#!/bin/bash
# View the voice watcher logs

LOG_DIR="/tmp/claude/-Users-bill-Developer-personal-claude-tools/tasks"

# Find the most recent voice watcher log
LOG_FILE=$(ls -t "$LOG_DIR"/*.output 2>/dev/null | head -1)

if [ -z "$LOG_FILE" ]; then
  echo "No log file found"
  exit 1
fi

echo "Watching log: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo ""

tail -f "$LOG_FILE"
