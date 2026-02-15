---
name: gestrich-claude-tools-next-task
description: Next Phase Command
invoke: Execute phased work from planning documents with review and commit cycles
---

# Next Phase Command

This command implements phased work from a planning document. It guides the user through completing one phase at a time with review and commit cycles.

## Workflow

### Step 1: Check for Uncommitted Changes

First, run `git status --porcelain` to check for uncommitted changes.

If there are uncommitted changes:
- Show the user what files have changes
- Ask: "You have uncommitted changes. Would you like to commit them before starting the next phase?"
- If yes, help them commit with an appropriate message
- If no, proceed (their changes will be included in the phase commit)

### Step 2: Identify the Planning Document

If the user has not specified a planning document in this session, show them a list of documents in `docs/proposed/` sorted by **file modification date** (newest first, descending). Do not sort by filename — filenames contain date prefixes but other non-dated docs may also exist.

```bash
ls -lt docs/proposed/*.md 2>/dev/null | head -5
```

Present the files as a numbered list and ask which document they want to work on. Store this choice for the session.

### Step 3: Analyze the Document for Phases

Read the planning document and identify all phases. Phases are `##` headings with checkboxes:
- `## - [ ] Phase N: Description` (incomplete)
- `## - [x] Phase N: Description` (complete)

Determine:
1. Total number of phases
2. Which phases are complete
3. The next incomplete phase (the one to work on)

### Step 4: Confirm the Phase

Present the next phase to the user:

"**Next Phase:** Phase N: [Description]"

Ask: "Ready to work on this phase?"

If the user declines, exit gracefully.

### Step 5: Implement the Phase

Complete the phase by:
1. Reading the detailed requirements from the planning document
2. If the phase lists **Skills to read**, invoke those skills first to load relevant conventions and patterns. The guidance from skills may adjust the implementation approach — this is expected.
3. Implementing the required changes
4. Updating the planning document to mark this phase as in-progress if helpful

Do NOT commit yet - wait for user review.

### Step 6: Review Changes

When implementation is complete:
1. Show a summary of what was changed
2. Ask: "Are you OK with these changes?"

If the user says yes/ok/looks good:
- Mark the phase as complete in the planning document (change `## - [ ]` to `## - [x]`)
- Below the completed phase heading, add a completion note documenting what skills were used and key principles applied:
  ```
  ## - [x] Phase 2: Implement command parsing

  **Skills used**: `swift-testing`, `design-kit`
  **Principles applied**: Used factory pattern per design-kit conventions; tests follow swift-testing arrange/act/assert style
  ```
- Commit all changes with a message like: "Complete Phase N: [Description]"
- Include any relevant technical notes in the commit body

If the user provides feedback:
- Make the requested adjustments
- Ask for review again
- Repeat until approved

### Step 7: Check for Completion or Continue

After committing, check if this was the last phase:

**If all phases are complete:**
- Congratulate the user
- Ask: "All phases are complete! Would you like to move this document to `docs/completed/`?"
- If yes:
  - Move the file: `git mv docs/proposed/[filename] docs/completed/[filename]`
  - Commit: "Move completed spec to docs/completed"

**If more phases remain:**
- Ask: "Ready to work on the next phase?"
- If yes, go back to Step 4 with the next phase
- If no, exit gracefully

## Important Guidelines

1. **Use "phase"** - Always refer to work items as "phases"
2. **One phase at a time** - Complete, review, and commit each phase before moving on
3. **User approval required** - Never commit without explicit user approval
4. **Preserve document format** - When updating phase status, maintain the existing markdown structure
5. **Clear communication** - Always explain what you're about to do and what was accomplished

## Example Interaction

```
> Checking for uncommitted changes...
> No uncommitted changes found.

> No planning document specified. Recent documents in docs/proposed/:
>
> 1. 2025-01-03-1-add-voice-commands.md (modified 2 hours ago)
> 2. 2025-01-02-1-refactor-api.md (modified yesterday)
>
> Which document would you like to work on?

[User selects 1]

> Working with: docs/proposed/2025-01-03-1-add-voice-commands.md
>
> Phase Overview:
> ## - [x] Phase 1: Set up voice input infrastructure
> ## - [ ] Phase 2: Implement command parsing
> ## - [ ] Phase 3: Add error handling
> ## - [ ] Phase 4: Validation
>
> **Next Phase:** Phase 2: Implement command parsing
>
> Ready to work on this phase?

[User confirms]

[Claude implements the phase]

> Phase 2 implementation complete. Here's what changed:
> - Created src/voice/parser.py with command parsing logic
> - Updated src/voice/main.py to use the new parser
> - Added tests in tests/test_parser.py
>
> Are you OK with these changes?

[User approves]

> Marked Phase 2 as complete and committed changes.
>
> Ready to work on the next phase? (Phase 3: Add error handling)
```

## Commit Message Format

Use this format for phase commits:

```
Complete Phase N: [Short description]

[Optional: 1-2 sentences about what was implemented]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```
