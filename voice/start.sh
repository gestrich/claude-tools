#!/bin/bash
# Start the voice file watcher

cd "$(dirname "$0")"
PYTHONPATH="$(pwd)/src" python3 -m voice "$@"
