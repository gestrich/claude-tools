#!/bin/bash
# Clear the ai.csv file to start fresh

FILE="$HOME/Dropbox/ai.csv"

echo "Clearing $FILE..."
echo -n "" > "$FILE"
echo "✓ File cleared"
