# Legacy MacPorts curl/git bootstrap — mechanism, dependency footprint, findings

How the `update-macports-legacy` workflow gives the 10.5–10.11 runner VMs a
`port` that can fetch from the modern internet, what that costs in installed
ports, and what the 2026‑09 runs actually did.

Companion docs: `DISTFILE_PREFETCH.md` (the container‑side distfile cache),
`.github/workflows/LEGACY_VM_SETUP.md` (runner/VM wiring).

---

## 1. Why

Apple's `/usr/bin/curl` and `/usr/bin/git` on Mac OS X 10.5–10.11 use
SecureTransport / ancient OpenSSL and **cannot complete a TLS handshake with
today's GitHub / distfiles.macports.org** (`tlsv1 alert protocol version`,
cert‑chain failures). So MacPorts on these VMs needs:

- **`/opt/local/bin/curl`** — the MacPorts `curl` port, `+ssl` (linked against
  MacPorts `openssl3`), used by `port` for all `curl`‑type fetches.
- **`/opt/local/bin/git`** — the MacPorts `git` port, for `fetch.type git`
  Portfiles (submodules, pinned commits). *Most* Portfiles — including
  `github.setup` ports — fetch a **tarball over HTTPS**, i.e. via curl, not git.

Circular dependency: installing MacPorts curl needs distfiles, downloading
distfiles needs curl. Broken by pre‑seeding the distfiles (see
`DISTFILE_PREFETCH.md` / `scripts/prefetch-distfiles`), then building offline.

---

## 2. How `/opt/local/bin/curl` is installed (`scripts/updatemacports`)

Two‑stage build, triggered when `/opt/local/bin/curl` is missing or broken
(`FRESH_INSTALL=true`):

1. **Stage 1** — `./configure --prefix=/opt/local` (no curlprefix) → `make` →
   `sudo make install`. A working `port` that still shells out to
   `/usr/bin/curl`.
2. **`sudo port install curl +ssl +pcre -brotli -http2 -idn -psl -zstd`** —
   builds the `curl` port from the pre‑seeded distfiles. `+ssl` = MacPorts
   `openssl3` instead of SecureTransport. The `-` variants drop features to
   trim the dependency tree.
3. **Stage 2** — `./configure --prefix=/opt/local --with-curlprefix=/opt/local`
   → rebuild → reinstall.

### What `--with-curlprefix` actually changes

It links `libcurl` into **`libexec/macports/lib/pextlib1.0/Pextlib.dylib`**
(the Tcl C extension MacPorts base uses for fetching) — **not** into
`/opt/local/bin/port`, which is a plain tclsh script and never links libcurl.

```
$ otool -L /opt/local/libexec/macports/lib/pextlib1.0/Pextlib.dylib | grep curl
    /opt/local/lib/libcurl.4.dylib          # <- configured --with-curlprefix
    # vs /usr/lib/libcurl.4.dylib           # <- NOT configured, rebuild needed
```

This is the correct "is base curl‑configured?" signal. `check_curl_configuration()`
used to `otool -L /opt/local/bin/port | grep libcurl`, which **never matched**,
so every run re‑did a full base rebuild (7 h on lion). Fixed 2026‑09‑07 to
inspect `Pextlib.dylib`.

---

## 3. How `/opt/local/bin/git` is configured (`ensure_git_configured()`)

1. If missing: `sudo port selfupdate` (stale trees fail checksums), then
   `sudo port install git +ssl +pcre -perl5_34 -doc -diff_highlight
   -credential_osxkeychain` — see §4 for why the lean variants.
2. Patch `libexec/macports/lib/port1.0/port_autoconf.tcl`:
   `variable git_path` → `/opt/local/bin/git`. MacPorts bakes `/usr/bin/git` in
   at `./configure` time; `portfetch.tcl` only auto‑overrides it on Darwin ≤ 13
   (10.9), so 10.10/10.11 need the patch.
3. `sudo /opt/local/bin/git config --system http.sslCAInfo
   /opt/local/share/curl/curl-ca-bundle.crt` so git trusts modern chains.

The whole git step is **non‑fatal** — curl is the piece the script guarantees.

---

## 4. Dependency footprint (measured on the VMs, MacPorts 2.12.6)

| VM state | ports installed |
|---|---|
| curl bootstrap only (mavericks) | **49** |
| curl + `git +ssl` **default variants** (elcapitan, first run) | **140** |
| curl + `git +ssl +pcre` **lean variants** | **~52** (git + `rsync`) |

### The curl bootstrap's ~49 ports

~24 are runtime libs (`curl curl-ca-bundle openssl3 zlib xz zstd libiconv
ncurses gettext* readline db48 …`). The other ~25 are **`openssl3`'s build
toolchain on a legacy OS**: `perl5.34` (OpenSSL's `Configure` is Perl),
`clang-11-bootstrap` (a modern compiler), `autoconf`, ~19 `p5.34-*` pod/test
modules. Largely unavoidable if the goal is real OpenSSL 3 on 10.6–10.11.

### Why default `git +ssl` added **+91 ports**

`git`'s default variants include `+perl5_34 +doc +diff_highlight
+credential_osxkeychain`. Runtime deps under those:

```
rsync, perl5.34, p5.34-authen-sasl, p5.34-error, p5.34-net-smtp-ssl,
p5.34-term-readkey, p5.34-cgi
```

which recurse into ~85 more `p5.34-*` modules + `kerberos5` (via
Authen::SASL → GSSAPI) + the `IO::Socket::SSL` / `Net::SSLeay` stack +
`HTML::Parser` / `LWP` + test frameworks, plus `libarchive icu libxml2 lmdb
autoconf automake libtool`. **All of it serves `git send-email` / `git svn` /
`contrib/diff-highlight` (a Perl script) — none of which git‑type port fetches
use.**

### Lean git — `git +ssl +pcre -perl5_34 -doc -diff_highlight -credential_osxkeychain`

Resolves to `git @2.12.x+pcre`. Deps: `curl zlib expat gettext-runtime
libiconv pcre2` (**all already present** from the curl bootstrap) + `rsync`
(the only genuinely new port). Core `git clone` / `git fetch` over HTTPS is
pure C on libcurl and fully intact; only `git send-email`, `git svn`,
`git cvsimport`, `git archimport` are dropped.

---

## 5. 2026‑09‑06/07 run results (`update-macports-legacy`, 7 x86 VMs)

Dispatched with `-f macports_version=2.12.6` (the script's own "latest"
detection uses system curl and fails on legacy → wrongly defaults to 2.11.6,
so the tarball the workflow pre‑fetches must be pinned).

| VM | Darwin | outcome | live state after |
|---|---|---|---|
| **elcapitan** 10.11 | 15 | ✅ full success (52 m) | `port 2.12.6` + mpcurl 8.13.0 + mpgit 2.52.0 |
| lion 10.7 | 11 | ❌ (7 h 31 m) | mpcurl ✓; `git +ssl` hit a stale‑tree dep cycle (wanted clang‑16/llvm‑16) |
| snowleopard 10.6 | 10 | ❌ (2 h 19 m) | mpcurl ✓; `git +ssl` → checksum mismatch `Authen-SASL-2.1900.tar.gz` |
| mountainlion 10.8 | 12 | ❌ (33 m) | mpcurl ✓; `git +ssl` → checksum mismatch `Socket-2.040.tar.gz` |
| mavericks 10.9 | 13 | ❌ (35 m) | mpcurl ✓; `git +ssl` → checksum mismatch `Pod-Simple-3.47.tar.gz` |
| yosemite 10.10 | 14 | ❌ (37 m) | mpcurl ✓; `git +ssl` → checksum mismatch `Encode-3.21.tar.gz` |
| leopard 10.5 | 9 | ❌ (4 m) | **unchanged** — Stage 1 base build fails: `curl.c:510: error: 'CURLOPT_NOPROXY' undeclared` (MacPorts 2.12.6 too new for 10.5's libcurl headers) |

**6 of 7 got the macports‑curl `port`** built cleanly through the
`--with-curlprefix` two‑stage path. The failures were all *after* curl, in
`ensure_git_configured` (stale ports tree → checksum mismatches on perl
modules; `port selfupdate` was never run), or — for 10.5 — before curl in the
base build.

---

## 6. Fixes applied (PR #4, merged to `main` 2026-09-07)

`scripts/updatemacports`:

1. **`check_curl_configuration()`** inspects `Pextlib.dylib`, not `bin/port`.
   A working mpcurl + matching version is now a real no‑op instead of forcing
   a rebuild every run.
2. **Lean git variants** (§4) — `git +ssl +pcre -perl5_34 -doc
   -diff_highlight -credential_osxkeychain`. +91 ports → +2.
3. **`port selfupdate`** before `port install git`, `port clean git` to drop
   any variant‑mismatched partial build, and the whole git step **non‑fatal**
   at both call sites.
4. **`trim_build_deps()`** — after curl + git are built, `port uninstall
   inactive` then sweep `port uninstall leaves` until the cascade stops. Drops
   the clang/llvm/cctools bootstrap, autotools, and the perl5.34 + p5.34‑*
   tree (openssl3 / git *build* deps). MacPorts protects the `requested`
   ports and their live closure. Measured: **48–191 ports → ~13–19** per VM.

Workflows: `update-macports-legacy` per‑job `timeout` 120 → 480 min; all 8
legacy workflows renamed `tenfive…teneleven`/`tenfive-ppc` →
`leopard…elcapitan`/`leopard-ppc` (matches the darkstar container runner
labels).

### leopard (10.5) — MacPorts 2.12.6 base won't compile

`curl.c:510: error: 'CURLOPT_NOPROXY' undeclared` while building `pextlib`.
Tracked upstream:

- **[trac #74362](https://trac.macports.org/ticket/74362)** — "port 2.12.6 does
  not build on PPC Leopard, Mac OS X 10.5.8 … 'CURLOPT_NOPROXY' undeclared" —
  **closed: fixed**. ( **[#74365](https://trac.macports.org/ticket/74365)** —
  "doesn't build on <10.6" — closed as duplicate.)
- Introduced by macports-base commit `8749f963` (2026‑05‑04, "Don't rely on env
  vars for curl in worker threads"): added `curl_easy_setopt(…,
  CURLOPT_NOPROXY, …)`. That option needs libcurl ≥ 7.19.4 (2009); Apple's
  system libcurl on 10.5 is older.
- Fixed by commit `847bfc23` (2026‑08‑26, "Guard use of CURLOPT_NOPROXY"):
  `#if LIBCURL_VERSION_NUM >= 0x071304` around both call sites. On the
  `release-2.12` branch and as a patchfile in `sysutils/MacPorts` — **not in
  any released tag yet** (latest is v2.12.6; fix lands in v2.12.7).

| MacPorts base | 10.5 build |
|---|---|
| ≤ v2.12.5 | ✅ ok (predates `8749f963`) |
| v2.12.6 | ❌ CURLOPT_NOPROXY |
| release‑2.12 / future v2.12.7 | ✅ fixed |

**Our fix:** pin `-f macports_version=2.12.5` for the 10.5 line. `leopard-ppc`
already sits on 2.12.5 with a working mpcurl — leave it. Move both to v2.12.7
once released.

### Pre‑fix bloat still on some VMs (2026‑09)

`snowleopard` (~84 `p5.34-*`) and `elcapitan` (~99 `p5.34-*`, fat `git`
variants) carry the perl tree from runs that happened before the lean‑git fix.
git on `snowleopard` is already lean; the orphaned deps just weren't swept.
Cleanup: on `elcapitan` `port -f uninstall git` then reinstall lean; then on
both `sudo port uninstall leaves` (repeat until none) to drop build‑only
leftovers.

---

## 7. Operational notes (darkstar)

- **Runners:** 8 containers (`leopard-runner` … `leopard-ppc-runner`) via
  `~/Developer/actions_runners`; register on `trodemaster/blakeports` with
  codename labels. Container SSHes to the paired VM over OpenSSH 9.x with
  legacy crypto; `Host <codename>` alias written by the container entrypoint.
- **Distfile cache:** `darkstar` is Linux and has no `port`, so
  `scripts/cache-distfiles` can't run there.
  `actions_runners/host/cache-distfiles-from-vm.sh` mirrors the distfiles tree
  from `leopard-ppc` (the one VM with a working mpcurl) into
  `docker/config/distfiles-cache/` (mounted at `/config/distfiles-cache`).
  Distfiles are arch‑independent source tarballs; over‑inclusion is harmless.
- **Snapshots:** all 8 VMs have `pre-update-macports-2026-09-06` (live‑VM
  snapshots dump ~17 GB of RAM each — slow, ~30–50 min). Off‑disk VM backups
  and the untouched `runner-*` originals are the other rollback layers.
- **`gh` version pinning:** pass `-f macports_version=<X>` — the workflow
  pre‑fetches that tarball and the script's own detection is unreliable on
  legacy.
