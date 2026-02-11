---
name: beads
description: Use Beads (bd) for task tracking and long-term knowledge. Use when planning work, asking "what's next", starting a session, completing tasks, or when the repo uses .beads/ for issues.
---

# Beads Task Tracking

## Overview

This repo uses [Beads](https://github.com/steveyegge/beads) (CLI: `bd`) for dependency-aware task tracking. Issues live in `.beads/` as git-tracked JSONL. Use this skill when working with tasks, planning, or when you need to know what work is unblocked.

**Prerequisite:** Beads must be initialized in the repo (`bd init` or `bd init --stealth`). If `.beads/` is missing, suggest the user run `bd init` first.

## When to Use

- User asks "what should I work on?", "what's next?", or "current tasks"
- Starting a coding session and you need context on in-progress or ready work
- After completing a task: update or close the Beads task and unblock dependents
- User mentions planning, roadmap, or tracking work
- Repo contains `.beads/` and user is discussing tasks or priorities

## Essential Commands

| Command | Purpose |
|---------|---------|
| `bd ready` | List tasks with no open blockers (what to do next) |
| `bd show <id>` | Full task details and audit trail (e.g. `bd show bd-a1b2`) |
| `bd create "Title" -p 0` | Create a task (priority 0 = P0) |
| `bd dep add <child> <parent>` | Link tasks: child blocked by parent |
| `bd list` | List tasks (filter by status/priority as needed) |

**JSON output for agents:** Use `bd ready --json` or `bd show <id> --json` when you need structured data.

## Workflow

1. **Start of session:** Run `bd ready` to see unblocked tasks. Optionally `bd show <id>` on one task for full context.
2. **While working:** Create or update tasks with `bd create` and `bd dep add` to keep the graph accurate. Link to specs (e.g. "See PLANNED_IMPROVEMENTS.md § Phase 2") in task body if useful.
3. **After completing work:** Mark the task done (per Beads workflow; e.g. status update). Run `bd ready` again to see newly unblocked work.

## Hierarchy

Beads supports hierarchical IDs for epics and sub-tasks:

- `bd-a3f8` — Epic
- `bd-a3f8.1` — Task under epic
- `bd-a3f8.1.1` — Sub-task

Use these when creating structured plans (e.g. migration phases as parent tasks, port-specific work as children).

## Relation to Project Docs

- **PLANNED_IMPROVEMENTS.md** (if present): Long-form spec and design. Use Beads for *actionable* tasks and ordering. In task bodies, reference sections like "See PLANNED_IMPROVEMENTS.md § Phase 2" so context stays linked.
- **AGENTS.md**: May contain a one-line note that the repo uses Beads for task tracking; this skill provides the full workflow.

## Tips

- Hash-based IDs (`bd-a1b2`) avoid merge conflicts when multiple branches edit `.beads/`.
- If the repo uses `bd init --stealth`, `.beads/` may be gitignored; the skill still applies for local task tracking.
- For "what's next?", always prefer `bd ready` over scanning markdown; the graph is the source of truth for unblocked work.
