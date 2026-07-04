# macports-cache

A lightweight HTTP server that caches MacPorts binary archives locally. Useful when you have build machines on slow or vintage OS versions where compiling from source takes a long time — build once, cache the binary, and every other machine on the network installs in seconds.

## How it works

MacPorts already has a binary archive system. When you install a port it checks configured `archive_sites` for a pre-built `.tbz2` before compiling. The official `packages.macports.org` servers cover standard configurations, but not beta OS versions, vintage OS versions, or custom ports in local repositories.

This server fills that gap:

1. **Build** the port on any machine (fast or slow)
2. **Submit** the built image to the cache via a file share mount
3. **Server auto-signs** the archive with its RSA key within 15 seconds
4. **Other machines** download and verify the signed archive from the server — no build required

Archives for multiple OS versions and CPU architectures coexist in the same cache. MacPorts clients always request their own platform's filename, so `netatalk-4.4.0_0.darwin_25.arm64.tbz2` and `netatalk-4.4.0_0.darwin_10.i386.tbz2` live side by side under `/netatalk/` and each client gets the right one automatically.

## Archive filename format

```
{portname}-{version}_{revision}+{variants}.darwin_{os_major}.{arch}.tbz2
```

Examples:
```
netatalk-4.4.0_0.darwin_25.arm64.tbz2        macOS 26 / Apple Silicon
netatalk-4.4.0_0.darwin_24.x86_64.tbz2       macOS 15 / Intel
netatalk-4.4.0_0.darwin_10.i386.tbz2         Mac OS X 10.6 / 32-bit
gsettings-desktop-schemas-50.0_0.any_any.noarch.tbz2   platform-independent
```

## Quick start

### 1. Install the cache server

```bash
cd tools/macports-cache
make config        # write config.mk with defaults — edit before installing
make install       # go install binary, write launchd agent, start server
```

`make config` prints and writes a `config.mk` (git-ignored) with all overridable values:

```makefile
PORT      = 8030
CACHE_DIR = /Users/you/Library/Caches/macports-cache
MOUNT     = /Volumes/macports-cache
```

You can also pass overrides directly on the command line and they get written into `config.mk`:

```bash
make config PORT=9000 CACHE_DIR=/Volumes/BigDisk/macports-cache
make install
```

The binary is installed via `go install` to `$GOBIN` (or `$GOPATH/bin` if `$GOBIN` is not set). This path is not configurable — use standard Go toolchain conventions to control it.

On first run the server generates an RSA keypair and prints client setup instructions.

### 2. Share the cache directory

In **System Settings → General → Sharing → File Sharing**, add the cache directory (`~/Library/Caches/macports-cache` by default). Build machines will mount this to submit archives.

### 3. Configure client machines

Run once on each machine that should pull binaries from the cache:

```bash
sudo make setup-client HOST=mymac.local
# or directly:
sudo ./scripts/setup-client.sh mymac.local 8030
```

This downloads the server's public key, adds it to `pubkeys.conf`, and writes the right entry into `archive_sites.conf` (including the correct `cxx_stdlib` and `delete_la_files` values for the client's OS version).

### 4. Submit builds from build machines

On the build machine, install the port normally, then mount the cache share and submit:

```bash
# Build the port
sudo port install netatalk

# Mount the cache share (AFP or SMB)
# e.g. Finder → Go → Connect to Server → afp://mymac.local

# Submit
./scripts/submit-archive.sh netatalk /Volumes/macports-cache
```

The script has zero dependencies beyond the standard shell, `cp`, and `tar` — it runs on Mac OS X 10.5 and up.

From the server machine you can also use:
```bash
make submit PORTNAME=netatalk
```

### 5. Test

```bash
# -b forces binary-only mode — fails immediately if the cache doesn't have it
sudo port -b install netatalk

# Or normal mode with fallback to source
sudo port install netatalk
```

## Management

```
make config         Write config.mk with current effective values (edit to customise)
make build          Compile the server binary
make install        Build, install binary + launchd agent, start server
make reinstall      Rebuild and reload without touching cache data
make uninstall      Stop and remove binary + launchd agent (cache data untouched)
make start          Start the launchd agent
make stop           Stop the launchd agent
make restart        Restart the launchd agent
make status         Show launchd status and server health
make logs           Tail the server log
make clean          Remove the compiled binary
make submit         Submit a port  [PORTNAME=xxx] [MOUNT=path]
make setup-client   Configure a client machine  [HOST=xxx] [PORT=8030]
```

## Directory layout

```
cache-dir/
├── .privkey.pem          RSA private key (mode 0600, never leave this machine)
├── pubkey.pem            RSA public key  (served at GET /pubkey.pem)
└── {portname}/
    ├── {portname}-{version}_{rev}+{variants}.darwin_{os}.{arch}.tbz2
    └── {portname}-{version}_{rev}+{variants}.darwin_{os}.{arch}.tbz2.rmd160
```

## HTTP endpoints

| Endpoint | Description |
|---|---|
| `GET /{portname}/{archive}.tbz2` | Serve a cached archive |
| `GET /{portname}/{archive}.tbz2.rmd160` | Serve the signature (generated on-demand if missing) |
| `GET /pubkey.pem` | Server's RSA public key for client setup |
| `GET /status` | Archive count, total size, cache path |

## Signing

MacPorts verifies every downloaded archive against a signature file (`.rmd160`) using RSA/RIPEMD-160 before installing. The server generates its own keypair on first run and signs archives automatically. Clients add the server's public key to `/opt/local/etc/macports/pubkeys.conf`.

Signing is compatible with the OpenSSL command MacPorts documents:
```bash
openssl dgst -ripemd160 -sign privkey.pem -out archive.tbz2.rmd160 archive.tbz2
openssl dgst -ripemd160 -verify pubkey.pem -signature archive.tbz2.rmd160 archive.tbz2
```

## Multi-architecture / multi-OS

No special configuration needed. The platform is encoded in the filename and each MacPorts client requests its own platform's archive. The `setup-client.sh` script detects the Darwin kernel version and sets `cxx_stdlib` and `delete_la_files` in `archive_sites.conf` to match the local installation — required for MacPorts' compatibility filter to accept the cache entry.

| Darwin major | macOS version | cxx_stdlib | delete_la_files |
|---|---|---|---|
| ≤ 12 | 10.8 and earlier | libstdc++ | no |
| ≥ 13 | 10.9 and later | libc++ | yes |
