#!/bin/bash
# voice-to-claude.sh
# Watches ~/Downloads/voice.txt and sends content to Terminal

FILE="$HOME/Downloads/voice.txt"
LAST_CONTENT=""

echo "Watching $FILE for changes..."
echo "Make sure your Claude Code terminal is the frontmost Terminal window."
echo "Press Ctrl+C to stop."
echo ""

while true; do
  if [[ -f "$FILE" ]]; then
    CONTENT=$(cat "$FILE" 2>/dev/null)
    if [[ "$CONTENT" != "$LAST_CONTENT" && -n "$CONTENT" ]]; then
      echo "[$(date '+%H:%M:%S')] Sending: $CONTENT"

      # Copy to clipboard and paste into Terminal
      echo -n "$CONTENT" | pbcopy
      osascript -e 'tell application "Terminal" to activate' \
                -e 'tell application "System Events" to keystroke "v" using command down' \
                -e 'tell application "System Events" to keystroke return'

      LAST_CONTENT="$CONTENT"
    fi
  fi
  sleep 1
done
