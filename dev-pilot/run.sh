#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

# Check if --config is already provided
HAS_CONFIG=false
for arg in "$@"; do
    if [[ "$arg" == "--config" ]]; then
        HAS_CONFIG=true
        break
    fi
done

# If no recognized subcommand, default to "plan" with all args as the voice text
if [[ "$SUBCOMMAND" != "plan" && "$SUBCOMMAND" != "execute" ]]; then
    CONFIG_ARGS=()
    if [ "$HAS_CONFIG" = false ] && [ -f "$PROJECT_ROOT/repos.json" ]; then
        CONFIG_ARGS=(--config "$PROJECT_ROOT/repos.json")
    fi
    exec "$SCRIPT_DIR/.build/release/dev-pilot" plan "${CONFIG_ARGS[@]}" "$@"
else
    if [ "$HAS_CONFIG" = false ] && [ -f "$PROJECT_ROOT/repos.json" ]; then
        # Insert --config after the subcommand
        FIRST_ARG="$1"
        shift
        exec "$SCRIPT_DIR/.build/release/dev-pilot" "$FIRST_ARG" --config "$PROJECT_ROOT/repos.json" "$@"
    else
        exec "$SCRIPT_DIR/.build/release/dev-pilot" "$@"
    fi
fi
