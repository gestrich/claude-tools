## Background

This project creates a hands-free, voice-driven development pipeline. The flow is: speak a development task into an iPhone → Apple Shortcut transcribes and SSHs the text to a Mac → a Swift CLI tool interprets the request and generates a phased implementation plan → the same tool executes the plan step by step, calling Claude CLI for each phase.

The system needs a **repository metadata** layer (JSON config per repo) that provides Claude with context about each repository: what it does, relevant Claude skills/documentation, how to test, and how to create PRs. This metadata is referenced throughout the planning and execution phases.

The existing `voice/` system in this repo handles voice-to-terminal input for an active Claude session. This new pipeline is different — it's for initiating entirely new work from voice, not interacting with an existing session. However, both systems may share the Apple Shortcut entry point in the future.

The existing `phased-implementation.py` script demonstrates the core execution pattern (call Claude per-phase, track status, timer display). This Swift package replaces and extends that with a self-contained, type-safe CLI app.

### Key Design Decisions

- The Apple Shortcut only does: record → transcribe → SSH command. It's intentionally minimal.
- Self-contained Swift Package CLI app — replaces `phased-implementation.py`. Uses Swift Argument Parser for CLI, Foundation `Process` for calling Claude CLI, and `Codable` for all JSON handling.
- Two subcommands: `plan` (generate plan from voice text) and `execute` (run phases). Can be chained with `plan --execute` to generate then immediately execute.
- Each phase executes in its own Claude CLI session, keeping context focused.
- Repository metadata lives in a single JSON file (`repos.json`), not scattered across repos.
- Voice transcription errors are expected — the system is designed to be tolerant of them.

---

## Phases

- [x] Phase 1: Scaffold the Swift package

Create the Swift package structure in a new `cli/` directory within this project.

**Package structure**:
```
cli/
├── Package.swift
├── Sources/
│   └── DevPilot/
│       ├── DevPilot.swift          (entry point)
│       ├── Commands/
│       │   ├── PlanCommand.swift
│       │   └── ExecuteCommand.swift
│       ├── Models/
│       │   ├── RepoConfig.swift
│       │   ├── PhaseStatus.swift
│       │   └── ClaudeResponse.swift
│       └── Services/
│           ├── ClaudeService.swift
│           ├── PlanGenerator.swift
│           ├── PhaseExecutor.swift
│           └── TimerDisplay.swift
└── Tests/
    └── DevPilotTests/
```

**Package.swift dependencies**:
- `apple/swift-argument-parser` (~> 1.3) for CLI subcommands and flags

**Entry point** (`DevPilot.swift`):
```swift
@main
struct DevPilot: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Voice-driven development pipeline",
        subcommands: [Plan.self, Execute.self]
    )
}
```

**Outcome**: A Swift package that builds with `swift build` and produces a `dev-pilot` executable.

**Completed**: Entry point is `DevPilot.swift` (not `main.swift`) because Swift treats `main.swift` as top-level code, which conflicts with the `@main` attribute. Resolved with swift-argument-parser 1.7.0, macOS 13+ platform target. All stub files compile and the `dev-pilot` binary runs with working `plan` and `execute` subcommands.

---

- [x] Phase 2: Implement the Claude service layer

Build the service that calls Claude CLI as a subprocess — the equivalent of the Python `clauded()` function.

**`ClaudeService.swift`**:
- Method: `func call(prompt: String, jsonSchema: [String: Any], workingDirectory: URL?) async throws -> T` where `T: Decodable`
- Runs: `caffeinate -dimsu claude --dangerously-skip-permissions -p --verbose --output-format json --json-schema '<schema>' '<prompt>'`
- Parses the verbose JSON array output, extracts `structured_output` from the last element
- Uses Foundation `Process` with `Pipe` for stdout/stderr capture
- Throws typed errors on non-zero exit code or JSON parsing failure

**`ClaudeResponse.swift`** (Codable models for Claude's structured output):
```swift
struct RepoMatch: Codable {
    let repoId: String
    let interpretedRequest: String
}

struct GeneratedPlan: Codable {
    let planContent: String
    let filename: String
}

struct PhaseResult: Codable {
    let success: Bool
}
```

**Outcome**: A reusable service that can call Claude with any prompt + JSON schema and decode the response into Swift types.

**Completed**: Implemented `ClaudeService.call<T: Decodable>()` using Foundation `Process` with `Pipe` for stdout/stderr capture. Uses `/usr/bin/env` to resolve `caffeinate` and `claude` from PATH. Parses the verbose JSON array via `JSONSerialization`, extracts `structured_output` from the last array element, then decodes into the generic `T` type via `JSONDecoder`. Three error cases: `nonZeroExit` (with exit code and stderr), `jsonParsingFailed` (with detail string), and `noStructuredOutput`. The `jsonSchema` parameter is `String` (not `[String: Any]`) to keep the API clean — callers encode the schema JSON themselves. `ClaudeResponse.swift` models (`RepoMatch`, `GeneratedPlan`, `PhaseResult`) were already correct from Phase 1 scaffolding.

---

- [x] Phase 3: Implement repository config loading

Build the models and loading for `repos.json`.

**`RepoConfig.swift`**:
```swift
struct ReposConfig: Codable {
    let repositories: [Repository]
}

struct Repository: Codable {
    let id: String
    let path: String
    let description: String
    let recentFocus: String?
    let skills: [String]
    let architectureDocs: [String]
    let verification: Verification
    let pullRequest: PullRequestConfig
}

struct Verification: Codable {
    let commands: [String]
    let notes: String?
}

struct PullRequestConfig: Codable {
    let baseBranch: String
    let branchNamingConvention: String
    let template: String?
    let notes: String?
}
```

- Load from `repos.json` in the CLI tool's directory (or a path specified via `--config` flag)
- Provide a helper to look up a repository by ID

Also create the initial `repos.json` file in the project root with 2-3 placeholder entries for Bill to fill in:

```json
{
  "repositories": [
    {
      "id": "example-ios",
      "path": "/Users/bill/Developer/example-ios",
      "description": "Main iOS application",
      "recentFocus": "Working on flight planner improvements",
      "skills": ["swift-testing", "design-kit"],
      "architectureDocs": ["docs/architecture.md"],
      "verification": {
        "commands": ["xcodebuild -scheme App -sdk iphonesimulator test"],
        "notes": "Run on iPhone 16 simulator"
      },
      "pullRequest": {
        "baseBranch": "develop",
        "branchNamingConvention": "feature/JIRA-123-description",
        "template": null,
        "notes": "Assign to Bill for review"
      }
    }
  ]
}
```

**Outcome**: Type-safe loading of repository metadata with Codable.

**Completed**: Added `ReposConfig.load(from:)` static method that loads from an explicit path or defaults to `repos.json` in the current working directory. Uses `JSONDecoder` for type-safe Codable decoding. Added `repository(withId:)` lookup helper. Two typed errors: `fileNotFound` and `decodingFailed`. Created `repos.json` in the project root with three placeholder entries (example-ios, example-backend, claude-tools) for Bill to customize. The `--config` option already exists on both `Plan` and `Execute` commands from Phase 1 scaffolding. Codable models were already correct from Phase 1.

---

- [x] Phase 4: Implement the `plan` subcommand

Build the `Plan` command that takes voice text and generates a plan document.

**CLI interface**:
```bash
# Generate plan only (default):
dev-pilot plan "Fix the bug where waypoints disappear after saving"

# Generate plan and immediately execute it:
dev-pilot plan --execute "Fix the bug where waypoints disappear after saving"
```

**`PlanCommand.swift`**:
```swift
struct Plan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate an implementation plan from voice text"
    )

    @Argument(help: "Voice-transcribed text describing the task")
    var text: String

    @Flag(help: "Execute the plan immediately after generating it")
    var execute = false

    @Option(help: "Path to repos.json config")
    var config: String?
}
```

**`PlanGenerator.swift`** — two-step Claude call:

**Step 1 — Match repo**: Call Claude with the voice text + list of repos (id, description, recentFocus). Claude returns `RepoMatch { repoId, interpretedRequest }`.

**Step 2 — Generate plan**: Call Claude with the interpreted request + full repo metadata. Claude returns `GeneratedPlan { planContent, filename }`. The prompt instructs Claude to generate a markdown plan with exactly this structure:

**Critical: The plan command only generates the document — it does NOT execute any phases.** All phases are unchecked (`- [ ]`). No codebase exploration, no implementation, no commits — just the plan document.

**Phase format in the generated document**:

Each phase is a markdown section with an unchecked checkbox header:

```markdown
## - [ ] Phase 1: Interpret the Request

[Description of what this phase will do when executed...]

## - [ ] Phase 2: Gather Architectural Guidance

[Description of what this phase will do when executed...]
```

**The generated plan must have these fixed phases (all unchecked)**:

**`## - [ ] Phase 1: Interpret the Request`** — When executed, this phase will explore the codebase and recent commits (authored by Bill Gestrich) to understand what the voice transcription is asking for. It will find the relevant code, files, and areas. This phase is purely about understanding — no implementation planning yet. The voice text may have transcription errors; use recent commits and codebase context to infer intent. Document findings underneath this phase heading.

**`## - [ ] Phase 2: Gather Architectural Guidance`** — When executed, this phase will look at the repository's `skills` and `architectureDocs` from `repos.json` to identify which documentation and architectural guidelines are relevant to this request. It will read and summarize the key constraints. Document findings underneath this phase heading.

**`## - [ ] Phase 3: Plan the Implementation`** — When executed, this phase will use insights from Phases 1 and 2 to create concrete implementation steps. It will **append new phases** (Phase 4 through N) to this document, each with:
- What to implement
- Which files to modify
- Which architectural documents to reference during that step
- Acceptance criteria for the step
It will also append a Testing/Verification phase and a Create Pull Request phase at the end. Note in this phase's description that it is responsible for generating the remaining phases dynamically.

**No Phases 4+ are written by the plan command.** Phase 3, when executed, will add them.

**Step 3 — Write the file**: Write `planContent` to `docs/proposed/<filename>.md` inside the target repository. Create `docs/proposed/` if it doesn't exist.

**Step 4 — Optionally execute**: If `--execute` was passed, invoke the `Execute` command with the generated plan path and repo context.

**Important instructions baked into the Claude prompts**:
- The voice transcription likely has errors. Look at recent commits by Bill Gestrich for context clues.
- You are only generating the plan skeleton. Do NOT execute, explore, or implement anything.
- All phases must be unchecked (`- [ ]`). None are completed at this stage.

**Outcome**: `dev-pilot plan "some voice text"` generates a well-structured plan document in the target repo.

**Completed**: `PlanCommand.swift` changed from `ParsableCommand` to `AsyncParsableCommand` to support async Claude calls. The `run()` method loads `ReposConfig`, creates a `PlanGenerator`, and calls `generate()`. If `--execute` is passed, it invokes `Execute.parse()` with the generated plan path. `PlanGenerator.swift` implements the full two-step flow: `matchRepo()` sends the voice text + repo list to Claude and gets back a `RepoMatch`; `generatePlan()` sends the interpreted request + full repo metadata to Claude and gets back a `GeneratedPlan` with markdown content and filename. `writePlan()` creates `docs/proposed/` in the target repo if needed and writes the plan file. Three typed errors: `noMatchingRepo`, `repoNotFound`, `writeError`. All Claude prompts include instructions about voice transcription tolerance and the plan-only constraint.

---

- [x] Phase 5: Implement the `execute` subcommand

Build the `Execute` command that runs phases from a planning document — the Swift equivalent of `phased-implementation.py`'s main loop.

**CLI interface**:
```bash
# Execute phases from a planning doc (interactive selection):
dev-pilot execute

# Execute a specific planning doc:
dev-pilot execute --plan path/to/plan.md

# With repo context:
dev-pilot execute --plan path/to/plan.md --repo /path/to/repo

# With time limit:
dev-pilot execute --plan path/to/plan.md --max-minutes 90
```

**`ExecuteCommand.swift`**:
```swift
struct Execute: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute phases from a planning document"
    )

    @Option(help: "Path to planning document")
    var plan: String?

    @Option(help: "Path to target repository (sets working directory)")
    var repo: String?

    @Option(help: "Maximum runtime in minutes")
    var maxMinutes: Int = 90

    @Option(help: "Path to repos.json config")
    var config: String?
}
```

**`PhaseExecutor.swift`**:
- `getPhaseStatus(planDoc:)` — Calls Claude to analyze the markdown and return phase list + next index (same pattern as the Python version)
- `executePhase(planDoc:phaseIndex:description:repoMetadata:)` — Calls Claude to implement a single phase, passing repo metadata (architectural docs, verification commands) into the prompt
- Main loop: iterate through phases, display progress, enforce time limit, re-read status after each phase (handles dynamic phase generation from Phase 3)
- Change working directory to `--repo` path if provided
- On completion: optionally move spec to `docs/completed/`, play completion sound

**`TimerDisplay.swift`**:
- Port the ANSI scroll-region timer from `phased-implementation.py`
- Background thread (or Swift concurrency Task) updating bottom terminal line
- Phase timer + total timer + max runtime display

**Key behavior: dynamic phase generation**:
After executing Phase 3 (which appends new phases to the markdown), the next `getPhaseStatus()` call re-reads the document and picks up the newly added phases. This should work naturally since status is re-read after every phase.

**Outcome**: `dev-pilot execute` runs phases one-by-one with live timer, repo context, and dynamic phase support.

**Completed**: Changed `Execute` from `ParsableCommand` to `AsyncParsableCommand`. `ExecuteCommand.swift` resolves the plan path (either from `--plan` or interactive selection via `PhaseExecutor.selectPlanningDoc()`), resolves the optional `--repo` path, and delegates to `PhaseExecutor.execute()`. `PhaseExecutor.swift` implements the full execution loop: `getPhaseStatus()` calls Claude with a JSON schema matching the Python `STATUS_SCHEMA` to get phase list and next index; `executePhase()` calls Claude to implement each phase with timer running; the main loop iterates phases, enforces `--max-minutes` time limit, re-reads status after each phase (supporting dynamic phase generation from Phase 3), and displays colored progress output. On completion, moves spec to `docs/completed/` and plays Glass.aiff sound. `TimerDisplay.swift` is a `Sendable` class using a background `Thread` that updates the bottom terminal line via ANSI scroll-region escape codes (`\033[1;{height-1}r`), matching the Python `Timer` class behavior. Uses `ioctl(TIOCGWINSZ)` for terminal dimensions. `PhaseStatus` model updated to `Codable` with a companion `PhaseStatusResponse` type for the Claude JSON schema response. Updated `PlanCommand.swift` to call `Execute.run()` with `await` since it's now async.

---

- [x] Phase 6: Create the SSH entry point

The Apple Shortcut needs a simple entry point to call via SSH.

**File**: `voice-plan.sh` (in this project root)

```bash
#!/bin/bash
# Entry point for Apple Shortcut SSH calls
cd "$(dirname "$0")"
cli/.build/release/dev-pilot plan "$@"
```

**Usage from Apple Shortcut**:
```bash
ssh bill@macbook "/Users/bill/Developer/personal/claude-tools/voice-plan.sh 'Fix the bug where waypoints disappear after saving'"

# Or with auto-execute:
ssh bill@macbook "/Users/bill/Developer/personal/claude-tools/voice-plan.sh --execute 'Fix the bug where waypoints disappear after saving'"
```

Also add a build step / Makefile target so `swift build -c release` is easy to run after changes.

**Outcome**: A single SSH-callable script that bridges the Apple Shortcut to the Swift CLI.

**Completed**: Created `voice-plan.sh` in the project root as the SSH entry point — it `cd`s to the script's directory and invokes `cli/.build/release/dev-pilot plan "$@"`, passing all arguments through (including `--execute` flag). Created a `Makefile` with `build` (runs `swift build -c release` in the `cli/` directory) and `clean` targets. Release build verified successfully, producing the `dev-pilot` binary at `cli/.build/release/dev-pilot`.

---

- [ ] Phase 7: Document the Apple Shortcut setup

Create documentation for setting up the Apple Shortcut.

**File**: `docs/apple-shortcut-setup.md`

**The shortcut flow**:
1. **Trigger**: Manual activation (tap the shortcut) or Siri voice command
2. **Record Audio**: Use the "Record Audio" action
3. **Transcribe**: Use the "Transcribe Audio" action to convert speech to text
4. **SSH Command**: Use the "Run Script over SSH" action:
   - Host: Bill's Mac hostname/IP
   - User: bill
   - Authentication: SSH key
   - Command: `/Users/bill/Developer/personal/claude-tools/voice-plan.sh '<transcribed text>'`

**Also document**:
- How to set up SSH key authentication between iPhone and Mac
- How to enable Remote Login on the Mac (System Settings → General → Sharing)
- How to test the shortcut
- Troubleshooting tips (SSH connection failures, transcription issues)

---

- [ ] Phase 8: Integration testing and end-to-end verification

1. **Build**: `cd cli && swift build -c release` succeeds
2. **Test repos.json**: Verify the schema loads correctly
3. **Test plan generation**: `dev-pilot plan "Fix the bug where waypoints disappear after saving"` generates a valid plan doc
4. **Test execution**: `dev-pilot execute --plan <generated-plan>` runs phases with timer
5. **Test plan+execute**: `dev-pilot plan --execute "Fix the bug..."` chains both
6. **Test SSH entry point**: Run `voice-plan.sh` locally with sample text
7. **Test backward compat**: Existing `phased-implementation.py` still works for non-voice workflows (no changes needed — it remains as-is)
8. **Test the Apple Shortcut**: (Manual — record voice, verify plan is generated on Mac)

Fix any issues discovered during testing.
