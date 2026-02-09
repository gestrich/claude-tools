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

# Run dev-pilot with all arguments passed through
exec "$SCRIPT_DIR/.build/release/dev-pilot" "$@"
