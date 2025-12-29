"""Command executor for handling parsed commands."""

import subprocess
from pathlib import Path
from typing import Optional

from voice.domain.models import Command


class CommandExecutor:
    """Executes commands parsed from voice input."""

    def execute(self, command: Command) -> bool:
        """Execute a command.

        Args:
            command: The command to execute

        Returns:
            True if successful, False otherwise
        """
        handlers = {
            "openApp": self._open_app,
            "openFile": self._open_file,
            "scroll": self._scroll,
        }

        handler = handlers.get(command.type)
        if handler:
            try:
                return handler(command.args)
            except Exception as e:
                print(f"Error executing command {command.type}: {e}")
                return False
        else:
            print(f"Unknown command type: {command.type}")
            return False

    def _open_app(self, args: dict) -> bool:
        """Open an application.

        Args:
            args: Dictionary with 'app' key

        Returns:
            True if successful
        """
        app = args.get("app")
        if not app:
            print("Missing 'app' argument for openApp command")
            return False

        print(f"Opening {app}...")
        subprocess.run(["open", "-a", app], check=True)
        return True

    def _open_file(self, args: dict) -> bool:
        """Open a file in an application.

        Args:
            args: Dictionary with 'path' and 'app' keys

        Returns:
            True if successful
        """
        path = args.get("path")
        app = args.get("app")

        if not path:
            print("Missing 'path' argument for openFile command")
            return False

        # Expand path (handle ~ and wildcards)
        expanded_path = Path(path).expanduser()

        # If path contains wildcards, try to resolve
        if "*" in str(path):
            # Try to find the file using glob
            parent = expanded_path.parent
            pattern = expanded_path.name
            matches = list(parent.glob(pattern))
            if matches:
                expanded_path = matches[0]
            else:
                print(f"No files found matching: {path}")
                return False

        if not expanded_path.exists():
            print(f"File not found: {expanded_path}")
            return False

        print(f"Opening {expanded_path}...")

        if app:
            subprocess.run(["open", "-a", app, str(expanded_path)], check=True)
        else:
            subprocess.run(["open", str(expanded_path)], check=True)

        return True

    def _scroll(self, args: dict) -> bool:
        """Scroll in the frontmost application.

        Args:
            args: Dictionary with 'direction' and optional 'amount' keys

        Returns:
            True if successful
        """
        direction = args.get("direction", "down")
        amount = args.get("amount", 5)

        print(f"Scrolling {direction}...")

        # Map direction to AppleScript key codes
        if direction == "up":
            key_code = "126"  # Up arrow
        elif direction == "down":
            key_code = "125"  # Down arrow
        elif direction == "top":
            # Cmd+Up or Cmd+Home
            script = 'tell application "System Events" to key code 126 using command down'
            subprocess.run(["osascript", "-e", script], check=True)
            return True
        elif direction == "bottom":
            # Cmd+Down or Cmd+End
            script = 'tell application "System Events" to key code 125 using command down'
            subprocess.run(["osascript", "-e", script], check=True)
            return True
        else:
            print(f"Unknown scroll direction: {direction}")
            return False

        # Send arrow key multiple times
        for _ in range(amount):
            script = f'tell application "System Events" to key code {key_code}'
            subprocess.run(["osascript", "-e", script], check=True)

        return True
