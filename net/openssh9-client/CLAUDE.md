# openssh9-client: notes for future work

A client-only OpenSSH 9.x port. Every binary gets a `9` suffix (`ssh9`,
`scp9`, `sftp9`, `ssh-add9`, …) and its config lives in `${prefix}/etc/ssh9/`,
so it can sit next to the `openssh` port and Apple's ssh. We need it to reach
legacy Macs (10.5–10.11, PPC included): those run old sshd versions that
modern clients won't negotiate with, and it's 9.x because OpenSSH 10.0
removed DSA (see the `legacy_dsa` variant).

**Scope (from the user):** it's only for connecting to the user's legacy VMs.
No FIDO, PKCS#11 or other hardware-token support, so don't add it back.
It's not being upstreamed to macports-ports, so keep it simple rather than
trying to match upstream conventions.

Last updated: 2026-10-18 (session that bootstrapped MacPorts on the g5-test
Leopard QEMU guest).

## Who uses it

| Consumer | Where | How |
|---|---|---|
| `oldssh` / `oldscp` | `~/Developer/machine-cfg/scripts/` | Wrap `/opt/local/bin/ssh9` / `scp9` with the legacy `-o` options |
| `setupoldmac` | `scripts/setupoldmac` | `OLDSSH_CMD`/`OLDSCP_CMD` (and `NEWERLEGACY*`) use `ssh9`/`scp9` |
| `ghrunner` | `scripts/ghrunner` | `LEGACY_SSH_CMD="ssh9"` for the legacy VM runners |

If you change binary names or paths, check all three.

## How the port works

- `post-destroot` renames `ssh scp ssh-add ssh-agent ssh-keygen ssh-keyscan sftp`
  to `*9`, deletes all man pages, the server binaries (`sshd`, `sshd-session`,
  `sftp-server`, `ssh-keysign`), the `ssh-pkcs11-helper`/`ssh-sk-helper`
  helpers (always built by `Makefile.in` `TARGETS`, even with the features
  disabled) and the server config, and renames
  `ssh_config` to `ssh_config.example`. `post-activate` copies it into place if
  `ssh_config` is missing.
- `files/macports-config.patch` is the stock MacPorts openssh patch
  (`SendEnv LANG LC_*` in `ssh_config`, plus man page notes). The patch
  touches `configure.ac`, so `use_autoreconf yes`.
- On macOS 27+, `--with-sandbox=no`: the 27 SDK drops
  `kSBXProfilePureComputation`, which the darwin privsep sandbox uses, and
  that sandbox only confines sshd, which we don't install.
- `platform darwin 10` adds `port:cctools` (old ranlib can't read the objects).
- `--disable-pkcs11 --disable-security-key`: no hardware-token support (see
  Scope). The `fido2` variant was removed 2026-10-18 for the same reason.

### scp9/sftp9 exec ssh9 (fixed 2026-10-18)

OpenSSH compiles the ssh path into `scp` and `sftp` from the Makefile
variable `SSH_PROGRAM` (`Makefile.in` `PATHS=` → `_PATH_SSH_PROGRAM`,
default `@bindir@/ssh`). Renaming the binaries in post-destroot doesn't
update it, so the port passes `build.args-append SSH_PROGRAM=${prefix}/bin/ssh9`.
Only the build needs it: `make install` doesn't recompile.

Before the fix, `scp9 host:…` failed with
`/opt/local/bin/ssh: No such file or directory` (`sftp9` too), unless the
`openssh` port happened to be installed, in which case it silently used that
ssh instead. The workaround was `scp9 -S ssh9`. It's no longer needed
anywhere, so don't reintroduce it.

Compiled-in paths that point at nothing (harmless, left alone):
`ssh-askpass` (GUI password prompts), `ssh-keysign` (hostbased auth, deleted
on purpose) and `ssh-sk-helper` (the string stays in `ssh9` but is never used
with `--disable-security-key`).

## Verifying a change

No revision bumps in blakeports. Reinstall in place:

```bash
cd ~/Developer/blakeports
portindex
port lint --nitpick openssh9-client
sudo port uninstall openssh9-client
sudo port clean --all openssh9-client
sudo port install -s openssh9-client

# scp9 and sftp9 must show /opt/local/bin/ssh9; libexec should be empty
for b in scp9 sftp9 ssh9 ssh-agent9; do
    printf '%-11s ' $b
    strings /opt/local/bin/$b | grep -E '^/opt/local/(bin/ssh|libexec/ssh)' | sort -u | tr '\n' ' '
    echo
done
port contents openssh9-client | grep -E 'bin/|libexec/'
```

Then a live test against a legacy guest (see below): `oldssh host true`,
`oldscp file host:/tmp/`, plain `scp9` and `scp9 -O` with the same options,
and `echo 'ls /tmp' | sftp9 <opts> -b - host`. The last full run used
`scripts/setupoldmac <host>`, which exercises `ssh9`, `ssh9 -t` and `scp9`.

## Talking to legacy Macs

Options in use (from `oldssh`):

```
-i ~/.ssh/oldmac
-o HostKeyAlgorithms=ssh-rsa
-o PubkeyAcceptedKeyTypes=ssh-rsa
-o KexAlgorithms=diffie-hellman-group14-sha1,ecdh-sha2-nistp256,diffie-hellman-group1-sha1
-o Ciphers=aes128-ctr,aes128-cbc
-o MACs=hmac-sha1
```

- **Leopard 10.5.8:** sshd is `OpenSSH_5.1` and offers host keys `ssh-rsa,ssh-dss`
  only. It negotiates `diffie-hellman-group14-sha1`, `ssh-rsa`, `aes128-ctr`,
  `hmac-sha1`, so setupoldmac's "newer legacy" set works on 10.5 as well.
  Both scp modes work: the default SFTP mode (10.5 ships
  `/usr/libexec/sftp-server`) and `-O` (legacy scp protocol).
- If you call `scp9`/`ssh9` directly **without** those options you get
  `Unable to negotiate … no matching host key type found. Their offer:
  ssh-rsa,ssh-dss`. That's the missing options, not a port bug.
  Use `oldssh`/`oldscp`, or copy the options.
- `PubkeyAcceptedKeyTypes` is the old name for `PubkeyAcceptedAlgorithms`;
  9.9 still accepts it.
- From a sandboxed Claude session, LAN hosts fail with
  `Operation not permitted`: ssh/scp/ping to guests need the sandbox
  disabled for that command.
- Streaming works as a fallback: `oldssh host 'cat > /tmp/f' < f`.

### Test target

The g5-test Leopard PPC QEMU guest (bridged, `192.168.234.196`, user `blake`,
`oldmac` key in `authorized_keys`, NOPASSWD sudo, MacPorts 2.12.7 with
MacPorts curl). Launcher:
`~/Developer/ppc-10.5/Qemu-system-pcc64-G5-openbios-macOS-15-10-2026/Machines/g5-test/run-cat7.command`
(run it with `SMP=8`: the guest kernel-panicked twice under build load with 16
vCPUs). The guest may not be running; check with `ping` first.

## Open items

- `oldscp` in machine-cfg had the same `scp9`→`ssh` bug before this fix. It
  works now with no changes, but only on machines where the port has been
  reinstalled since the fix (verified on the Mac-Studio host 2026-10-18).
