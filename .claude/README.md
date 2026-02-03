# Cursor/Claude Configuration

This directory contains project-specific Cursor IDE and Claude AI configuration.

## Structure

```
.claude/
├── settings.local.json    # Local Cursor settings
└── skills/                # Project-specific AI skills
    └── macports/          # MacPorts development skill
```

## MacPorts Skill

The `skills/macports/` directory contains a comprehensive skill that provides:

- **Portfile development workflows** - Creating, updating, testing ports
- **Port command reference** - Complete CLI documentation
- **Build debugging** - Techniques for diagnosing failures
- **Automated scripts** - Common repetitive tasks
- **Templates** - Portfile template for new ports

### Skill Resources

- `SKILL.md` - Main skill guide with core workflows
- `scripts/` - Automation scripts (test-port.sh, update-checksums.sh)
- `references/` - Detailed documentation (port commands, debugging, Portfile syntax)
- `assets/` - Templates (Portfile.template)

The skill automatically activates when working with MacPorts-related tasks in this repository.
