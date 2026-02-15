# Claude Tools Skills Plugin

A Claude Code plugin providing phased development workflow tools for structured planning, implementation, and code review.

## Skills

### `/gestrich-claude-tools-next-task`
Execute phased work from planning documents with review and commit cycles. This skill:
- Guides you through completing one phase at a time
- Ensures proper review before committing
- Tracks progress and automatically marks phases complete
- Moves completed specs to `docs/completed/`

### `/gestrich-claude-tools-plan`
Create structured planning documents with phased implementation approach. This skill:
- Discovers and references project-specific skills from `CLAUDE.md`
- Creates plans in `docs/proposed/` with proper naming conventions
- Breaks work into discrete, reviewable phases
- Always includes a validation phase

### `/gestrich-claude-tools-review`
Create structured code review documents for changes. This skill:
- Analyzes git changes (commits, diffs, or unstaged work)
- Categorizes changes by type (architecture, bugs, features, refactoring, tests)
- Provides rationale and impact analysis
- Generates review documents in `docs/reviews/`

## Installation

### From Local Directory

1. Add to your `~/.claude/config.json`:

```json
{
  "plugins": [
    {
      "path": "/Users/bill/Developer/personal/claude-tools/plugin"
    }
  ]
}
```

2. Restart Claude Code

## Usage

Invoke skills using slash commands in Claude Code:

```
/gestrich-claude-tools-next-task
/gestrich-claude-tools-plan
/gestrich-claude-tools-review
```

## Project Structure

```
claude-tools/
├── .claude-plugin/
│   └── marketplace.json     # Package registry entry
├── plugin/                  # Main plugin directory
│   ├── .claude-plugin/
│   │   └── plugin.json     # Plugin metadata
│   ├── skills/
│   │   ├── gestrich-claude-tools-next-task/
│   │   │   └── SKILL.md
│   │   ├── gestrich-claude-tools-plan/
│   │   │   └── SKILL.md
│   │   └── gestrich-claude-tools-review/
│   │       └── SKILL.md
│   └── LICENSE
├── docs/
│   ├── proposed/           # Work-in-progress planning docs
│   ├── completed/          # Finished planning docs
│   └── reviews/            # Code review documents
└── commands/               # Legacy command files (deprecated)
```

## Documentation Structure

The plugin expects the following directory structure in your projects:

- `docs/proposed/` - Planning documents for active work
- `docs/completed/` - Archive of completed planning documents
- `docs/reviews/` - Code review documents

## License

MIT License - see [LICENSE](plugin/LICENSE) for details.
