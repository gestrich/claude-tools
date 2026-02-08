#!/bin/bash
# Entry point for Apple Shortcut SSH calls
# Usage: voice-plan.sh [--execute] "Voice transcribed text"
cd "$(dirname "$0")"
cli/.build/release/dev-pilot plan "$@"
