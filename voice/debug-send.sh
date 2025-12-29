#!/bin/bash
# Debug script to test voice processing without file monitoring

if [ -z "$1" ]; then
  echo "Usage: ./debug-send.sh \"your message\""
  echo ""
  echo "Examples:"
  echo "  ./debug-send.sh \"Open Typora\""
  echo "  ./debug-send.sh \"I'd like to write a blog about AI\""
  echo "  ./debug-send.sh \"Open Typora and write a blog post\""
  exit 1
fi

MESSAGE="$1"

echo "========================================="
echo "Debug: Processing message"
echo "========================================="
echo "Message: $MESSAGE"
echo ""

cd "$(dirname "$0")"
PYTHONPATH="$(pwd)/src" python3 << EOF
import sys
from voice.application.claude_parser import ClaudeParser
from voice.application.command_executor import CommandExecutor
import subprocess

# Parse the message
parser = ClaudeParser()
executor = CommandExecutor()

message = """$MESSAGE"""

print('Parsing with Claude...')
parsed = parser.parse(message)

if not parsed:
    print('ERROR: Failed to parse message')
    sys.exit(1)

print(f'✓ Parsed successfully')
print(f'  Session Prompt: {parsed.session_prompt}')
print(f'  Commands: {len(parsed.commands)}')
print()

# Execute commands
for cmd in parsed.commands:
    print(f'Executing command: {cmd.type}')
    print(f'  Args: {cmd.args}')
    result = executor.execute(cmd)
    print(f'  Result: {"✓ Success" if result else "✗ Failed"}')
    print()

# Send session prompt to terminal
if parsed.session_prompt:
    print(f'Sending to terminal: {parsed.session_prompt}')

    # Copy to clipboard and paste - using separate -e flags with delay
    subprocess.run(['pbcopy'], input=parsed.session_prompt.encode('utf-8'), check=True)

    subprocess.run([
        'osascript',
        '-e', 'tell application "Terminal" to activate',
        '-e', 'tell application "System Events" to keystroke "v" using command down',
        '-e', 'delay 0.2',
        '-e', 'tell application "System Events" to keystroke return'
    ], check=True)
    print('✓ Sent to terminal')
else:
    print('No session prompt to send')

print()
print('========================================')
print('Done')
print('========================================')
EOF
