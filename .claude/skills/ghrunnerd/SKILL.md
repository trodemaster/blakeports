---
name: ghrunnerd
description: Manage the blakeports GitHub Actions self-hosted runners (status, start, stop, restart, logs, snapshots, exec on runner VMs) through the ghrunnerd MCP servers on darkstar, far-star and umac. Use whenever a runner or runner VM needs to be checked, started, stopped, restarted, reverted, rebuilt or debugged, when CI jobs sit queued, or when asked which runners are online. Start with ghrunnerd, not ad-hoc limactl/vmrun/docker/gh commands.
---

# Managing blakeports runners with ghrunnerd

Every runner action starts with ghrunnerd. It is the one place that knows how
each runner's VM, container and GitHub registration fit together, and it
refuses the unsafe combinations (a third macOS VM, a legacy runner without a
known-good snapshot, a rebuild while a job runs). Only fall back to `limactl`,
`vmrun`, `docker` or `gh api` for something ghrunnerd has no tool for, and say
so when you do.

## One server per host

Each host runs its own `ghrunnerd serve` (port 18081, `/mcp`, bearer token) and
sees only its own runners. Registered at local scope for this project in
`~/.claude.json` (the token must stay out of git, so there is no `.mcp.json`):

| MCP server | Endpoint | Runner ids | GitHub runner names |
|---|---|---|---|
| `ghrunnerd-far-star` | `http://127.0.0.1:18081/mcp` | `macos-26`, `macos-27`, `leopard-ppc` | `macOS_26`, `macOS_27`, `leopard-ppc-runner` |
| `ghrunnerd-umac` | `http://192.168.234.144:18081/mcp` (LAN IP; not listening on tailscale) | `macos-15` | `macOS_15` |
| `ghrunnerd-darkstar` | `http://darkstar.jibb.tv:18081/mcp` | `leopard`, `snowleopard`, `lion`, `mountainlion`, `mavericks`, `yosemite`, `elcapitan` | `<id>-runner` |

Pick the server by the runner: `macOS_15` lives on umac, `macOS_26`/`macOS_27`
and `leopard-ppc` on far-star, every other legacy runner on darkstar. Tools
appear as `mcp__ghrunnerd-<host>__<tool>`. They load at session start, so a
session opened before the registration needs a restart.

Modern runners (build on push): `macOS_15`, `macOS_26`, `macOS_27`. Everything
else, **including `leopard-ppc`**, is legacy and only builds on manual
dispatch with `run_legacy=true`.

## Tools

| Tool | Use |
|---|---|
| `runners_status` | VM, known-good, IP, container or `guest_runner`, GitHub online/busy. **Always the first call.** Failed probes land in `unknown`, not "off" |
| `vm_list` | running VMs mapped to runner ids; an id-less row is infrastructure (far-star/umac Lima `default`, darkstar `10.5_leopard_ppcxbuild`) |
| `runner_logs` | container or in-guest runner service log (`tail`, `since`) |
| `vm_ip`, `vm_snapshots` | resolve an IP; show the snapshot tree |
| `runner_up` / `runner_down` / `runner_restart` | lifecycle; `up` starts the VM and registers the runner. Jobs |
| `runner_remove` | force-deregister from GitHub |
| `vm_start` / `vm_stop` | power only; `hard` for stop. Jobs |
| `vm_snapshot` / `vm_consolidate` / `vm_revert` | legacy known-good handling; consolidate and revert need `confirm=true` |
| `runner_rebuild` | Lima only: destroy and rebuild the VM (hours); `confirm=true`, refused while busy |
| `runner_build` | `docker compose build` the legacy runner image |
| `vm_exec` | any shell command on the VM over ssh; `background=true` for long ones |
| `job_get` / `job_list` / `job_cancel` | poll slow tools (`wait_seconds` long-polls) |

Slow tools return a job: poll `job_get` until it finishes before reporting
done. Jobs live in memory and vanish if the server restarts.

## Workflow

1. `runners_status` on the relevant server (or all three for "what's online").
2. If asked about the whole fleet, also compare against GitHub, which is the
   source of truth for what Actions can schedule:
   `gh api --paginate repos/trodemaster/blakeports/actions/runners --jq '.runners[] | "\(.name)\t\(.status)\tbusy=\(.busy)"'`
   Expect 11 runners: 7 on darkstar, 3 on far-star, 1 on umac.
3. Act with the narrowest tool: `runner_up <id>` rather than `all`.
4. Re-run `runners_status` and confirm GitHub shows the runner `online`.
5. For queued jobs, check status first; only then re-dispatch
   (`gh workflow run "Build <Port>"`, adding `-f run_legacy=true` for legacy).

## Rules

- **Do not start or stop `macOS_15` unless the user asks.** It is on umac and
  the user manages it. Read-only calls against `ghrunnerd-umac` are fine.
- **Check for busy runners before any stop, restart, revert or rebuild.**
  `runners_status` shows `busy`; never interrupt a running job without the user
  saying so. Same for existing CI runs when asked not to break a runner VM.
- Virtualization.framework allows 2 macOS VMs per host. far-star runs
  `macos-26` and `macos-27` together, so a third refuses to start.
- Lima runners (`macos-*`) have no snapshots; a reset is a `runner_rebuild`
  that takes hours. Do not use it as a retry.
- `leopard-ppc` is a QEMU G5 whose runner container runs in the Lima `default`
  Docker VM on far-star. If `runner_up` fails with "Cannot connect to the
  Docker daemon", `limactl start default` (sandbox off), then `runner_up`
  again. `default` is not a runner VM; never stop it while leopard-ppc runs.
- `vm_exec` is unrestricted and the bearer token is the only gate. Treat
  commands on the VMs as the user's own, and never print or log a token.
- Never edit a runner's `runners.json` by hand; `runner_up` rewrites it.

## When the MCP tools are not loaded

Use the same operations from the CLI on the host that owns the runner:

```bash
ghrunnerd status | vm-list | up <id> | down <id> | restart <id> | logs <id>   # far-star (this machine)
ssh darkstar ghrunnerd status                                                  # legacy VMs
ssh umac '~/Developer/go/bin/ghrunnerd status'                                 # macOS_15
```

On far-star, `limactl`/`vmrun`-backed commands need the Claude sandbox
disabled; in the sandbox they report 0 running VMs, which is not real state.

## Registering or repairing a server

Check with `claude mcp list | grep ghrunnerd` (all three should show
connected). A server that refuses the connection is down or still waiting on a
tailscale interface at startup: look at `~/Library/Logs/ghrunnerd.log`
(macOS) or `journalctl --user -u ghrunnerd` (darkstar). To re-register, read
the token over ssh without echoing it:

```bash
claude mcp add --transport http --scope local ghrunnerd-darkstar http://darkstar.jibb.tv:18081/mcp \
  --header "Authorization: Bearer $(ssh darkstar cat .config/ghrunnerd/token)"
claude mcp add --transport http --scope local ghrunnerd-umac http://192.168.234.144:18081/mcp \
  --header "Authorization: Bearer $(ssh umac cat .config/ghrunnerd/token)"
claude mcp add --transport http --scope local ghrunnerd-far-star http://127.0.0.1:18081/mcp \
  --header "Authorization: Bearer $(tr -d '[:space:]' < ~/.config/ghrunnerd/token)"
```

Source and full docs: `~/Developer/actions_runners/ghrunnerd` (`README.md`,
`CLAUDE.md`). Each host's registry is `<host>/config/runners.example.json`.
