"""File watcher service for monitoring transcription file changes."""

import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

from voice.application.claude_parser import ClaudeParser
from voice.application.command_executor import CommandExecutor


class FileWatcher:
    """Watches a file for changes and sends new content to Terminal."""

    def __init__(self, file_path: str):
        """Initialize the file watcher.

        Args:
            file_path: Path to the file to watch
        """
        self.file_path = Path(file_path).expanduser()
        self.last_content = ""
        self.parser = ClaudeParser()
        self.executor = CommandExecutor()

    def log(self, message: str) -> None:
        """Print a timestamped log message.

        Args:
            message: The message to log
        """
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] {message}")

    def read_file(self) -> Optional[str]:
        """Read the current file content.

        Returns:
            File content as string, or None if file doesn't exist
        """
        try:
            if self.file_path.exists():
                return self.file_path.read_text()
            return None
        except Exception as e:
            self.log(f"Error reading file: {e}")
            return None

    def extract_new_content(self, current_content: str) -> str:
        """Extract only the newly appended content.

        Args:
            current_content: The current full file content

        Returns:
            The new content that was appended
        """
        if current_content.startswith(self.last_content):
            return current_content[len(self.last_content):]
        return current_content

    def send_to_terminal(self, text: str) -> None:
        """Send text to Terminal via clipboard and paste.

        Args:
            text: The text to send
        """
        try:
            # Copy to clipboard
            subprocess.run(['pbcopy'], input=text.encode('utf-8'), check=True)

            # Paste into Terminal and hit enter - using separate -e flags with delay
            subprocess.run([
                'osascript',
                '-e', 'tell application "Terminal" to activate',
                '-e', 'tell application "System Events" to keystroke "v" using command down',
                '-e', 'delay 0.2',
                '-e', 'tell application "System Events" to keystroke return'
            ], check=True)

        except subprocess.CalledProcessError as e:
            self.log(f"Error sending to terminal: {e}")

    def process_input(self, text: str) -> None:
        """Process input text through Claude parser.

        Args:
            text: The input text to process
        """
        # Parse with Claude
        self.log("Parsing input with Claude...")
        parsed = self.parser.parse(text)

        if not parsed:
            self.log("Failed to parse input, sending directly to terminal")
            self.send_to_terminal(text)
            return

        self.log(f"Parsed - Prompt: {parsed.session_prompt}, Commands: {len(parsed.commands)}")

        # Execute commands
        for cmd in parsed.commands:
            self.log(f"Executing command: {cmd.type}")
            self.executor.execute(cmd)

        # Send session prompt to terminal if present
        if parsed.session_prompt:
            self.log(f"Sending to terminal: {parsed.session_prompt}")
            self.send_to_terminal(parsed.session_prompt)

    def watch(self, interval: float = 1.0) -> None:
        """Watch the file for changes and send new content to Terminal.

        Args:
            interval: Seconds to wait between checks (default: 1.0)
        """
        self.log(f"Watching {self.file_path} for changes...")
        self.log("Make sure your Claude Code terminal is the frontmost Terminal window.")
        self.log("Press Ctrl+C to stop.")
        print()

        try:
            while True:
                self.log("Checking file...")

                if not self.file_path.exists():
                    self.log("File does not exist")
                else:
                    content = self.read_file()
                    if content is None:
                        continue

                    self.log(f"File exists, content length: {len(content)}")

                    if content != self.last_content and content:
                        new_text = self.extract_new_content(content)
                        self.log(f"New text appended: {new_text}")

                        self.process_input(new_text)
                        self.last_content = content
                    else:
                        self.log("No change detected")

                time.sleep(interval)

        except KeyboardInterrupt:
            self.log("Stopping watcher...")
