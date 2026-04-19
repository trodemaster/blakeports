# MacPorts Bug Reports

Tracked issues to submit as Trac tickets at https://trac.macports.org/newticket

---

## netatalk 4.5.0beta: legacy platform build failure summary

| Platform | Darwin | Failure | Where to fix |
|---|---|---|---|
| 10.6.8 (tensix) | 10 | `py-meson` patch fails (MacPorts bug) | Upstream MacPorts (see below) |
| 10.7.5 (tenseven) | 11 | `nad_ls.c:638` incompatible function pointer type | Netatalk upstream + Portfile workaround ✅ |
| 10.8.5 (teneight) | 12 | `stdatomic.h` not found in system clang SDK | Portfile compiler.blacklist ✅ |
| 10.9.5 (tennine) | 13 | `stdatomic.h` not found in system clang SDK | Portfile compiler.blacklist ✅ |
| 10.10+ (tenten, teneleven) | 14-15 | — | N/A (pass) |

Items marked ✅ have been fixed in the Portfile.

---

## py-meson: patch-wheel-pyproject.toml.diff fails on meson 1.10.0+

**Port:** `py-meson` (all Python subports: py39-meson through py314-meson)  
**Version:** 1.10.0 (rsync servers as of 2026-04-19); also present in 1.10.2 in macports/macports-ports  
**Category:** python  
**Severity:** Error (build failure, port cannot be installed)  

### Summary

`py314-meson` (and all `py*-meson` subports) fail to build because the patch
`patch-wheel-pyproject.toml.diff` no longer applies to meson 1.10.0+.

### Error

```
--->  Applying patches to py314-meson
Error: Failed to patch py314-meson: command execution failed
```

Log detail:
```
:info:patch Reversed (or previously applied) patch detected!  Skipping patch.
:info:patch 1 out of 1 hunk ignored -- saving rejects to file pyproject.toml.rej
:info:patch Command failed:  cd "...meson-1.10.0" && /usr/bin/patch -t -N -p0 < 'patch-wheel-pyproject.toml.diff'
:info:patch Exit code: 1
:error:patch Failed to patch py314-meson: command execution failed
```

### Root Cause

The patch removes `"wheel"` from `pyproject.toml`'s build requirements:

```diff
--- pyproject.toml.orig 2025-04-11 22:09:12
+++ pyproject.toml      2025-04-11 22:09:21
@@ -1,3 +1,3 @@
 [build-system]
-requires = ["setuptools>=42", "wheel"]
+requires = ["setuptools>=42"]
 build-backend = "setuptools.build_meta"
```

However, meson 1.10.0 already ships with this change incorporated upstream — its
`pyproject.toml` already contains `requires = ["setuptools>=42"]` without `"wheel"`.
The patch was written for an older meson version (≤ 1.9.x) and is now stale.

Confirmed by extracting the meson 1.10.0 tarball:

```
[build-system]
requires = ["setuptools>=42"]
build-backend = "setuptools.build_meta"
```

### Fix

Remove `patchfiles patch-wheel-pyproject.toml.diff` from the Portfile (and delete
the patch file) since the change is now included in the upstream meson source.

If guard needed for older meson versions still in the port, restrict the patchfile
to those versions only.

### Reproduction

```bash
sudo port install py314-meson
# Fails at the "Applying patches" phase
```

### Environment Tested

- macOS 10.6.8 Snow Leopard (Darwin 10.8.0) with MacPorts 2.12.4
- `port sync` run immediately before to ensure latest port tree from rsync

### References

- Portfile: `python/py-meson/Portfile`
- Patch file: `python/py-meson/files/patch-wheel-pyproject.toml.diff`
- Upstream meson 1.10.0 release: https://github.com/mesonbuild/meson/releases/tag/1.10.0

---

## netatalk: incompatible function pointer type in bin/nad/nad_ls.c (UPSTREAM)

**Report to:** https://github.com/Netatalk/netatalk/issues  
**Version:** 4.5.0beta  
**Affects:** macOS 10.7 (Darwin 11) with clang-mp-16  

### Summary

`bin/nad/nad_ls.c:638` passes a comparator with signature
`int (const struct dirent **, const struct dirent **)` to `scandir()` which
expects `int (*)(const void *, const void *)`. clang 16+ treats this as a hard
error (`-Wincompatible-function-pointer-types`), breaking the build.

### Error

```
../netatalk-4.5.0beta/bin/nad/nad_ls.c:638:39: error: incompatible function pointer
types passing 'int (const struct dirent **, const struct dirent **)' to parameter
of type 'int (*)(const void *, const void *)' [-Wincompatible-function-pointer-types]
    n = scandir(".", &namelist, NULL, compare_names);
```

### Fix

Change `compare_names` to use `const void *` parameters and cast internally:

```c
static int compare_names(const void *a, const void *b) {
    const struct dirent **da = (const struct dirent **)a;
    const struct dirent **db = (const struct dirent **)b;
    return strcmp((*da)->d_name, (*db)->d_name);
}
```

**Portfile workaround** (applied): `configure.cflags-append -Wno-incompatible-function-pointer-types` on Darwin ≤ 13.
