#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build if binary is missing or sources are newer
BINARY="$SCRIPT_DIR/.build/release/dev-pilot"
NEWEST_SOURCE=$(find "$SCRIPT_DIR/Sources" -name '*.swift' -newer "$BINARY" 2>/dev/null | head -1)
if [ ! -f "$BINARY" ] || [ -n "$NEWEST_SOURCE" ]; then
    echo "Building dev-pilot..."
    swift build -c release --package-path "$SCRIPT_DIR"
fi

# Check if a subcommand is provided (first non-flag argument)
SUBCOMMAND=""
for arg in "$@"; do
    if [[ "$arg" != --* ]]; then
        SUBCOMMAND="$arg"
        break
    fi
done

# If no recognized subcommand: no args → execute, voice text → plan
if [[ "$SUBCOMMAND" != "plan" && "$SUBCOMMAND" != "execute" ]]; then
    if [ $# -eq 0 ]; then
        exec "$SCRIPT_DIR/.build/release/dev-pilot" execute "$@"
    else
        exec "$SCRIPT_DIR/.build/release/dev-pilot" plan --execute "$@"
    fi
else
    exec "$SCRIPT_DIR/.build/release/dev-pilot" "$@"
fi
