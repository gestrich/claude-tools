## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-testing` | Test style guide and conventions |

## Background

`ClaudeService.swift` has a deep indentation problem, primarily in the `StreamParser.processLine(_:logService:)` method. The `"assistant"` case nests 6+ levels deep due to successive `if let` unwraps and type checks for navigating the JSON structure (`message` → `content` → blocks → `type` → conditional logic). This makes the code hard to read and modify.

The refactoring should flatten the nesting using early returns / `guard` statements and extract small helper methods where it improves clarity.

## Phases

## - [x] Phase 1: Flatten `processLine` — the `"assistant"` case

**Skills to read**: (none)

The worst offender is lines 260–295 in `processLine`. The nested structure is:

```
switch type
  case "assistant":
    if let message...
      if let content...
        for block in content
          if let blockType...
            if blockType == "text"
              if !silent
                if let logService   ← 7 levels deep
```

Refactor approach:

1. Extract a `private func handleAssistantMessage(_ json: [String: Any], logService: LogService?)` method
2. Use `guard let` for `message`, `content` to return early instead of nesting
3. Extract the per-block logic into `private func handleContentBlock(_ block: [String: Any], logService: LogService?)`
4. Inside `handleContentBlock`, use `guard let blockType` + early return, then a `switch blockType` with separate `case "text"` and `case "tool_use"` branches
5. For the text/tool_use output logic, extract a small `private func emit(_ text: String, logService: LogService?)` helper that encapsulates the `silent` / `logService` / `print` branching — this pattern appears 3 times

After this phase, maximum nesting in the assistant path should be ~3 levels (method body → for loop → switch case).

**Completed**: Extracted three helpers (`handleAssistantMessage`, `handleContentBlock`, `emit`). Max nesting in the assistant path is now 3 levels. Build passes.

## - [x] Phase 2: Flatten `processLine` — the `"result"` case & top-level switch

**Skills to read**: (none)

1. Extract `private func handleResultEvent(_ json: [String: Any], data: Data)` for the `"result"` case (lines 297–304)
2. The top-level `processLine` should become a clean `guard` + `switch` with one-line calls to the extracted handlers
3. Consider converting the initial JSON parsing guard chain into a small `private func parseJSON(_ line: String) -> (data: Data, json: [String: Any], type: String)?` if it reads cleaner

**Completed**: Extracted `parseJSON` helper (returns optional tuple of data/json/type), `handleResultEvent` (handles lock + decoding + structured_output extraction), and `processLine` is now a clean guard → switch with one-line calls. Added `defer { lock.unlock() }` in `handleResultEvent` for safer lock management. Build passes.

## - [ ] Phase 3: Clean up `call` method length (optional, light touch)

**Skills to read**: (none)

The `call` method is ~110 lines. It's sequential and not deeply indented, so it's less urgent. Light cleanup only:

1. Extract `private func buildProcess(prompt:jsonSchema:workingDirectory:) -> (Process, Pipe, Pipe)` for lines 61–94 (process setup, environment, pipes)
2. The remaining `call` body handles: run → await termination → drain → check exit → decode — this is a clear linear flow and should stay inline

Do **not** over-abstract here — the goal is mild readability improvement, not architectural change.

## - [ ] Phase 4: Validation

**Skills to read**: `swift-testing`

1. Run `swift build` to confirm compilation
2. Run `swift test` (if tests exist) to confirm no regressions
3. Manually verify that the public API of `ClaudeService` is unchanged — same `call` signature, same `Error` enum cases, same `StreamResult` struct
4. Spot-check that the `StreamParser` logic is functionally identical (same output/logging behavior, same lock discipline)
