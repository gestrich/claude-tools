"""Main entry point for voice watcher."""

import sys

from voice.application.file_watcher import FileWatcher


def main():
    """Run the voice file watcher."""
    # Default file to watch
    default_file = "~/Dropbox/ai.csv"

    # Get file path from command line if provided
    file_path = sys.argv[1] if len(sys.argv) > 1 else default_file

    print(f"Voice watcher starting...")
    print(f"File: {file_path}")
    print(f"Parser mode: enabled")
    print()

    watcher = FileWatcher(file_path)
    watcher.watch()


if __name__ == "__main__":
    main()
