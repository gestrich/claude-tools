#!/bin/bash
# Debug script with verbose output to see what's happening

if [ -z "$1" ]; then
  echo "Usage: ./debug-send-verbose.sh \"your message\""
  exit 1
fi

MESSAGE="$1"

echo "========================================="
echo "Debug: Processing message"
echo "========================================="
echo "Message: $MESSAGE"
echo ""

cd "$(dirname "$0")"
export DEBUG_MESSAGE="$MESSAGE"
PYTHONPATH="$(pwd)/src" python3 << 'EOF'
import sys
import os

# Read message from environment
message = os.environ.get('DEBUG_MESSAGE', '')

print(f"[DEBUG] Starting parser test")
print(f"[DEBUG] Message: {message}")

from voice.application.claude_parser import ClaudeParser
from voice.application.command_executor import CommandExecutor
import subprocess

# Parse the message
parser = ClaudeParser()
executor = CommandExecutor()

print('[DEBUG] About to call parser.parse()')
print('[DEBUG] This should invoke: claude --dangerously-skip-permissions -p --verbose --output-format json ...')
print()

parsed = parser.parse(message)

if not parsed:
    print('[ERROR] Failed to parse message')
    sys.exit(1)

print(f'[DEBUG] Parse complete')
print(f'[DEBUG] Session Prompt: {parsed.session_prompt}')
print(f'[DEBUG] Commands: {len(parsed.commands)}')

for i, cmd in enumerate(parsed.commands):
    print(f'[DEBUG] Command {i}: type={cmd.type}, args={cmd.args}')

print()
print('[DEBUG] About to send to terminal via AppleScript')

# Send session prompt to terminal
if parsed.session_prompt:
    print(f'[DEBUG] Copying to clipboard: {parsed.session_prompt}')

    # Copy to clipboard
    result = subprocess.run(['pbcopy'], input=parsed.session_prompt.encode('utf-8'), capture_output=True)
    print(f'[DEBUG] pbcopy exit code: {result.returncode}')

    # Verify clipboard
    verify = subprocess.run(['pbpaste'], capture_output=True, text=True)
    print(f'[DEBUG] Clipboard contains: {verify.stdout}')

    print('[DEBUG] Executing AppleScript to paste into Terminal')

    # Use separate -e flags with delay for paste to complete
    result = subprocess.run([
        'osascript',
        '-e', 'tell application "Terminal" to activate',
        '-e', 'tell application "System Events" to keystroke "v" using command down',
        '-e', 'delay 0.2',
        '-e', 'tell application "System Events" to keystroke return'
    ], capture_output=True, text=True)
    print(f'[DEBUG] AppleScript exit code: {result.returncode}')

    if result.stderr:
        print(f'[DEBUG] AppleScript stderr: {result.stderr}')

    print('[DEBUG] ✓ AppleScript executed')
else:
    print('[DEBUG] No session prompt to send')

print()
print('========================================')
print('Done')
print('========================================')
EOF
