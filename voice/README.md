# Voice

Intelligent voice transcription watcher for Claude Code with command interpretation.

Watches a file (default: `~/Dropbox/ai.csv`) for changes and intelligently processes voice input to:
- Extract commands (open apps, scroll documents, etc.)
- Send prompts to the active Claude Code session

## Setup

```bash
pip install -e ".[dev]"
```

## Usage

Watch the default file with intelligent parsing (recommended):
```bash
python -m voice
```

Watch a custom file:
```bash
python -m voice ~/path/to/file.txt
```

Disable intelligent parsing (direct mode):
```bash
python -m voice --no-parser
```

Or after installation:
```bash
voice
voice ~/path/to/file.txt
voice --no-parser
```

## How it works

### Intelligent Mode (default)

1. Monitors the file for changes every second
2. When new content is appended, sends it to Claude for parsing
3. Claude analyzes the last 10 messages for context and extracts:
   - **Session Prompt**: The actual message/request for the active Claude session
   - **Commands**: Special actions to execute (open apps, scroll, etc.)
4. Executes any commands
5. Sends the session prompt to the Terminal

### Direct Mode (`--no-parser`)

Sends new text directly to the Terminal without interpretation.

## Supported Commands

When using intelligent mode, you can say things like:

- **"Open Typora and write a blog post about AI"**
  - Opens Typora
  - Sends "write a blog post about AI" to Claude

- **"Open the blog file in Typora then scroll to the bottom"**
  - Opens blog.md in Typora
  - Scrolls to bottom

- **"Scroll down in the document"**
  - Scrolls down 5 lines in the frontmost app

### Available Commands

- `openApp`: Open an application (e.g., Typora, VSCode)
- `openFile`: Open a file in an application
- `scroll`: Scroll in a document (up, down, top, bottom)

## Examples

```
You: "Open Typora"
→ Opens Typora application

You: "Add error handling to the upload function"
→ Sends "Add error handling to the upload function" to Claude

You: "Open VSCode and refactor the authentication module"
→ Opens VSCode
→ Sends "refactor the authentication module" to Claude
```

## Testing

### Direct Testing (Recommended for Debugging)

Test voice processing directly without the file watcher:

```bash
# Send a message directly to the parser and execute
./debug-send.sh "Write a function to parse JSON"

# Verbose mode with detailed debug output
./debug-send-verbose.sh "Open Typora and write a blog post"
```

This bypasses the file watcher and runs in the foreground, making it easier to debug:
- See immediate output and errors
- No background processes to manage
- Perfect for testing parser behavior

Example test cases:
```bash
./debug-send.sh "Add error handling to the upload function"
./debug-send.sh "Open Typora"
./debug-send.sh "Open VSCode and refactor the authentication module"
```

### File Watcher Testing

Test via the file watcher (mimics real voice transcription workflow):

```bash
# Send a test message to the watched file
./test-input.sh "Open Typora and write a blog post about AI"

# View the watcher logs in real-time
./view-logs.sh

# Clear the input file to start fresh
./clear-input.sh
```

## Development

Run tests:
```bash
pytest
```
