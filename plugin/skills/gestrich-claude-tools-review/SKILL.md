---
name: gestrich-claude-tools-review
description: Review Bill Command
invoke: Create structured code review documents for changes
---

# Review Bill Command

When the user invokes this command, help them review code changes by creating a structured review document.

## Determining What to Review

1. **If context is clear** (user just mentioned changes, or obvious recent work):
   - Default to reviewing those changes
   - Proceed directly to creating the review document

2. **If context is unclear**:
   - Check for unstaged changes: `git status`
   - Check recent commits: `git log -5 --oneline`
   - Present numbered options to the user:
     ```
     What would you like to review?
     1) Unstaged changes (X files modified)
     2) Last commit: <commit message>
     3) Last 3 commits: <range>
     4) Other (specify)
     ```
   - Wait for user selection before proceeding

## Review Document Format

Create a markdown document in `docs/reviews/<descriptive-name>-YYYY-MM-DD.md` (e.g., `timer-fix-2025-12-28.md`).

The review document should follow this structure:

```markdown
# Code Review: [Descriptive Title]

**Date**: YYYY-MM-DD
**Scope**: [What was reviewed - e.g., "Last commit", "Unstaged changes", "Commits abc123..def456"]

## Summary

[2-3 sentence overview of what changed and why]

## Changes by Category

### 🏗️ Architecture / Structure
[If architectural changes were made]

**Files**: `path/to/file.py:123-145`

\`\`\`diff
- old code
+ new code
\`\`\`

**Rationale**: [Why this architectural change was made]

**Impact**: [What this affects]

---

### 🐛 Bug Fixes
[If bugs were fixed]

**Files**: `path/to/file.py:67`

\`\`\`diff
- old buggy code
+ fixed code
\`\`\`

**Issue**: [What was broken]
**Fix**: [How it was resolved]

---

### ✨ New Features
[If new features were added]

**Files**: `path/to/file.py:200-250`

\`\`\`python
# Show relevant new code snippets
def new_feature():
    pass
\`\`\`

**Purpose**: [What this feature does]
**Implementation**: [Key technical decisions]

---

### 🔧 Refactoring
[If code was refactored]

**Files**: `path/to/file.py`

**Changes**: [What was refactored and why]
**Benefit**: [Improvement gained]

---

### 📝 Documentation / Comments
[If docs or comments were updated]

**Files**: `README.md`, `docs/guide.md`

**Updates**: [What documentation changed]

---

### 🧪 Tests
[If tests were added/modified]

**Files**: `tests/test_feature.py`

**Coverage**: [What's now tested]

## Review Notes

### ✅ Strengths
- [What was done well]
- [Good patterns used]

### ⚠️ Considerations
- [Potential edge cases to watch]
- [Areas that might need follow-up]
- [Performance implications if any]

### 🔍 Suggested Next Steps
- [Optional improvements]
- [Follow-up tasks if any]

## Example Review Document

Here's a concrete example of what a review looks like:

---

# Code Review: Timer Scroll Region Fix

**Date**: 2025-12-28
**Scope**: Commit e2f069f "Fix timer scrolling by reserving bottom line"

## Summary

Fixed the live timer display in phased-implementation.py that was scrolling off the bottom of the terminal. The solution uses ANSI escape codes to reserve the bottom line exclusively for the timer while constraining normal output to scroll only in the upper region.

## Changes by Category

### 🐛 Bug Fixes

**Files**: `phased-implementation.py:77-113`

\`\`\`diff
def start(self):
-   self.phase_start_time = time.time()
-   self.running = True
+   self.phase_start_time = time.time()
+   self.running = True
+
+   # Set scroll region to exclude bottom line
+   sys.stdout.write(f"\033[1;{term_height-1}r")
+   sys.stdout.write(f"\033[{term_height-1};1H")
\`\`\`

**Issue**: Normal terminal output was scrolling the timer line up, making it part of the scrollback instead of staying anchored at bottom
**Fix**: Set terminal scroll region using `\033[1;{h-1}r` to constrain scrolling to upper lines, reserving bottom line for timer

---

### 🔧 Refactoring

**Files**: `phased-implementation.py:115-158`

**Changes**:
- Replaced cursor save/restore (`\033[s` / `\033[u`) with absolute positioning
- Changed update interval from 1s to 0.5s for smoother display
- Removed unused `safe_print()` helper method since scroll region handles coordination

**Benefit**: More reliable positioning across different terminal emulators; scroll region is standard VT100

## Review Notes

### ✅ Strengths
- Proper use of ANSI scroll regions prevents race conditions
- Falls back gracefully if terminal size unavailable
- Cleans up scroll region on exit (restores normal scrolling)

### ⚠️ Considerations
- Assumes VT100-compatible terminal (standard on modern systems)
- Scroll region not supported in all environments (hence the try/except)
- Timer thread is daemon, so won't block program exit

### 🔍 Suggested Next Steps
- Consider testing on different terminal emulators (iTerm2, Terminal.app, etc.)
- Could add a `--no-timer` flag for non-compatible terminals
```

## Guidelines

1. **Organize by change type** - Use the category sections that apply (skip empty categories)
2. **Show context, not everything** - Include enough diff to understand the change, not full files
3. **Explain the "why"** - Focus on rationale and impact, not just what changed
4. **Be concise** - Aim for clarity and brevity; reviewers want signal, not noise
5. **Use file:line references** - Help reviewers jump to relevant code
6. **Highlight trade-offs** - Note any technical decisions or alternatives considered

## Workflow

1. Determine what to review (as described above)
2. Analyze the changes using `git diff`, `git show`, or `git log -p`
3. Categorize changes by type
4. Create review document in `docs/reviews/` with descriptive name
5. Open the document in Typora for review: `open -a Typora docs/reviews/<filename>.md`
6. Present the review document path to the user
7. Do NOT commit the review document automatically - let user decide

This approach creates focused, actionable code reviews that help understand what changed and why.
