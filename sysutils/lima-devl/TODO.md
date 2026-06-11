# lima-devl — Upstream PR & Port Tracking

Status of feature patches carried by this port and their upstream submission.
Patch revs: see `g3_rev` / `b1_rev` / `b2_rev` in the Portfile.

## Feature status

| Patch | Feature | Upstream status |
|-------|---------|-----------------|
| G1 (`patch-01`) | VZ thread pinning | local only |
| G4 (`patch-02`) | VZ window title | **merged** (PR #5084) |
| G3 (`patch-04`) | `limactl screenshot` | **PR #5098 open** — reviewer comments resolved, awaiting approval |
| B1 (`patch-05`) | `suppressFirstLoginSetup` | ready for submission (r7) |
| B2 (`patch-06`) | TCC pre-seeding (`guestPatch.tccPermissions`) | ready for submission (r7), depends on B1 |
| O1 (`patch-07`) | PID timeout | disabled in Portfile |

## TODO

### Upstream PRs
- [ ] G3 / PR #5098: merge pending. `Lints` (lima-vm.io link check) and
      `Windows QEMU` (proxy.golang.org TLS timeout) failures are infra flakes —
      re-run, don't chase.
- [ ] B1: create `upstream-pr/b1-suppress-first-login` branch from patch-05,
      sign off (DCO), submit after G3 merges. PR description must state tested
      guest versions: macOS 15, macOS 26.
- [ ] B2: submit after B1 merges (shares lima_yaml.go / macos.md hunks).
      PR description must cover: TCC schema v30 + tccd forward-migration
      rationale, per-user TCC limitation (tccd revokes per-user grants on
      first login — by design, not supported), tested on macOS 15 + 26.

### Verification
- [ ] Rebuild a VM from r7 patches (b1_rev 7 / b2_rev 7, pushed 2026-06-11)
      to confirm behavior after the design-review cuts: dscl check reverted to
      FileExists, per-user TCC path removed, plist flow via
      vzSuppressFirstLoginSetup(). `make rebuild-26` in lima_mac.
- [ ] Test TCC patching against a macOS 27-beta guest (template exists in
      lima_mac, untested). Strengthens schema-migration claim to 3 generations.

### CI maintenance
- [ ] `golangci/golangci-lint-action@v8` runs on Node 20 (deprecated).
      GitHub forces Node 24 on 2026-06-16 and removes Node 20 from runners on
      2026-09-16. Verify the action works under Node 24 or bump the version.

### Deferred / not planned
- Per-user TCC database pre-seeding: cut in r7 — proven non-functional
  (tccd validates and removes unrecognized per-user grants on first login).
  Revisit only if tccd behavior changes in a future macOS.
- AppleEvents presets (`terminal-apple-events`, `sshd-apple-events-finder`):
  removed with the per-user path. Wallpaper automation is handled by the
  cliclick approval flow in lima_mac configure.sh instead.

## Workflow reminders
- Regenerate patches from git commit ranges, never hand-edit
  (see lima-mac skill → "MacPorts Patch Fix Workflow").
- Bump the matching `*_rev` in the Portfile on every patch regeneration.
- `gofmt -w` all changed files before regenerating any patch.
- Never modify upstream CI config (.golangci.yml etc.) in a PR.
