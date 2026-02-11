#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build the project if needed
if [ ! -f "$SCRIPT_DIR/.build/release/dev-pilot" ]; then
    echo "Building dev-pilot..."
    cd "$SCRIPT_DIR"
    swift build -c release
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
