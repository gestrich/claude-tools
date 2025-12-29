#!/bin/bash
# Test the voice parser by sending sample input

if [ -z "$1" ]; then
  echo "Usage: ./test-input.sh \"your test message\""
  echo ""
  echo "Examples:"
  echo "  ./test-input.sh \"Open Typora and write a blog post\""
  echo "  ./test-input.sh \"Add error handling to the upload function\""
  echo "  ./test-input.sh \"Open the blog file in Typora then scroll to the bottom\""
  exit 1
fi

MESSAGE="$1"
FILE="$HOME/Dropbox/ai.csv"

echo "Appending to $FILE:"
echo "  \"$MESSAGE\""
echo ""

echo "$MESSAGE" >> "$FILE"

echo "✓ Message sent. Check the voice watcher output to see how it was parsed."
