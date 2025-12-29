"""Service for parsing voice input using Claude."""

import json
import subprocess
from typing import Optional

from voice.domain.models import ParsedInput


# JSON schema for Claude's structured output
PARSE_SCHEMA = {
    "type": "object",
    "properties": {
        "sessionPrompt": {
            "type": ["string", "null"],
            "description": "The prompt to send to the active Claude session in the terminal"
        },
        "commands": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {
                        "type": "string",
                        "description": "Command type (e.g., 'openApp', 'scroll', 'openFile')"
                    },
                    "args": {
                        "type": "object",
                        "description": "Command arguments as key-value pairs"
                    }
                },
                "required": ["type", "args"]
            }
        }
    },
    "required": ["sessionPrompt", "commands"]
}

# Prompt template for parsing voice input
PARSE_PROMPT = """You are a voice command interpreter for a Claude Code session. The user is dictating commands and prompts via voice transcription.

Your job is to analyze the user's latest voice input and extract:
1. sessionPrompt: The actual prompt/message to send to the active Claude session
2. commands: Any special commands the user wants to execute (opening apps, scrolling documents, etc.)

## Supported Commands

- openApp: Open an application
  - args: {{"app": "Typora"}} or {{"app": "VSCode"}}

- openFile: Open a file in an application
  - args: {{"path": "/path/to/file", "app": "Typora"}}

- scroll: Scroll to a location in a document
  - args: {{"direction": "up|down|top|bottom", "amount": 10}}

## Context Messages (for reference only)
{context_messages}

## LATEST MESSAGE TO PROCESS (this is what you should parse)
{latest_message}

## Instructions

1. Parse the LATEST MESSAGE ONLY (prior messages are just context)
2. Extract the core prompt/request for Claude
3. Identify any commands the user wants to execute
4. Clean up transcription errors (e.g., "Tyra" -> "Typora", "V S code" -> "VSCode")
5. If the message is purely a prompt with no commands, set sessionPrompt and leave commands empty
6. If the message is purely commands with no prompt, set sessionPrompt to null

## Examples

Input: "Open Typora and write a blog post about AI safety"
Output:
{{{{
  "sessionPrompt": "Write a blog post about AI safety",
  "commands": [
    {{{{"type": "openApp", "args": {{{{"app": "Typora"}}}}}}}}
  ]
}}}}

Input: "Scroll down in the document"
Output:
{{{{
  "sessionPrompt": null,
  "commands": [
    {{{{"type": "scroll", "args": {{{{"direction": "down", "amount": 5}}}}}}}}
  ]
}}}}

Input: "Add error handling to the file upload function"
Output:
{{{{
  "sessionPrompt": "Add error handling to the file upload function",
  "commands": []
}}}}

Input: "Open the blog file in Typora then scroll to the bottom"
Output:
{{{{
  "sessionPrompt": null,
  "commands": [
    {{{{"type": "openFile", "args": {{{{"path": "~/Desktop/doc-drafts/*/blog.md", "app": "Typora"}}}}}}}},
    {{{{"type": "scroll", "args": {{{{"direction": "bottom"}}}}}}}}
  ]
}}}}

Now parse the latest message above and return the structured output.
"""


class ClaudeParser:
    """Parses voice input using Claude API."""

    def __init__(self, context_size: int = 10):
        """Initialize the parser.

        Args:
            context_size: Number of previous messages to include for context
        """
        self.context_size = context_size
        self.message_history: list[str] = []

    def add_message(self, message: str) -> None:
        """Add a message to the history.

        Args:
            message: The message to add
        """
        self.message_history.append(message)
        # Keep only the last N messages
        if len(self.message_history) > self.context_size:
            self.message_history = self.message_history[-self.context_size:]

    def parse(self, latest_message: str) -> Optional[ParsedInput]:
        """Parse the latest voice input using Claude.

        Args:
            latest_message: The latest message to parse

        Returns:
            ParsedInput object or None if parsing fails
        """
        # Add to history
        self.add_message(latest_message)

        # Build context (all but the last message)
        context_messages = ""
        if len(self.message_history) > 1:
            context_lines = [
                f"- {msg}" for msg in self.message_history[:-1]
            ]
            context_messages = "\n".join(context_lines)
        else:
            context_messages = "(No prior context)"

        # Build the full prompt
        prompt = PARSE_PROMPT.format(
            context_messages=context_messages,
            latest_message=latest_message
        )

        # Call Claude CLI
        try:
            result = self._call_claude(prompt)
            if result:
                return ParsedInput.from_dict(result)
        except Exception as e:
            print(f"Error parsing with Claude: {e}")
            return None

        return None

    def _call_claude(self, prompt: str) -> Optional[dict]:
        """Call Claude CLI and get structured output.

        Args:
            prompt: The prompt to send to Claude

        Returns:
            Parsed JSON response or None if call fails
        """
        schema_json = json.dumps(PARSE_SCHEMA)

        cmd = [
            'claude',
            '--dangerously-skip-permissions',
            '-p',
            '--verbose',
            '--output-format', 'json',
            '--json-schema', schema_json,
            prompt
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                print(f"Claude CLI error: {result.stderr}")
                return None

            # With --verbose, output is a JSON array - result is the last element
            output = json.loads(result.stdout)
            return output[-1]['structured_output']

        except subprocess.TimeoutExpired:
            print("Claude CLI call timed out")
            return None
        except json.JSONDecodeError as e:
            print(f"Failed to parse Claude output: {e}")
            return None
        except Exception as e:
            print(f"Error calling Claude: {e}")
            return None
