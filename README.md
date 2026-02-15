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

### From Marketplace (Recommended)

1. Add the marketplace (if not already added):
```bash
claude marketplace add https://github.com/gestrich/claude-tools-skills
```

2. Install the plugin with system-wide scope:
```bash
claude plugin install claude-tools-skills@gestrich-claude-tools-skills --scope user
```

The `--scope user` parameter enables system-wide installation for all projects.

3. Restart Claude Code

### From Local Directory (For Development)

1. Clone this repository:
```bash
git clone https://github.com/gestrich/claude-tools-skills.git
cd claude-tools-skills
```

2. Run Claude with the plugin directory:
```bash
claude --plugin-dir ~/path/to/claude-tools-skills/plugin
```

**Or** add to your `~/.claude/config.json`:
```json
{
  "plugins": [
    {
      "path": "/path/to/claude-tools-skills/plugin"
    }
  ]
}
```

Then restart Claude Code.

## Usage

Invoke skills using slash commands in Claude Code:

```
/gestrich-claude-tools-next-task
/gestrich-claude-tools-plan
/gestrich-claude-tools-review
```

**Note**: The VSCode extension provides the best experience with slash command discovery. In the terminal, slash commands may not appear in autocomplete but will still work when typed.

## Troubleshooting

### Plugin Not Appearing After Installation

If the plugin doesn't appear after marketplace installation:

1. Manually enable it by editing `~/.claude/config.json`:
```json
{
  "enabledPlugins": [
    "claude-tools-skills@gestrich-claude-tools-skills"
  ]
}
```

2. Restart Claude Code

### Updating the Plugin

To update to the latest version:

1. Update the marketplace:
```bash
claude marketplace update
```

2. Uninstall and reinstall the plugin:
```bash
claude plugin uninstall claude-tools-skills@gestrich-claude-tools-skills
claude plugin install claude-tools-skills@gestrich-claude-tools-skills --scope user
```

**Note**: Asking Claude to update via CLI doesn't work reliably — manual reinstallation is more dependable.

### Slash Commands Not Working

- Verify the plugin is installed: `claude plugin list`
- Check that skills appear in the available skills list
- Try restarting Claude Code
- Use the VSCode extension for better slash command discovery

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
