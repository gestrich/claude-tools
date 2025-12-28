#!/bin/bash

# Sync all commands from claude-tools to ~/.claude/commands
# Usage: ./sync-commands.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/commands"
TARGET_DIR="$HOME/.claude/commands"

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Copy all .md files from source to target
if [ -d "$SOURCE_DIR" ]; then
    echo "Syncing commands from $SOURCE_DIR to $TARGET_DIR..."
    cp "$SOURCE_DIR"/*.md "$TARGET_DIR/" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "✓ Commands synced successfully!"
        echo ""
        echo "Synced files:"
        ls -1 "$SOURCE_DIR"/*.md 2>/dev/null | xargs -n 1 basename
    else
        echo "✗ No .md files found in $SOURCE_DIR"
        exit 1
    fi
else
    echo "✗ Source directory $SOURCE_DIR not found"
    exit 1
fi
