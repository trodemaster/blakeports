# CLAUDE.md — macports-cache

## Purpose

macports-cache is a local HTTP server that caches MacPorts binary archives (`.tbz2` files) and serves them to MacPorts clients on the local network. The primary use case is avoiding repeated from-source builds for ports that take a long time to compile, especially on beta OS versions (macOS 26 Tahoe) or vintage build machines (macOS 10.5–10.7).

MacPorts already has a binary archive protocol — this server speaks that protocol for a self-hosted cache, so no changes to MacPorts itself are needed.

## How MacPorts binary archives work

MacPorts checks `archive_sites.conf` for configured servers before compiling from source (`buildfromsource ifneeded` is the default). For each port it constructs a URL:

```
{base_url}/{subport}/{archive_filename}.tbz2
{base_url}/{subport}/{archive_filename}.tbz2.rmd160
```

Where `archive_filename` encodes the platform:
```
{portname}-{version}_{revision}+{variants}.darwin_{os_major}.{arch}
```

It fetches both files, verifies the signature with a key from `pubkeys.conf`, then installs. If fetching or verification fails it falls back to building from source (unless `-b` binary-only mode is set).

The filter in `portarchivefetch.tcl` also checks `cxx_stdlib` and `delete_la_files` fields in `archive_sites.conf` against the local MacPorts config before even attempting to fetch — these must match or the server is silently skipped. `setup-client.sh` detects the Darwin kernel version and writes the correct values.

## Signing — the critical detail

MacPorts uses RSA PKCS#1 v1.5 with RIPEMD-160 hashing. The signature must use the Teletrust OID `1.3.36.3.2.1` in the DigestInfo structure — this is what `openssl dgst -ripemd160 -sign` produces.

**Go 1.22+ uses the ISO OID `1.0.10118.3.0.49` for RIPEMD-160** when you call `rsa.SignPKCS1v15(rand, key, crypto.RIPEMD160, hash)`. This is a different OID and OpenSSL rejects the signature.

The fix in `main.go` (see `rmd160DigestInfo` and the `sign` function): manually construct the DigestInfo bytes with the Teletrust OID and sign with `hash=0` (raw bytes, no DigestInfo wrapping by Go). This produces signatures that verify correctly with both MacPorts OpenSSL and the `openssl` CLI.

Do not change this signing approach without re-running the compatibility test:
```bash
# Sign with Go-generated key, verify with MacPorts openssl
/opt/local/bin/openssl dgst -ripemd160 -verify pubkey.pem \
    -signature archive.tbz2.rmd160 archive.tbz2
```

## File structure

```
tools/macports-cache/
├── main.go                   Single-file Go server (~230 lines)
├── go.mod / go.sum           One external dep: golang.org/x/crypto/ripemd160
├── Makefile                  Build, install, day-to-day management
├── config.mk                 Git-ignored local overrides (PORT, CACHE_DIR, MOUNT)
├── README.md                 User-facing docs
├── CLAUDE.md                 This file
└── scripts/
    ├── submit-archive.sh     Run on build machines to push archives to cache
    └── setup-client.sh       Run on client machines to configure MacPorts
```

The cache directory layout on disk:
```
CACHE_DIR/
├── .privkey.pem              RSA-2048 private key, mode 0600
├── pubkey.pem                RSA public key, served at GET /pubkey.pem
└── {subport}/
    ├── {imagename}.tbz2
    └── {imagename}.tbz2.rmd160
```

## Key design decisions

**Publishing via file share, not HTTP PUT.** Build machines mount the cache directory (AFP/SMB) and copy archives directly. This means:
- No authentication logic in the server
- `submit-archive.sh` needs only `sh`, `cp`, `tar` — runs on Mac OS X 10.5
- Server auto-signs newly-arrived archives every 15 seconds (configurable via `-sign-interval`)
- Additionally signs on-demand if a `.rmd160` GET arrives before the scan fires

**Single file server, no routing logic.** `http.ServeFile` handles GET requests at `/{portname}/{filename}`. MacPorts constructs the exact URL it needs based on its own platform — the server just has to have the file.

**RSA keypair generated on first run.** Stored in the cache directory (`.privkey.pem` mode 0600, `pubkey.pem` world-readable). If the cache directory is wiped, a new keypair is generated and all client machines need to re-run `setup-client.sh`.

**Multiple platforms coexist naturally.** The platform is encoded in the filename. No routing or platform-detection logic in the server.

## macports-cache server flags

```
-port int           HTTP listen port (default 8030)
-dir string         Cache directory, also the file-share root
-sign-interval dur  How often to scan for unsigned archives (default 15s)
```

## Makefile targets

- `make install` — build, install to `~/bin/macports-cache`, write launchd plist, load agent
- `make reinstall` — rebuild and reload without touching cache data (use after code changes)
- `make uninstall` — unload agent and remove binary/plist; cache data is left untouched
- `make submit PORTNAME=xxx [MOUNT=path]` — wrapper around `submit-archive.sh`
- `make setup-client HOST=xxx` — wrapper around `setup-client.sh` (requires sudo)
- `make status` — launchd list + `GET /status`
- `make logs` — `tail -f` the log

## submit-archive.sh behavior

The script handles two MacPorts image formats:
1. **Old MacPorts (pre-2.0):** `.tbz2` files directly in `software/{portname}/` — just copied
2. **Modern MacPorts (2.x):** Directory images in `software/{portname}/{imagename}/` — re-archived with `tar -cjf` on the fly before copying

The re-archived format (`+CONTENTS`, `+PORTFILE`, `+STATE`, etc. + `opt/` tree with the installed files) matches what MacPorts' `archive` phase produces. **This has a caveat: test one real `sudo port -b install` after first use to confirm MacPorts accepts the archive structure before relying on it broadly.**

## setup-client.sh behavior

Runs on each MacPorts machine that should consume from the cache:
1. Downloads `pubkey.pem` from the server and saves it to `/opt/local/share/macports/macports-cache-pubkey.pem`
2. Appends that path to `/opt/local/etc/macports/pubkeys.conf`
3. Appends an entry to `/opt/local/etc/macports/archive_sites.conf` with:
   - The server URL
   - `cxx_stdlib libc++` or `libstdc++` depending on Darwin major version (threshold: 13)
   - `delete_la_files yes` or `no` depending on Darwin major version (threshold: 13)

## Common tasks

**After changing PORT or CACHE_DIR:**
```bash
make reinstall   # rewrites plist with new values and reloads
```

**Key rotation (e.g. after cache dir wipe):**
```bash
make restart     # new key generated on start; re-run setup-client on all clients
```

**Check what's in the cache:**
```bash
curl http://localhost:8030/status
find ~/Library/Caches/macports-cache -name "*.tbz2" | sort
```

**Manually verify a signature:**
```bash
/opt/local/bin/openssl dgst -ripemd160 \
    -verify ~/Library/Caches/macports-cache/pubkey.pem \
    -signature ~/Library/Caches/macports-cache/portname/archive.tbz2.rmd160 \
    ~/Library/Caches/macports-cache/portname/archive.tbz2
```
