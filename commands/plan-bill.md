# Plan Bill Command

When the user invokes this command, create a planning document in `docs/proposed/<doc-name>.md` where the doc name reflects the plan appropriately (e.g., `add-user-authentication.md`, `refactor-api-layer.md`).

## Skill Discovery

Before writing the plan:

1. Read the project's `CLAUDE.md` file to understand what skills are referenced or relevant to this project
2. For each skill mentioned in `CLAUDE.md`, read its description to understand what guidance it provides
3. From those skills, decide which ones are relevant to the task being planned
4. List only the relevant skills in the planning document

This ensures plans reference project-specific skills rather than dumping every available skill.

## Planning Document Format

The planning document should follow this structure:

```markdown
## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-testing` | Test style guide and conventions |
| `design-kit` | SwiftUI design system context |

[List only skills from CLAUDE.md that are relevant to this task, with a short description of what each provides.]

## Background

[Explain why we are making these changes. Include any general information that applies across all phases. Reference user requirements and context from the conversation.]

## Phases

Each phase is an `##` heading with a checkbox. This makes phases stand out as sections in rendered markdown, with details nested underneath.

## - [ ] Phase 1: [Short descriptive name]

**Skills to read**: `skill-a`, `skill-b`

[Detailed description of Phase 1, including:
- Specific tasks to complete
- Files to modify
- Important details from user's instructions
- Any technical considerations
- Expected outcomes]

## - [ ] Phase 2: [Short descriptive name]

**Skills to read**: `skill-c`

[Detailed description of Phase 2...]

## - [ ] Phase N: Validation

**Skills to read**: `swift-testing` (or whichever apply)

[Describe validation approach:
- Which tests to run (unit, integration, e2e)
- Manual checks if needed
- Success criteria
- Prefer automated testing over manual user verification]
```

**Note**: Reading skills during implementation may reveal conventions or patterns that change the original approach. This is expected and encouraged — the plan is a starting point, not a rigid contract.

## Important Guidelines

1. **Limit phases to 10 or less** - For simple plans, use 5 or fewer phases
2. **Include user details** - Capture specific requirements and preferences from the conversation
3. **Always end with Validation phase** - Choose appropriate test level based on complexity
4. **No implementation** - Only write the planning document, don't start coding
5. **Descriptive naming** - Doc filename should clearly indicate what's being planned
6. **Be specific** - Each phase should have enough detail to execute independently

## Naming Convention

Plan filenames use the format: `YYYY-MM-DD-<alpha>-<description>.md`

- **Date**: Current date in `YYYY-MM-DD` format
- **Alpha index**: A lowercase letter (`a`, `b`, `c`, ...) that increments per day. Each new day resets to `a`.
- **Description**: A short, kebab-case identifier formed by the AI (e.g., `unified-app-rearchitecture`, `add-retry-logic`)

### Determining the next alpha index

Run this to get the next available prefix for today:

```bash
today=$(date +%Y-%m-%d); last=$(find docs/proposed -maxdepth 1 -name "${today}-*.md" 2>/dev/null | sort | tail -1 | sed "s|.*/||" | cut -c12); if [ -z "$last" ]; then echo "${today}-a"; else echo "${today}-$(echo "$last" | tr 'a-y' 'b-z')"; fi
```

### Examples

If `docs/proposed/` is empty today (2026-02-10):
- First plan: `2026-02-10-a-unified-app-rearchitecture.md`

If `2026-02-10-a-unified-app-rearchitecture.md` already exists:
- Next plan: `2026-02-10-b-add-retry-logic.md`

If `2026-02-10-a-...` and `2026-02-10-b-...` both exist:
- Next plan: `2026-02-10-c-refactor-auth-layer.md`

Next day resets:
- `2026-02-11-a-fix-streaming-parser.md`

## Workflow

1. Gather requirements (ask clarifying questions if needed)
2. Read the project's `CLAUDE.md` to identify available skills, then read descriptions of each to determine which are relevant to the task
3. Run the alpha-index snippet above to determine the filename prefix
4. Choose a short kebab-case description for the plan
5. Create the planning document in `docs/proposed/<prefix>-<description>.md`
6. Present the plan to the user for review
7. Wait for approval before any implementation

This approach creates clear, actionable plans that can be executed phase by phase with proper validation.
