# Planning Skill

When the user invokes this skill, create a planning document in `docs/proposed/<doc-name>.md` where the doc name reflects the plan appropriately (e.g., `add-user-authentication.md`, `refactor-api-layer.md`).

## Planning Document Format

The planning document should follow this structure:

```markdown
## Background

[Explain why we are making these changes. Include any general information that applies across all phases. Reference user requirements and context from the conversation.]

## Phases

- [ ] Phase 1: [Short descriptive name]

[Detailed description of Phase 1, including:
- Specific tasks to complete
- Files to modify
- Important details from user's instructions
- Any technical considerations
- Expected outcomes]

- [ ] Phase 2: [Short descriptive name]

[Detailed description of Phase 2...]

- [ ] Phase N: Validation

[Describe validation approach:
- Which tests to run (unit, integration, e2e)
- Manual checks if needed
- Success criteria
- Prefer automated testing over manual user verification]
```

## Important Guidelines

1. **Limit phases to 10 or less** - For simple plans, use 5 or fewer phases
2. **Include user details** - Capture specific requirements and preferences from the conversation
3. **Always end with Validation phase** - Choose appropriate test level based on complexity
4. **No implementation** - Only write the planning document, don't start coding
5. **Descriptive naming** - Doc filename should clearly indicate what's being planned
6. **Be specific** - Each phase should have enough detail to execute independently

## Workflow

1. Gather requirements (ask clarifying questions if needed)
2. Determine appropriate doc name based on the task
3. Create the planning document in `docs/proposed/<doc-name>.md`
4. Present the plan to the user for review
5. Wait for approval before any implementation

This approach creates clear, actionable plans that can be executed phase by phase with proper validation.
