# Project Brief: Automated MacPorts PPC Pipeline — Intel/Rosetta Builder + QEMU PPC Tester

## Mission

Build an automated MacPorts PowerPC (Leopard, `ppc` 32-bit) build-and-test pipeline
using **two VMs with complementary strengths**, runnable locally and uplifted to
self-hosted macOS GitHub Actions runners:

1. **BUILDER — Intel Mac OS X 10.5 VM** (already exists, 4 vCPUs, hardware-virtualized
   on an Intel Mac host). Compiles ports for `ppc` at near-native x86 speed: the
   toolchain runs native x86 and cross-targets `-arch ppc`; configure-time test
   binaries execute under (original PPC→x86) Rosetta, so autoconf probes correctly
   see a big-endian ppc host. Produces `darwin_9.ppc` binary archives.
2. **TESTER — QEMU PowerPC Leopard guest** on Apple Silicon. Installs those archives
   binary-only and runs test suites / smoke tests under faithful PPC execution.
   Multi-CPU (SMP + MTTCG) work makes this lane faster but is an optimization,
   not a blocker — even single-threaded TCG is adequate for running tests.

End state: builder churns through a port queue producing archives into a shared
store; N parallel QEMU tester guests consume them, run tests, and report; both
driven by one harness, resetting to golden snapshots between jobs.

## Background / Current State of the World (as of mid-2026)

### Builder lane (Intel 10.5 + Rosetta)

- `build_arch ppc` is a documented macports.conf value; 10.5's default
  `universal_archs` is "i386 ppc". Setting `build_arch ppc` on Intel 10.5 makes
  MacPorts compile everything `-arch ppc`.
- Original Rosetta (optional install on 10.5; check it during install or add from
  the DVD) transparently executes the ppc test binaries that configure scripts
  build and run — so runtime probes report big-endian ppc correctly. This is the
  decisive advantage over classic cross-compiling.
- Xcode 3.1.x is the era-correct toolchain with first-class PPC support including
  the right ld. (The 10.6.8-Rosetta community hit `collect2: ld terminated with
  signal 6` aborts from newer ld64 versions that had degraded PPC support — on
  10.5 this class of failure should not occur.)
- Rosetta translates 32-bit G3/G4 code only: **no ppc64** (consistent with scope),
  AltiVec is translated to SSE.
- Prior art: the MacRumors "Building with MacPorts for 10.6 PowerPC / 10.6.8
  Rosetta" effort (barracuda156, kencu) does this pattern at scale and documents
  the port-level failure modes and fixes. Their experience is the playbook;
  their per-port fixes are often directly reusable.
- Archive compatibility linchpin: MacPorts archives are keyed on platform +
  archs + prefix. Intel 10.5 and PPC 10.5 are **both darwin_9**, so a
  `foo-X_Y.darwin_9.ppc.tbz2` built on the Intel VM is exactly what the PPC
  guest would produce. Keep MacPorts base version, prefix (/opt/local), and
  ports-tree commit identical on both VMs per batch.

### Tester lane (QEMU PPC)

- `qemu-system-ppc` (32-bit target) is single-threaded TCG only. `-smp 4` there
  round-robins 4 vCPUs on ONE host thread — no throughput gain.
- `qemu-system-ppc64` **does** support MTTCG (`-accel tcg,thread=multi`) — it is used
  routinely for `pseries` guests. The untested combination is:
  **mac99 machine + Mac device models + OS X guest + thread=multi**.
- The E-Maculation community (Cat_7, with patches credited to BALATON Zoltán / qmiga,
  JD, Andrew, DearthnVader) publishes experimental QEMU + OpenBIOS builds with SMP
  support for the mac99 machine. Current state of those builds:
  - Machine model reports as PowerMac3,3; runs Mac OS 9.x–OS X 10.3 with 2 CPUs,
    **OS X 10.4 and 10.5 with 4 CPUs**, Linux with 4 CPUs.
  - These are `qemu-system-ppc64` builds using G4 CPUs. Patches for QEMU and OpenBIOS
    are included with the downloads.
  - Source thread: https://www.emaculation.com/forum/viewtopic.php?t=8848
    (macOS builds, second post) and the Windows equivalent thread.
- Secondary-CPU bring-up mechanism (reverse-engineered by that team): OpenBIOS
  enumerates extra CPUs with `state = "stopped"` in the device tree; the OS starts
  them by poking a GPIO soft-reset. This code was developed under round-robin TCG
  and has NOT been validated under MTTCG.
- Leopard requires `-M mac99,via=pmu`. G4 (`-cpu G4`) is the target CPU; the G5 /
  PowerMac11,2 path is out of scope (OS X has never booted on an emulated G5;
  U3/U4 northbridge and K2 MacIO are unimplemented in QEMU). MacPorts PPC is
  overwhelmingly 32-bit `ppc` arch, so G4 coverage is sufficient.
- Developer intro from the qemu-ppc maintainer:
  https://codeberg.org/qmiga/pages/wiki/DeveloperTips
- Host toolchain comes from **MacPorts, not Homebrew**:
  `sudo port install glib2 pixman meson ninja pkgconfig cmake ccache`
  plus python for the test harness. QEMU itself is built from source (patched).

## Phase A — Builder lane: Intel 10.5 VM producing ppc archives (do this first; delivers value immediately)

Prereq: the existing Intel Leopard VM (4 vCPUs, hardware-virtualized). Verify
Rosetta is installed (`/usr/libexec/oah/translate` exists; run any ppc binary to
confirm). Verify Xcode 3.1.x.

1. **Configure MacPorts for ppc builds** in /opt/local/etc/macports/macports.conf:
   - `build_arch ppc`
   - `buildmakejobs 4` (real cores here — use them)
   - `configureccache yes`
   - Optional Mode B for dual-use archives: `+universal` with
     `universal_archs ppc i386`. Default to Mode A (pure ppc); it halves build time
     and the consumer is PPC-only.
2. **Pin the ports tree** to a specific commit (git checkout of macports-ports,
   `file://` sources.conf entry). Record the commit per batch; the tester must use
   the same one so archive names/revisions match.
3. **Build job:** `sudo port -v install $PORT`. MacPorts automatically produces
   `$PORT-$VER_$REV.darwin_9.ppc.tbz2` under /opt/local/var/macports/software/.
4. **Publish archives** to the shared store (rsync over SSH to the host store
   directory serving both lanes).
5. **Distfiles:** same TLS problem as the PPC guest (10.5 curl can't do modern TLS).
   Pre-fetch on the modern host into a distfiles mirror; rsync into the builder's
   /opt/local/var/macports/distfiles before each batch.

### Expected failure modes and the triplet-fix playbook

From the 10.6.8-Rosetta builders' experience (10.5 should see strictly fewer):

- **build/host/target confusion:** ports whose configure logic keys off the
  physical CPU (x86_64/i386) instead of the target setting inject Intel code
  paths — the xorg family is a known offender. Fix: set explicit
  `configure.build/host/target` triplets (`powerpc-apple-darwin9`) in the
  Portfile. Usually easy per-port; maintain a local overlay of fixed Portfiles
  and upstream fixes to macports-ports (the PPC community accepts these).
- **meson ports:** need a cross-file declaring
  `cpu_family='ppc', cpu='ppc', endian='big'` with `-arch ppc` link args
  (see /opt/local/share/meson/cross/ppc-darwin pattern from the community).
- **cmake ports:** occasionally need CMAKE_SYSTEM_PROCESSOR/osx-arch hints.
- Track per-port outcomes in the harness DB: built-clean / fixed-with-overlay /
  fails (send to tester lane note or skip).

Expect ~90%+ of common ports to build untouched; budget for a per-port patch
backlog on the rest.

## Phase 0 — Tester lane baseline: QEMU Leopard guest (thread=single)

1. Obtain/build the E-Maculation experimental SMP QEMU (`qemu-system-ppc64`) and the
   matching patched OpenBIOS. Prefer applying their published patches to current QEMU
   master; fall back to their binaries to de-risk.
2. Create a Leopard guest:
   - qcow2 disk (`golden.qcow2`), install Leopard 10.5 from ISO.
   - `-M mac99,via=pmu -cpu G4 -smp 4 -m 2048`
   - NIC: `-device sungem,netdev=n0 -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22`
3. Inside the guest (one time): enable Remote Login (SSH), install Xcode 3.1.x and
   MacPorts base, create a `macports` user with passwordless sudo for `port`.
   Guest de-bloat (critical at TCG speeds):
   - `mdutil -a -i off` and unload `mds` via launchctl (Spotlight off)
   - disable Dashboard, screen saver, sleep, Software Update
   - macports.conf: `build.jobs 1` (single-thread baseline; revisit in Phase 2),
     `configureccache yes` with ccache dir on a location persisted outside overlays
4. Verify 4-CPU boot with `thread=single`: `hostinfo` in guest must report 4 CPUs.
   Snapshot this as the golden image. **This is the CI baseline; lock it in.**
5. Performance flags to use everywhere: `-accel tcg,tb-size=1024`,
   overlay disks with `cache=unsafe` (overlays are disposable by design).

## Phase 1 — MTTCG experiment (tester-lane speedup; the novel QEMU work)

Note: with the builder lane carrying compilation, this phase accelerates test
execution and remains the upstream-contribution track — it no longer gates the
pipeline. Deprioritize relative to Phases A/2 if time-boxed.

Flip the accelerator:

```
qemu-system-ppc64 -M mac99,via=pmu -cpu G4 -smp 4 \
  -accel tcg,thread=multi,tb-size=1024 ...
```

Expected outcomes and responses:

| Outcome | Response |
|---|---|
| QEMU refuses / silently falls back to single thread | Machine or CPU class gates MTTCG; small patch to lift the gate, then proceed |
| Boots but misbehaves (hangs, panics, time weirdness) | Expected case. Diagnose per failure-mode list below |
| Works | Validate hard with stress suite before trusting it |

### Known-likely failure modes, in the order to attack them

1. **Secondary-CPU bring-up race.** The GPIO soft-reset path mutates another vCPU's
   state; under round-robin the other CPU is implicitly not running, under MTTCG it
   races. Fix: route reset/start through `async_run_on_cpu` on the target vCPU.
2. **Timebase/decrementer desync.** Round-robin keeps per-vCPU timebases coherent
   for free; MTTCG threads free-run. OS X assumes synced TB across CPUs (real
   hardware syncs TB at bring-up). Symptoms: time going backwards, spinlock
   timeouts, scheduler panics. Fix: sync TB during bring-up + back TB with the
   shared QEMU clock (pseries already solves this; port the pattern).
3. **6xx hash-MMU / `tlbie` under concurrency.** Cross-vCPU TLB invalidation must
   hit all softmmu TLBs synchronously. Infrastructure exists (pseries uses it) but
   the 32-bit 6xx MMU paths have near-zero MTTCG exposure. Symptom: random compiler
   segfaults under load. A guest GCC bootstrap is an excellent stress test.
4. **Mac device models under concurrency.** MMIO holds the BQL so openpic/macio/PMU
   are mostly safe, but DMA completion paths touching guest RAM outside MMIO context
   are suspect (macio IDE DMA has history: a stale-softmmu-icache bug once broke
   OS 9 boot). Symptom: disk corruption or lost IRQs only under thread=multi.
5. **lwarx/stwcx atomics.** Implemented via cmpxchg for ppc64 MTTCG, probably fine,
   but OS X userland locking exercises it harder than Linux. Symptom: userland
   deadlocks.

### Canary tests (run before trusting builds)

- `hostinfo` reports 4 CPUs
- Tight pthread ping-pong / mutex contention test binary, 10+ min
- `yes > /dev/null &` x4, confirm all vCPUs' host threads busy
- Parallel `md5` of large files (I/O + CPU mix)
- Guest GCC or large port build with `-j4` as the ultimate stressor

Report findings (with reproduction harness) to the qemu-ppc list and the
E-Maculation SMP thread — the maintainer has stated the blocker is available hands,
not architecture. An automated reproducer from a real use case (MacPorts CI) is
high-value there.

## Phase 2 — Pipeline harness (builder → archive store → tester)

One harness drives both lanes over SSH. Per-batch flow:

1. Pin ports-tree commit; sync tree + distfiles mirror to builder.
2. **Builder:** for each port in queue, `port -v install`; on success rsync the
   `darwin_9.ppc.tbz2` (and its dep archives) to the archive store; on failure
   pull /opt/local/var/macports/logs and record.
3. **Archive store:** plain directory on the host, served to testers over the
   hostfwd network as an `archive_sites` URL (http via a tiny local server, since
   Leopard-era TLS can't hit modern https).
4. **Tester (QEMU guest, per-job overlay):**
   - `qemu-img create -f qcow2 -b golden.qcow2 -F qcow2 work-$JOB.qcow2`;
     discard after job, never mutate golden
   - `port -b install $PORT` — **binary-only**; a source fallback here means the
     archive didn't match (name/rev/prefix drift) and is a pipeline bug: fail loudly
   - run `port test $PORT` where defined, plus per-port smoke scripts
     (execute the installed binaries, check `otool -h`/`file` shows ppc, load
     libraries) — this is native-fidelity PPC execution, the tester's whole job
   - pull results/logs; destroy overlay
- **Control plane = SSH** over `hostfwd` (unique port per worker), pytest +
  paramiko/pexpect, hard timeouts everywhere: boot 60–120 s, per-port test
  timeout (default 30 min — tests are much shorter than builds).
- **Persist across runs:** archive store (the product), ccache on the builder,
  distfiles mirror, results DB.
- **Parallelism:** builder is one fast VM with `-j4`; testers scale as N
  single-CPU QEMU workers today (4–6 on an 8+ perf-core M-series host), each
  overlaying the same golden image. Post-MTTCG, fewer/faster testers.
  QEMU perf flags per tester: `-accel tcg,tb-size=1024`, overlay
  `cache=unsafe`; consider `taskpolicy -B` / QoS to keep vCPU threads on P-cores.

## Phase 3 — GitHub Actions uplift (self-hosted macOS runners)

- Guest images contain Apple software: **not redistributable, keep out of caches
  and artifacts.** Park golden image(s) on the self-hosted runner disk as
  pre-provisioned infrastructure; workflow only creates overlays.
- Workflow steps: checkout harness → (build or fetch patched QEMU, ccache +
  actions/cache keyed on QEMU commit) → spawn worker(s) from golden + overlay →
  run job matrix (one VM per matrix entry maps naturally) → upload logs +
  `/opt/local/packages` artifacts → destroy overlays.
- QEMU build: `--target-list=ppc64-softmmu` only; deps from MacPorts on the runner.
- Everything is localhost TCP + files, so local == CI by construction. arm64 host
  in both places for the tester lane, so behavior matches exactly.
- **Builder lane needs an Intel Mac runner** (VT-x for the 10.5 VM and original
  Rosetta semantics don't exist on Apple Silicon). Two-runner topology:
  Intel runner hosts the builder VM + archive store publish step; Apple Silicon
  runner(s) host tester guests. Chain as separate jobs with the archive store
  (shared storage or artifact hand-off between jobs) as the interface. The
  builder VM is pre-provisioned infrastructure like the golden images.
- Automation of the builder VM: `vmrun` (VMware Fusion — note Leopard *Server*
  is the guest version licensed for virtualization, and only older Fusion
  releases support legacy guests) or the equivalent for whatever hypervisor
  hosts the existing VM; plus the same SSH control plane.

## Deliverables checklist

- [ ] Builder VM configuration runbook: macports.conf, Rosetta/Xcode verification,
      ports-tree pinning, distfiles sync
- [ ] Portfile-fix overlay repo + triplet-fix playbook doc; upstream PR log
- [ ] Archive store: layout, publisher (builder side), http server + archive_sites
      config (tester side), name/rev consistency checks
- [ ] Patched QEMU + OpenBIOS build recipe (script, pinned commits/patches)
- [ ] Golden tester-image runbook (manual steps documented; guest de-bloat script)
- [ ] pytest harness: builder job runner, tester job runner (binary-only install +
      test + smoke), boot/SMP canaries, snapshot/overlay lifecycle, timeouts,
      log collection, results DB
- [ ] Phase 1 findings report: thread=multi behavior, minimal reproducers for each
      failure found, patches if achieved (bring-up race, TB sync are the contained,
      well-precedented ones)
- [ ] GitHub Actions workflows: builder job (Intel runner) + tester job(s)
      (Apple Silicon runners), chained via the archive store
- [ ] Throughput benchmark: ports/hour end-to-end (build+test), using a fixed
      port list (suggest: zlib, libpng, pkgconfig, openssl as small/medium mix)

## Hard constraints & gotchas

- MacPorts host tooling only (no Homebrew).
- Same MacPorts base version, same prefix (/opt/local), same pinned ports-tree
  commit on builder and testers — archive compatibility depends on it.
- ppc 32-bit only end-to-end: Rosetta can't translate ppc64 on the builder, and
  the G5 path is out of scope on the tester (QEMU can't boot OS X on an emulated
  G5 — missing U3/U4 + K2 emulation). Leopard tester needs `via=pmu`, `-cpu G4`.
- Never assume `port fetch` works inside either 10.5 VM (TLS). Pre-fetch on a
  modern host; sync mirrors in.
- Tester installs are `port -b` (binary-only); a source build on the tester is a
  pipeline failure, not a fallback.
- Hard timeout on every expect/SSH call; hung firmware must fail fast.
- Builds on Intel/Rosetta are legitimate for userland ports (this is the
  Universal-era workflow), but anything probing kernel/kext level differs from
  real PPC — that's exactly what the tester lane exists to catch.
- OS 9.x has known instability with SMP in the experimental builds; irrelevant here
  but do not use OS 9 results to judge SMP health.

## Key references

- E-Maculation QEMU builds + SMP patches: https://www.emaculation.com/forum/viewtopic.php?t=8848
- E-Maculation wiki (OS X on QEMU setup): https://www.emaculation.com/doku.php/ppc-osx-on-qemu-for-osx
- qmiga developer tips (qemu-ppc maintainer): https://codeberg.org/qmiga/pages/wiki/DeveloperTips
- QEMU MTTCG design doc: https://www.qemu.org/docs/master/devel/multi-thread-tcg.html
- QEMU PowerMac machine docs: https://www.qemu.org/docs/master/system/ppc/powermac.html
- MacRumors SMP WIP thread (bring-up/GPIO context): https://forums.macrumors.com/threads/smp-for-qemu-syetem-ppc64-wip.2450008/
- qemu-ppc mailing list for reporting: qemu-ppc@nongnu.org
- MacRumors "Building with MacPorts for 10.6 PowerPC / 10.6.8 Rosetta" (the
  Rosetta-build playbook; meson cross-file, triplet fixes):
  https://forums.macrumors.com/threads/building-with-macports-for-10-6-powerpc-10a190-and-10-6-8-rosetta.2332711/
- MacPorts Trac #64525 (Rosetta ld abort failures — the 10.6.8 hazard 10.5 avoids):
  https://trac.macports.org/ticket/64525
- barracuda156 custom PPC ports overlays (reference for fix patterns):
  https://github.com/barracuda156/macports-ports
- MacPorts guide (archive_sites, binary-only installs): https://guide.macports.org/

---

## Status — 2026-07-26

The tester lane now exists as five MacPorts ports in this repo, and mac99 SMP
boots Mac OS X 10.5 with 2 CPUs. Phase 1 turned out to be tractable: what the
plan called "the novel QEMU work" was three real bugs, all now fixed.

### Ports

| Port | Purpose |
|---|---|
| `emulators/qemu-mac99-smp` | QEMU 11.1.0-rc1, mac99 `max_cpus` 1 -> 4, ppc/ppc64 only |
| `emulators/openbios-mac99-smp` | OpenBIOS ROM advertising secondaries as `stopped` |
| `cross/powerpc-elf-binutils` | binutils 2.46.1 for the ROM |
| `cross/powerpc-elf-gcc` | gcc 12.4.0 + newlib for the ROM |
| `devel/fcode-utils` | `toke`, the FCode tokenizer OpenBIOS needs |

All install side by side with `port:qemu` (private prefix + suffixed symlinks),
build green in CI on macOS 26 and 27 beta, and are installed on the host.

### Correction to the plan's premises

- The E-Maculation builds ship **binaries only**, no source, despite the notes
  implying otherwise. Real source: `github.com/Randrianasulu/qemu-mac99-smp`
  and `openbios-experiments`. Rebasing 10.0 -> 11.1.0-rc1 cost 2 rejected hunks
  out of 12, both from `hw/irq.h` moving to `hw/core/irq.h`.
- MacPorts has **no powerpc cross toolchain**, hence two new `cross/` ports.
- MTTCG: `target/ppc` sets `.mttcg_supported = TARGET_LONG_BITS == 64`, so only
  `qemu-system-ppc64` declares support. `accel/tcg/tcg-all.c` only *warns* for an
  explicit `thread=multi` and runs multi-threaded anyway, so 32-bit ppc does get
  real parallelism, unvalidated. **`-accel tcg,thread=multi` is required** for
  SMP boot: default TCG round-robins all vcpus on one host thread, starving the
  boot CPU until the ATA probe stalls.

### Bugs fixed in the SMP patch

1. **Cross-thread CPU reset.** `cpu_kick()` called `cpu_reset()` +
   `ppc_cpu_do_system_reset()` on another vcpu from the poking cpu's thread.
   Now routed through `async_run_on_cpu()`. This is failure mode #1 from
   Phase 1 above, and it was real.
2. **`nanosleep(0.5s)` inside the GPIO write handler**, holding the BQL and
   freezing the whole VM once per secondary. Removed; it was papering over (1).
3. **`excp_prefix` set before `cpu_reset()` instead of after.** Resetting a ppc
   cpu sets `MSR[EP]`, and `helper_regs.c` derives `excp_prefix` from it, so the
   pre-set value was discarded and the system reset vectored to `0xFFF00100` in
   ROM. Secondaries re-entered OpenBIOS (two banners, black screen) instead of
   the kernel's secondary entry at `0x100`.

Also fixed, outside the SMP patch: OpenBIOS `switch-arch` collapses `arm64` to
`arm`, so Apple Silicon is detected as a 32-bit host and forthstrap truncates
pointers. Upstream's aarch64 fix only helps Linux, where `uname -m` is
`aarch64`. Worth reporting upstream.

### Where it stands

- `-smp 1` and `-smp 2`: boot to the desktop.
- `-smp 4`: kernel starts, stalls waiting for the root device.

4 is probably a guest limit, not ours. The emulated machine is **MacRISC2PE**,
a G4 PowerMac, and no G4 Apple shipped had more than 2 CPUs, so Leopard's
platform code likely cannot start more than one secondary. 10.5 does run 4 CPUs
on the Quad G5, but that is MacRISC4 (U3/U4 + K2), which QEMU cannot boot and
which this plan already puts out of scope. E-Maculation independently reported
"four are emulated, but the OS only recognizes two".

Treat "OS X 10.4 and 10.5 with 4 cpus" in the community release notes as four
device tree *nodes*, which is what the CI boot test measures, not four running
CPUs.

### Still open

- `hostinfo` in a 2-CPU guest, to confirm both CPUs are actually scheduled
  rather than enumerated. This is the last unverified claim.
- MTTCG stability under load (the plan's canary tests). A guest build with
  `-j2` is the obvious stressor.
- Phase A, the Intel 10.5 builder lane, is untouched.
