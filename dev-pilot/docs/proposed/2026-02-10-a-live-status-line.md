## Relevant Skills

No project-level CLAUDE.md found. No skills to reference.

## Background

During phase execution, the dev-pilot CLI shows a live timer on the bottom line of the terminal using ANSI scroll regions. All Claude output is currently suppressed (silent mode) — the user sees only the timer and has no visibility into what Claude is doing. Bill wants the last line of Claude's streaming output displayed above the timer in a stable, non-janky way. The line should update in-place without causing vertical jumping.

The approach: reserve the bottom **two** terminal lines instead of one. Row `height-1` shows the latest status from Claude (text snippet or tool name), row `height` shows the timer. Both are outside the scroll region so they never move vertically — only their content changes.

## Phases

## - [x] Phase 1: Add status line support to TimerDisplay

- In `Sources/DevPilot/Services/TimerDisplay.swift`:
  - Add a thread-safe `statusLine` property (string, guarded by the existing lock)
  - Add a public `setStatusLine(_ text: String)` method
  - Change the scroll region from `\e[1;{height-1}r` to `\e[1;{height-2}r` (reserve 2 lines)
  - In `updateDisplay()`, render the status line on row `height-1` (truncated to terminal width) and the timer on row `height`
  - Use `\e[K` (clear to end of line) before writing each line to prevent stale text
  - In `stop()`, clear both reserved lines and reset the scroll region
- **Completed**: Status line rendered in yellow (`\e[0;33m`) on row height-1, timer on row height. Both lines written in a single `writeToStdout` call to minimize flicker. Guard changed from `height > 2` to `height > 3` to ensure enough room for the scroll region plus two reserved lines.

## - [x] Phase 2: Feed streaming output to TimerDisplay

- In `Sources/DevPilot/Services/ClaudeService.swift`:
  - Add an optional `onStatusUpdate: ((String) -> Void)?` closure parameter to `StreamParser.init`
  - In `processLine()`, when processing `assistant` events (even in silent mode):
    - For `text` blocks: extract the last non-empty line and call `onStatusUpdate`
    - For `tool_use` blocks: call `onStatusUpdate` with `"[tool: <name>]"` (skip `StructuredOutput`)
  - Add an `onStatusUpdate` closure parameter to `ClaudeService.call()` (defaulting to nil)
- **Completed**: `StreamParser` stores `onStatusUpdate` closure and invokes it from `processLine()` for both text and tool_use blocks, independent of `silent` mode. The `guard !silent` was replaced with conditional `if !silent` blocks around console/log output, so status updates flow even when output is suppressed. Text blocks extract the last non-empty line via `split(separator:omittingEmptySubsequences:)`. All existing call sites remain unchanged since the new parameter defaults to nil.

## - [x] Phase 3: Wire PhaseExecutor to pass the timer's status updater

- In `Sources/DevPilot/Services/PhaseExecutor.swift`:
  - Store the `TimerDisplay` instance as a property (or pass it into `executePhase`)
  - When calling `claudeService.call()` for phase execution, pass `onStatusUpdate: { timer.setStatusLine($0) }`
  - Keep status calls (getPhaseStatus) without a status updater since those are quick
- **Completed**: Added `onStatusUpdate` parameter to `executePhase()` (defaulting to nil) and passed it through to `claudeService.call()`. At the call site in `execute()`, the timer's `setStatusLine` is wired in via `onStatusUpdate: { timer.setStatusLine($0) }`. The `getPhaseStatus` calls remain without a status updater since they are quick status checks.

## - [ ] Phase 4: Validation

- `swift build` succeeds with no errors
- Run `dev-pilot execute --plan <any-plan>` and visually confirm:
  - Two stable bottom lines: status line above, timer below
  - Status line updates as Claude works (shows text snippets and tool names)
  - No vertical jumping or jank — lines stay in fixed positions
  - Normal scrolling output above the reserved lines is unaffected
  - On completion, both lines are cleanly cleared
