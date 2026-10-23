# Cursor/Claude Configuration

This directory contains project-specific Cursor IDE and Claude AI configuration.

## Structure

```
.claude/
├── settings.local.json    # Local Cursor settings
└── skills/                # Project-specific AI skills
    ├── macports/          # MacPorts development skill
    └── ghrunnerd/         # Runner management via the ghrunnerd MCP servers
```

## ghrunnerd Skill

`skills/ghrunnerd/SKILL.md` covers managing the self-hosted runners through the
per-host ghrunnerd MCP servers (`ghrunnerd-darkstar`, `ghrunnerd-far-star`,
`ghrunnerd-umac`): which server owns which runner, the tools, safety rules and
how to re-register a server. The servers are registered at local scope in
`~/.claude.json` because the bearer tokens must not be committed.

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
