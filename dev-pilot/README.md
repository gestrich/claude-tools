# DevPilot

A voice-driven development pipeline that transforms spoken development tasks into automated implementation plans and execution.

## What It Does

DevPilot enables hands-free development workflow:

1. **Speak** your development task into an iPhone (via Apple Shortcut)
2. **Transcribe** the audio to text using on-device transcription
3. **SSH** the text to your Mac where DevPilot processes it
4. **Generate** a phased implementation plan using Claude AI
5. **Execute** the plan step-by-step, calling Claude for each phase

The system is designed to be tolerant of voice transcription errors by using recent commit history and codebase context to infer intent.

## Architecture

DevPilot consists of two main subcommands:

### `plan` - Generate Implementation Plans

Takes voice-transcribed text and generates a structured markdown plan with three initial phases:

- **Phase 1: Interpret the Request** - Explores codebase and recent commits to understand what's being asked
- **Phase 2: Gather Architectural Guidance** - Reviews relevant skills and architecture docs from repo config
- **Phase 3: Plan the Implementation** - Creates concrete implementation steps and dynamically generates additional phases (4 through N)

Generated plans are saved to `docs/proposed/<filename>.md` in the target repository.

### `execute` - Run Implementation Phases

Executes phases from a planning document one-by-one:

- Runs each phase in its own Claude CLI session (focused context)
- Displays live timer (phase + total runtime)
- Enforces maximum runtime limit
- Re-reads phase status after each step (supports dynamic phase generation)
- Moves completed plans to `docs/completed/`

## Installation

### Prerequisites

- macOS 10.15+
- Swift 5.9+
- [Claude CLI](https://docs.anthropic.com/claude/docs/cli) installed and configured
- (Optional) iPhone with Shortcuts app for voice input

### Build

```bash
# From the project root
make build

# Or manually
cd cli
swift build -c release
```

The binary will be available at `cli/.build/release/dev-pilot`

## Usage

### Basic Commands

```bash
# Generate a plan from voice text
dev-pilot plan "Fix the bug where waypoints disappear after saving"

# Generate and immediately execute (repo auto-detected)
dev-pilot plan --execute "Add a logout button to the settings page"

# Execute an existing plan with repo path
dev-pilot execute --plan docs/proposed/waypoint-fix.md --repo /path/to/repo

# Execute with custom time limit
dev-pilot execute --plan docs/proposed/feature.md --repo /path/to/repo --max-minutes 120
```

**Note:** Execution requires the `--repo` parameter pointing to your main repository. When using `plan --execute`, this is automatically determined. A worktree will be created in `~/Desktop/worktrees/<repo-name>/` for isolated work.

### Repository Configuration

DevPilot uses `repos.json` to provide context about your repositories. By default, it looks for the configuration at `~/.dev-pilot/repos.json`. You can override this with the `--config` flag.

Create the configuration directory and file:

```bash
mkdir -p ~/.dev-pilot
```

Then create `~/.dev-pilot/repos.json` with the following structure:

```json
{
  "repositories": [
    {
      "id": "my-ios-app",
      "path": "/Users/you/Developer/my-ios-app",
      "description": "Main iOS application for flight planning",
      "recentFocus": "Working on waypoint management improvements",
      "skills": ["swift-testing", "design-kit"],
      "architectureDocs": ["docs/architecture.md", "docs/api-guide.md"],
      "verification": {
        "commands": ["xcodebuild -scheme App -sdk iphonesimulator test"],
        "notes": "Run on iPhone 16 simulator"
      },
      "pullRequest": {
        "baseBranch": "develop",
        "branchNamingConvention": "feature/JIRA-123-description",
        "notes": "Assign to your-name for review"
      }
    }
  ]
}
```

**Configuration fields:**
- `id` - Unique identifier for the repository
- `path` - Absolute path to the repository
- `description` - What the repository does
- `recentFocus` - (Optional) Current development focus
- `skills` - List of Claude skills to use for this repo
- `architectureDocs` - Documentation files to reference during planning
- `verification.commands` - Commands to run for testing
- `verification.notes` - (Optional) Additional testing notes
- `pullRequest.baseBranch` - Target branch for PRs
- `pullRequest.branchNamingConvention` - How to name feature branches
- `pullRequest.notes` - (Optional) PR creation notes

### Voice Integration

For hands-free operation via iPhone, see the [Apple Shortcut Setup Guide](../docs/apple-shortcut-setup.md).

The voice entry point is `voice-plan.sh` in the project root:

```bash
# Called by Apple Shortcut via SSH
./voice-plan.sh "Fix the bug where waypoints disappear after saving"

# With auto-execute
./voice-plan.sh --execute "Add a logout button to the settings page"
```

## How It Works

### Worktree Isolation

DevPilot uses git worktrees to isolate each implementation from your main repository:

1. **Worktree Creation** - Before execution begins, a new worktree is created in `~/Desktop/worktrees/<repo-name>/<timestamp>`
2. **Base Branch** - The worktree is based on the `baseBranch` specified in your `repos.json` config (e.g., `main`, `develop`)
3. **Isolated Work** - All implementation happens in the worktree, keeping your main repository clean
4. **Automatic Cleanup** - After the PR is created, the worktree is automatically removed

This ensures that:
- Multiple implementations can run simultaneously without conflicts
- Your main working directory remains untouched
- Each task starts from a clean state based on the latest default branch
- Failed implementations don't leave your repository in a dirty state

### Phase Execution Flow

1. **Plan Generation**
   - Voice text is matched to a repository based on description and recent focus
   - Claude interprets the request (handling transcription errors)
   - A structured plan with 3 initial phases is generated

2. **Worktree Setup**
   - A git worktree is created in `~/Desktop/worktrees/<repo-name>/`
   - Based on the repository's default branch (from `repos.json`)
   - All subsequent work happens in this isolated environment

3. **Phase Execution**
   - Phase 1 explores the codebase to understand the request
   - Phase 2 gathers architectural constraints and guidelines
   - Phase 3 creates detailed implementation steps and appends new phases
   - Phases 4+ implement the actual changes
   - Final phases handle testing and PR creation

4. **Dynamic Phase Generation**
   - Phase 3 appends implementation phases to the markdown document
   - The executor re-reads the document after each phase
   - Newly added phases are automatically discovered and executed

5. **Cleanup**
   - After successful completion, the worktree is removed
   - On failure, the worktree is also cleaned up to prevent disk clutter

### Repository Context

Each phase execution receives full repository metadata:
- Architectural documentation to reference
- Verification commands for testing
- Recent commits for understanding current state
- Claude skills relevant to this codebase

## Command Reference

### `dev-pilot plan`

Generate an implementation plan from voice text.

**Arguments:**
- `<text>` - Voice-transcribed text describing the task (required)

**Options:**
- `--execute` - Execute the plan immediately after generating it
- `--config <path>` - Path to repos.json config file (default: ~/.dev-pilot/repos.json)

**Examples:**
```bash
dev-pilot plan "Fix authentication bug"
dev-pilot plan --execute "Add dark mode support"
dev-pilot plan --config ~/my-repos.json "Refactor database layer"
```

### `dev-pilot execute`

Execute phases from a planning document.

**Options:**
- `--plan <path>` - Path to planning document (omit for interactive selection)
- `--repo <path>` - Path to main repository (required, used to create worktree)
- `--max-minutes <int>` - Maximum runtime in minutes (default: 90)
- `--config <path>` - Path to repos.json config file (default: ~/.dev-pilot/repos.json)

**Note:** The `--repo` option is required and should point to your main repository. A worktree will be automatically created based on this repository and the `baseBranch` from `repos.json`.

**Examples:**
```bash
# When using plan --execute, the repo is automatically determined
dev-pilot plan --execute "Add feature"

# When executing manually, provide the main repo path
dev-pilot execute --plan docs/proposed/feature.md --repo /path/to/main/repo
dev-pilot execute --plan docs/proposed/feature.md --repo /path/to/main/repo --max-minutes 120
```

## Project Structure

```
cli/
├── Package.swift
├── Sources/DevPilot/
│   ├── DevPilot.swift              # Entry point
│   ├── Commands/
│   │   ├── PlanCommand.swift       # Plan generation command
│   │   └── ExecuteCommand.swift    # Phase execution command
│   ├── Models/
│   │   ├── RepoConfig.swift        # Repository configuration types
│   │   ├── PhaseStatus.swift       # Phase tracking models
│   │   └── ClaudeResponse.swift    # Claude API response types
│   └── Services/
│       ├── ClaudeService.swift     # Claude CLI subprocess wrapper
│       ├── PlanGenerator.swift     # Plan generation logic
│       ├── PhaseExecutor.swift     # Phase execution engine
│       └── TimerDisplay.swift      # Live timer display
└── Tests/DevPilotTests/            # Integration tests
```

## Testing

Run the test suite:

```bash
cd cli
swift test
```

Tests cover:
- Repository configuration loading
- Model serialization/deserialization
- Timer display formatting
- CLI argument parsing
- Error handling

## Troubleshooting

### Claude CLI Not Found

Ensure Claude CLI is installed and in your PATH:
```bash
claude --version
```

If not found, SSH sessions may not load your shell profile. Update `voice-plan.sh` to source your profile or use absolute paths.

### Plan Generation Fails

- Verify `~/.dev-pilot/repos.json` exists and is valid JSON
- Check that Claude CLI is authenticated: `claude auth login`
- Ensure repository paths in `repos.json` are absolute and exist

### Execution Hangs

- Check that the working directory is correct (use `--repo` flag)
- Verify verification commands in repos.json are valid
- Increase `--max-minutes` if tasks are legitimately long

### Voice Transcription Errors

The system is designed to handle these by using:
- Recent commit history (authored by you)
- Codebase exploration
- Repository context from repos.json

If transcription is consistently poor, speak more clearly or use project-specific terminology.

## License

See the root project LICENSE file.

## Related Documentation

- [Apple Shortcut Setup Guide](../docs/apple-shortcut-setup.md) - How to configure voice input
- [Voice-Driven Development Pipeline](../docs/completed/voice-driven-development-pipeline.md) - Full implementation specification
