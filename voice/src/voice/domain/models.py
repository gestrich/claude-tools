"""Domain models for voice watcher."""

from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class FileUpdate:
    """Represents a file update event."""
    file_path: Path
    new_content: str
    timestamp: float


@dataclass
class Command:
    """Represents a command to execute."""
    type: str
    args: dict


@dataclass
class ParsedInput:
    """Represents parsed voice input from Claude."""
    session_prompt: Optional[str]
    commands: list[Command]

    @classmethod
    def from_dict(cls, data: dict) -> "ParsedInput":
        """Create ParsedInput from dictionary.

        Args:
            data: Dictionary with 'sessionPrompt' and 'commands' keys

        Returns:
            ParsedInput instance
        """
        commands = [
            Command(type=cmd.get("type", ""), args=cmd.get("args", {}))
            for cmd in data.get("commands", [])
        ]
        return cls(
            session_prompt=data.get("sessionPrompt"),
            commands=commands
        )
