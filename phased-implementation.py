#!/usr/bin/env python3
"""
Phased implementation automation script (Python version)
Usage: ./phased-implementation.py <planning-document.md> [max-minutes]
"""

import sys
import os
import json
import subprocess
import time
import threading
import shutil
from pathlib import Path
from datetime import timedelta
from typing import Dict, List, Optional

# ANSI color codes
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

# JSON schema for getting phase status
STATUS_SCHEMA = {
    "type": "object",
    "properties": {
        "phases": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "description": {"type": "string"},
                    "status": {"type": "string", "enum": ["pending", "in_progress", "completed"]}
                },
                "required": ["description", "status"]
            }
        },
        "nextPhaseIndex": {
            "type": "integer",
            "description": "Index of the next phase to execute (0-based), or -1 if all complete"
        }
    },
    "required": ["phases", "nextPhaseIndex"]
}

# JSON schema for execution result
EXECUTION_SCHEMA = {
    "type": "object",
    "properties": {
        "success": {"type": "boolean", "description": "Whether the phase was completed successfully"}
    },
    "required": ["success"]
}


def format_time(seconds: int) -> str:
    """Format seconds as HH:MM:SS"""
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


class Timer:
    """Live timer display that runs in background thread"""
    def __init__(self, max_runtime_seconds: int, script_start_time: float):
        self.max_runtime_seconds = max_runtime_seconds
        self.script_start_time = script_start_time
        self.phase_start_time = 0
        self.running = False
        self.thread = None

    def start(self):
        """Start the live timer display"""
        self.phase_start_time = time.time()
        self.running = True

        try:
            term_height = shutil.get_terminal_size().lines
            # Set scroll region to exclude bottom line: \033[{top};{bottom}r
            # This prevents content from scrolling into the timer line
            sys.stdout.write(f"\033[1;{term_height-1}r")
            # Move cursor to a safe position
            sys.stdout.write(f"\033[{term_height-1};1H")
            sys.stdout.flush()
        except:
            pass

        self.thread = threading.Thread(target=self._update_timer, daemon=True)
        self.thread.start()

    def stop(self):
        """Stop the live timer"""
        self.running = False
        if self.thread:
            self.thread.join(timeout=1)

        # Reset scroll region and clear timer line
        try:
            term_height = shutil.get_terminal_size().lines
            # Reset scroll region to full screen: \033[r
            sys.stdout.write("\033[r")
            # Move to bottom line and clear it
            sys.stdout.write(f"\033[{term_height};1H\033[K")
            # Move cursor to a normal position
            sys.stdout.write(f"\033[{term_height-1};1H\n")
            sys.stdout.flush()
        except:
            print(f"\r{' ' * 80}\r", flush=True)

    def _update_timer(self):
        """Background thread that updates timer display"""
        last_line_content = ""

        while self.running:
            now = time.time()
            phase_elapsed = int(now - self.phase_start_time)
            total_elapsed = int(now - self.script_start_time)

            timer_display = (
                f"{Colors.CYAN}⏱  Phase: {format_time(phase_elapsed)} | "
                f"Total: {format_time(total_elapsed)} of {format_time(self.max_runtime_seconds)}{Colors.NC}"
            )

            try:
                # Get terminal dimensions
                term_width, term_height = shutil.get_terminal_size()

                # Pad to fit terminal width
                display_len = len(timer_display)
                if display_len < term_width:
                    timer_display = timer_display + (' ' * (term_width - display_len))
                elif display_len > term_width:
                    timer_display = timer_display[:term_width]

                # Use absolute positioning - move to bottom left, clear line, write timer
                # Don't save/restore cursor - always write to absolute bottom
                # \033[{row};{col}H = move to row,col; \033[K = clear to end of line
                sys.stdout.write(f"\033[{term_height};1H\033[K{timer_display}")
                sys.stdout.flush()

                last_line_content = timer_display
            except Exception as e:
                # Fallback to simple overwrite if terminal size unavailable
                sys.stdout.write(f"\r{timer_display}   ")
                sys.stdout.flush()

            time.sleep(0.5)  # Update more frequently for smoother display


def clauded(instruction: str, schema: dict, timer: Optional[Timer] = None) -> dict:
    """Run claude command with JSON output"""
    schema_json = json.dumps(schema)
    cmd = [
        'caffeinate', '-dimsu',
        'claude', '--dangerously-skip-permissions', '-p', '--verbose',
        '--output-format', 'json',
        '--json-schema', schema_json,
        instruction
    ]

    # Start timer if provided
    if timer:
        timer.start()

    try:
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise RuntimeError(f"Claude command failed: {result.stderr}")

        # With --verbose, output is a JSON array - result is the last element
        output = json.loads(result.stdout)
        return output[-1]['structured_output']
    finally:
        # Stop timer if it was started
        if timer:
            timer.stop()


def get_phase_status(planning_doc: str) -> dict:
    """Get current phase status from Claude"""
    instruction = f"""Look at {planning_doc} and analyze the phased implementation plan.

Return a JSON with:
1. phases: Array of all phases with their description and current status (pending/in_progress/completed)
2. nextPhaseIndex: The index (0-based) of the next phase to execute, or -1 if all phases are complete

Determine status by checking if each phase has been marked as complete in the document."""

    return clauded(instruction, STATUS_SCHEMA)


def execute_phase(planning_doc: str, phase_index: int, phase_description: str, timer: Optional[Timer] = None) -> dict:
    """Execute a single phase"""
    instruction = f"""Look at {planning_doc} for background.

You are working on Phase {phase_index + 1}: {phase_description}

Complete ONLY this phase by:
1. Implementing the required changes
2. Ensuring the build succeeds
3. Updating the markdown document to mark this phase as completed with any relevant technical notes
4. Committing your changes

Return success: true if the phase was completed successfully, false otherwise."""

    return clauded(instruction, EXECUTION_SCHEMA, timer)


def select_planning_doc(proposed_dir: str = "docs/proposed") -> Optional[str]:
    """Interactive file selection from proposed directory"""
    if not os.path.isdir(proposed_dir):
        print(f"{Colors.RED}Error: Directory not found: {proposed_dir}{Colors.NC}")
        return None

    # Find the last 5 recently modified .md files
    files = sorted(
        Path(proposed_dir).glob("*.md"),
        key=lambda p: p.stat().st_mtime,
        reverse=True
    )[:5]

    if not files:
        print(f"{Colors.RED}Error: No .md files found in {proposed_dir}{Colors.NC}")
        return None

    print(f"{Colors.BLUE}No planning document specified.{Colors.NC}")
    print(f"Last {Colors.GREEN}{len(files)}{Colors.NC} modified files in {Colors.GREEN}{proposed_dir}{Colors.NC}:\n")

    for i, file in enumerate(files, 1):
        print(f"  {Colors.YELLOW}{i}{Colors.NC}) {file.name}")

    print()
    selection = input(f"Select a file to implement [1-{len(files)}] (default: 1): ").strip()

    if not selection:
        selection = "1"

    try:
        idx = int(selection) - 1
        if 0 <= idx < len(files):
            return str(files[idx].absolute())
        else:
            print(f"{Colors.RED}Invalid selection. Must be between 1 and {len(files)}.{Colors.NC}")
            return None
    except ValueError:
        print(f"{Colors.RED}Invalid selection.{Colors.NC}")
        return None


def main():
    # Parse arguments
    max_runtime_seconds = 90 * 60  # default 90 minutes

    if len(sys.argv) < 2:
        planning_doc = select_planning_doc()
        if not planning_doc:
            sys.exit(1)
        move_on_complete = True
    else:
        planning_doc = sys.argv[1]
        move_on_complete = False
        if len(sys.argv) >= 3:
            max_runtime_seconds = int(sys.argv[2]) * 60

    # Validate planning document exists
    if not os.path.isfile(planning_doc):
        print(f"{Colors.RED}Error: Planning document not found: {planning_doc}{Colors.NC}")
        sys.exit(1)

    planning_doc = str(Path(planning_doc).absolute())

    # Print header
    print(f"{Colors.BLUE}{'=' * 50}{Colors.NC}")
    print(f"{Colors.BLUE}Phased Implementation Automation (Python){Colors.NC}")
    print(f"{Colors.BLUE}{'=' * 50}{Colors.NC}")
    print(f"Planning document: {Colors.GREEN}{planning_doc}{Colors.NC}")
    print(f"Max runtime: {Colors.GREEN}{format_time(max_runtime_seconds)}{Colors.NC}")
    print(f"{Colors.BLUE}{'=' * 50}{Colors.NC}\n")

    # Get initial phase status
    print(f"{Colors.CYAN}Fetching phase information...{Colors.NC}")
    try:
        status = get_phase_status(planning_doc)
    except Exception as e:
        print(f"{Colors.RED}Error fetching phase status: {e}{Colors.NC}")
        sys.exit(1)

    phases = status['phases']
    next_phase_idx = status['nextPhaseIndex']

    # Display phase overview
    print(f"\n{Colors.BLUE}{'=' * 50}{Colors.NC}")
    print(f"{Colors.BLUE}Implementation Steps{Colors.NC}")
    print(f"{Colors.BLUE}{'=' * 50}{Colors.NC}")
    print(f"Total steps: {Colors.GREEN}{len(phases)}{Colors.NC}\n")

    for i, phase in enumerate(phases):
        status_color = Colors.GREEN if phase['status'] == 'completed' else Colors.YELLOW
        status_symbol = '✓' if phase['status'] == 'completed' else '○'
        print(f"  {status_color}{i + 1}: {phase['description']}{Colors.NC}")

    print(f"{Colors.BLUE}{'=' * 50}{Colors.NC}\n")

    if next_phase_idx == -1:
        print(f"{Colors.GREEN}All steps already complete!{Colors.NC}")
        sys.exit(0)

    print(f"{Colors.CYAN}Starting from Step {next_phase_idx + 1}: {phases[next_phase_idx]['description']}{Colors.NC}\n")

    # Main execution loop
    script_start = time.time()
    timer = Timer(max_runtime_seconds, script_start)
    iteration = 1

    while next_phase_idx != -1:
        # Check time limit
        elapsed = time.time() - script_start
        if elapsed >= max_runtime_seconds:
            print(f"{Colors.YELLOW}Time limit reached ({format_time(max_runtime_seconds)}){Colors.NC}")
            break

        # Execute current phase
        current_phase = phases[next_phase_idx]
        total_steps = len(phases)

        print(f"{Colors.BLUE}{'=' * 50}{Colors.NC}")
        print(f"{Colors.YELLOW}Step {next_phase_idx + 1} of {total_steps} -> {current_phase['description']}{Colors.NC}")
        print(f"{Colors.BLUE}{'-' * 50}{Colors.NC}")
        print(f"{Colors.BLUE}Running claude...{Colors.NC}\n")

        phase_start = time.time()

        try:
            result = execute_phase(planning_doc, next_phase_idx, current_phase['description'], timer)
        except Exception as e:
            print(f"\n{Colors.RED}Phase {next_phase_idx + 1} failed: {e}{Colors.NC}")
            phase_elapsed = time.time() - phase_start
            total_elapsed = time.time() - script_start
            print(f"{Colors.CYAN}⏱  Phase time: {format_time(int(phase_elapsed))} | Total: {format_time(int(total_elapsed))}{Colors.NC}")
            sys.exit(1)

        phase_elapsed = time.time() - phase_start
        total_elapsed = time.time() - script_start

        if not result.get('success', False):
            print(f"\n{Colors.RED}Step {next_phase_idx + 1} reported failure{Colors.NC}")
            print(f"{Colors.CYAN}⏱  Step time: {format_time(int(phase_elapsed))} | Total: {format_time(int(total_elapsed))}{Colors.NC}")
            sys.exit(1)

        print(f"\n{Colors.GREEN}Step {next_phase_idx + 1} completed successfully{Colors.NC}")
        print(f"{Colors.CYAN}⏱  Step time: {format_time(int(phase_elapsed))} | Total: {format_time(int(total_elapsed))}{Colors.NC}")
        print(f"{Colors.BLUE}{'-' * 50}{Colors.NC}\n")

        # Get updated status
        print(f"{Colors.CYAN}Fetching updated phase status...{Colors.NC}")
        try:
            status = get_phase_status(planning_doc)
        except Exception as e:
            print(f"{Colors.RED}Error fetching phase status: {e}{Colors.NC}")
            sys.exit(1)

        phases = status['phases']
        next_phase_idx = status['nextPhaseIndex']

        # Continue to next step if available
        if next_phase_idx != -1:
            time.sleep(2)

        iteration += 1

    # Final summary
    total_time = time.time() - script_start
    print(f"\n{Colors.BLUE}{'=' * 50}{Colors.NC}")

    if next_phase_idx == -1:
        print(f"{Colors.GREEN}✓ All steps completed successfully!{Colors.NC}")
    else:
        remaining = sum(1 for p in phases if p['status'] != 'completed')
        print(f"{Colors.YELLOW}Time limit reached - {remaining} steps may remain{Colors.NC}")

    print(f"{Colors.BLUE}{'=' * 50}{Colors.NC}")
    print(f"Total steps executed: {Colors.GREEN}{iteration - 1}{Colors.NC}")
    print(f"Total time: {Colors.CYAN}{format_time(int(total_time))}{Colors.NC}")
    print(f"Planning document: {Colors.GREEN}{planning_doc}{Colors.NC}\n")

    # Move completed spec to docs/completed (only for interactive selection)
    if next_phase_idx == -1 and move_on_complete:
        completed_dir = Path("docs/completed")
        completed_dir.mkdir(parents=True, exist_ok=True)
        completed_path = completed_dir / Path(planning_doc).name

        # Move file
        Path(planning_doc).rename(completed_path)
        print(f"{Colors.GREEN}Moved spec to {completed_path}{Colors.NC}")

        # Git commit
        subprocess.run(['git', 'add', planning_doc, str(completed_path)])
        subprocess.run(['git', 'commit', '-m', 'Move completed spec to docs/completed'])
        print(f"{Colors.GREEN}Committed spec move{Colors.NC}\n")

    # Play completion sound
    if next_phase_idx == -1:
        subprocess.run(['afplay', '/System/Library/Sounds/Glass.aiff'])
        subprocess.run(['afplay', '/System/Library/Sounds/Glass.aiff'])


if __name__ == '__main__':
    main()
