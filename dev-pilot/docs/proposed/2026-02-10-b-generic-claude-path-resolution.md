## Relevant Skills

No project-level CLAUDE.md found. No skills to reference.

## Background

`ClaudeService.findClaudePath()` hardcodes `/Users/bill/.local/bin/claude` as the first candidate path. Since this tool will be used by others, the path resolution should be generic. The method already includes `~/.local/bin/claude` with proper tilde expansion via `NSString.expandingTildeInPath`, so the hardcoded path is redundant.

## Phases

## - [x] Phase 1: Remove hardcoded user path from findClaudePath

- In `Sources/DevPilot/Services/ClaudeService.swift`, update `findClaudePath()`:
  - Remove the hardcoded `"/Users/bill/.local/bin/claude"` entry from `possiblePaths`
  - Keep the remaining generic paths: `~/.local/bin/claude` (tilde-expanded), `/usr/local/bin/claude`, and bare `claude` (PATH fallback)
- Also reordered so tilde-expanded `~/.local/bin/claude` is checked first (user-local install takes priority)

## - [ ] Phase 2: Validation

- `swift build -c release` succeeds with no errors
