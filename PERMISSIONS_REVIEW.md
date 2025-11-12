# BlakePorts Repository Permissions Review & Update Guidance

## Executive Summary

The **blakeports** repository has **significant permission differences** from the official **macports-ports** repository that need to be addressed before submitting pull requests to the MacPorts project. This document provides a detailed analysis and step-by-step guidance to align permissions with MacPorts standards.

### Key Findings

| Issue | BlakePorts | MacPorts | Status |
|-------|-----------|---------|--------|
| **Missing .gitattributes** | ❌ None | ✅ Present | **CRITICAL** |
| **Executable bits on Portfiles** | ✅ Some marked executable | ❌ All non-executable | **HIGH** |
| **Executable bits on docs/configs** | ✅ Multiple files | ❌ Should be non-executable | **HIGH** |
| **git core.fileMode tracking** | ✅ Enabled (true) | ✅ Enabled (true) | ✓ OK |
| **Line ending normalization** | ❌ Not configured | ✅ Configured | **MEDIUM** |

---

## Problem Analysis

### 1. Missing `.gitattributes` File (CRITICAL)

**Current State in blakeports:**
```
❌ No .gitattributes file exists
```

**Reference from macports-ports:**
```
# Normalize EOLs by default, to avoid falling back on committers'
# "core.autocrlf" settings.
* text=auto

# Don't normalize EOLs of files derived from an upstream.
*.diff -text
*.patch -text
net/nagios-plugins/files/check_nt.c -text
```

**Impact:**
- Line endings (CRLF vs LF) may not be normalized across platforms
- Patch files (.diff, .patch) may get corrupted with line-ending conversions
- Inconsistent line endings across developers' machines
- MacPorts maintainers expect EOL normalization

**Solution:**
Create `.gitattributes` to match MacPorts standards.

---

### 2. Executable Bits on Non-Executable Files (HIGH PRIORITY)

**Current Issues in blakeports:**

Files with **incorrect executable bits** that should NOT be executable:
- `devel/libcbor/Portfile` - **MARKED EXECUTABLE** (wrong)
- `PortIndex.quick` - **MARKED EXECUTABLE** (wrong)
- `MACOS_DETAILS.md` - **MARKED EXECUTABLE** (wrong)
- Multiple Docker configuration files - **MARKED EXECUTABLE**

**Reference - macports-ports has all Portfiles as NON-EXECUTABLE:**
```bash
.rw-r--r--  Portfile      # Correct: NOT executable
.rw-r--r--  .gitattributes # Correct: NOT executable
```

**Current blakeports examples:**
```bash
.rw-r--r-x  Portfile      # WRONG: Shows 'x' bit
.rw-r--r-x  PortIndex.quick  # WRONG: Shows 'x' bit
```

**Why This Matters:**
- MacPorts expects consistent, predictable permissions
- Code review tools flag permission changes as suspicious
- Reviewers question whether these should really be executable
- Clutters git diffs with unnecessary permission changes
- Prevents smooth integration into official macports-ports

**Files That SHOULD Remain Executable:**
```
scripts/afp_tests (shell script)
scripts/fulltest (shell script)
scripts/ghrunner (shell script)
scripts/install-deps (shell script)
scripts/installmacports (shell script)
scripts/setupoldmac (shell script)
scripts/syncfromgitports (shell script)
```

---

### 3. Line Ending Issues (MEDIUM PRIORITY)

**Current State:**
- blakeports has NO configuration for line ending normalization
- Each developer's git config may differ (`core.autocrlf` settings vary)
- Patch files (.diff) may get corrupted with CRLF conversions on Windows/mixed environments

**MacPorts Approach:**
- Explicit `.gitattributes` ensures consistent behavior across all platforms
- Patch files marked with `-text` to prevent EOL conversion
- Universally understood and enforced

---

## Implementation Guidance

### STEP 1: Create `.gitattributes` File

**Action:** Create `/Users/blake/code/blakeports/.gitattributes`

**Content:**
```
# Normalize EOLs by default, to avoid falling back on committers'
# "core.autocrlf" settings.
* text=auto

# Don't normalize EOLs of files derived from an upstream.
*.diff -text
*.patch -text
```

**Command:**
```bash
cat > /Users/blake/code/blakeports/.gitattributes << 'EOF'
# Normalize EOLs by default, to avoid falling back on committers'
# "core.autocrlf" settings.
* text=auto

# Don't normalize EOLs of files derived from an upstream.
*.diff -text
*.patch -text
EOF
```

**Verification:**
```bash
cd /Users/blake/code/blakeports
cat .gitattributes
git add .gitattributes
git diff --cached --name-only  # Should show .gitattributes
```

---

### STEP 2: Remove Executable Bits from Non-Executable Files

**Action:** Use `chmod` to remove execute permissions from files that shouldn't have them.

**Files to Fix:**
```bash
cd /Users/blake/code/blakeports

# Portfiles - should NOT be executable
chmod -x devel/libcbor/Portfile
chmod -x audio/nrsc5/Portfile
chmod -x emulators/previous/Portfile
chmod -x net/netatalk/Portfile
chmod -x net/openssh9-client/Portfile
chmod -x security/libfido2/Portfile
chmod -x security/vault/Portfile
chmod -x textproc/bstring/Portfile

# Data files - should NOT be executable
chmod -x PortIndex
chmod -x PortIndex.quick
chmod -x MACOS_DETAILS.md
chmod -x docker/actions-runners/example.env
chmod -x docker/actions-runners/docker-compose.yml
chmod -x docker/actions-runners/docker-compose-multi.yml
chmod -x docker/actions-runners/Dockerfile
chmod -x docker/actions-runners/generate-token.sh
chmod -x docker/actions-runners/SETUP.md
chmod -x docker/actions-runners/quickstart-multi.sh
chmod -x docker/actions-runners/MULTI_RUNNER_SUMMARY.md
chmod -x docker/actions-runners/MULTI_RUNNER_SETUP.md
chmod -x docker/actions-runners/README.md
chmod -x docker/actions-runners/SCALING.md
chmod -x docker/actions-runners/entrypoint.sh
chmod -x .cursorrules
chmod -x .env
chmod -x .gitignore
chmod -x ACTIONS.md
chmod -x LICENSE
chmod -x README.md
chmod -x MACPORTS_SUBMISSIONS.md
chmod -x blakeports.code-workspace
chmod -x setupenv.bash
```

**One-Line Command to Fix All Non-Executable Files:**
```bash
cd /Users/blake/code/blakeports
find . -type f ! -path './.git/*' ! -path './docker/actions-runners/.gitkeep' \
  ! -name 'afp_tests' ! -name 'fulltest' ! -name 'ghrunner' \
  ! -name 'install-deps' ! -name 'installmacports' ! -name 'setupoldmac' \
  ! -name 'syncfromgitports' ! -name 'vmwvm-start' \
  -perm +111 -exec chmod -x {} +
```

**Verification:**
```bash
# Check that Portfiles are NOT executable
ls -la devel/libcbor/Portfile
# Should show: .rw-r--r--

# Check that scripts ARE executable
ls -la scripts/installmacports
# Should show: .rwxr-xr-x
```

---

### STEP 3: Commit Permission Changes

**Important:** Git tracks permission changes separately. Use atomic commits.

```bash
cd /Users/blake/code/blakeports

# Stage the .gitattributes file
git add .gitattributes

# View what changed
git status

# Commit the new .gitattributes
git commit -m ".gitattributes: normalize line endings per MacPorts standards

Add .gitattributes to ensure consistent line ending handling across
all platforms. This configuration:

* Normalizes EOLs for all files by default (text=auto)
* Preserves EOLs in patch files (.diff, .patch) to prevent corruption
* Matches the standard used in the official macports-ports repository

This prevents line ending differences from cluttering git diffs and
ensures patches are handled correctly across Windows, macOS, and Linux."
```

**Then Fix Permissions:**
```bash
# Remove execute bits from non-executable files
find . -type f ! -path './.git/*' \
  ! -name 'afp_tests' ! -name 'fulltest' ! -name 'ghrunner' \
  ! -name 'install-deps' ! -name 'installmacports' ! -name 'setupoldmac' \
  ! -name 'syncfromgitports' ! -name 'vmwvm-start' \
  -perm +111 -exec chmod -x {} +

# Verify changes
git status

# Commit permission fixes
git commit -m "permissions: remove executable bits from non-executable files

Files should only be executable if they are shell scripts or binaries.
Portfiles, configuration files, markdown documentation, and data files
must not have the executable bit set.

This aligns blakeports with the permission model used in the official
macports-ports repository, which will simplify pull requests and code
review."
```

---

### STEP 4: Verify Git Configuration

**Ensure file mode tracking is enabled (it already is):**
```bash
cd /Users/blake/code/blakeports
git config core.fileMode

# Output should be: true
```

**If not enabled (shouldn't be needed, but just in case):**
```bash
git config core.fileMode true
```

---

### STEP 5: Update `.gitignore` (Optional Enhancement)

**Current `.gitignore` is good but could be more explicit:**
```
.env
.DS_Store
work
```

**Enhanced version (optional):**
```
# Environment files
.env
.env.local
.env.*.local

# macOS system files
.DS_Store
.AppleDouble
.LSOverride

# Build/work directories
work/
build/
dist/

# IDE
.vscode/
.idea/
*.code-workspace

# Logs
*.log
```

---

## Pre-Submission Checklist

### Before Creating PRs to macports-ports

- [ ] **`.gitattributes` file created** with MacPorts standard content
- [ ] **All Portfiles are NON-executable** (`-x` bit removed)
- [ ] **All scripts in `scripts/` ARE executable** (`+x` bit present)
- [ ] **Documentation files are NON-executable** (Markdown, config files)
- [ ] **`git config core.fileMode` is `true`**
- [ ] **Permission changes committed** as distinct, atomic commits
- [ ] **Run `git status` before pushing** to verify no stray permission changes
- [ ] **Each Portfile runs `port lint --nitpick`** with zero errors

### Command to Verify All Permissions

```bash
cd /Users/blake/code/blakeports

# Check Portfiles are NOT executable
find . -path ./.git -prune -o -name "Portfile" -type f -exec ls -la {} \; | grep "x"
# Should return NOTHING (empty)

# Check scripts ARE executable
ls -la scripts/
# Should show all scripts with 'x' in permission string

# Verify .gitattributes exists
test -f .gitattributes && echo "✅ .gitattributes exists" || echo "❌ Missing .gitattributes"
```

---

## Why This Matters for MacPorts Submissions

### 1. **Code Review Cleanliness**
- Reviewers won't question permission changes on Portfiles
- Git diffs stay focused on actual content changes
- Reduces cognitive load during review

### 2. **Repository Consistency**
- Matches the strict conventions used in official macports-ports
- Demonstrates understanding of MacPorts standards
- Shows attention to detail and professionalism

### 3. **CI/CD Reliability**
- Patches won't be corrupted by automatic line ending conversion
- Build systems won't be confused by unexpected executable bits
- Reduces edge-case bugs related to cross-platform handling

### 4. **Contributor Experience**
- New contributors get a clear model to follow
- Reduces back-and-forth during code review
- Demonstrates mature repository practices

### 5. **Merge Compatibility**
- Cleaner git history when ports are merged upstream
- No "spurious permission changes" commits
- Smoother integration into official repositories

---

## Comparison: BlakePorts vs MacPorts Standards

### File Permission Model

| File Type | BlakePorts (Current) | MacPorts Standard | Action |
|-----------|-------------------|-----------------|--------|
| Portfile | `-rw-r--r-x` ❌ | `-rw-r--r--` ✅ | Remove executable |
| *.diff (patches) | `-rw-r--r-x` ❌ | `-rw-r--r--` ✅ | Remove executable |
| *.md (docs) | `-rw-r--r-x` ❌ | `-rw-r--r--` ✅ | Remove executable |
| shell scripts | `-rwxr-xr-x` ✅ | `-rwxr-xr-x` ✅ | Keep executable |
| .gitattributes | ❌ Missing | `-rw-r--r--` ✅ | Create file |

---

## Rollback Procedure

If needed, you can revert these changes:

```bash
cd /Users/blake/code/blakeports

# View commits to revert
git log --oneline -n 5

# Revert the permission changes (use your actual commit hashes)
git revert <commit-hash-for-permissions>
git revert <commit-hash-for-.gitattributes>

# Or reset entire changes if not yet pushed
git reset --hard HEAD~2
```

---

## Additional Resources

- **MacPorts Portfile Reference:** https://guide.macports.org/chunked/development.portfile.html
- **MacPorts Git Workflow:** https://guide.macports.org/chunked/development.practises.html
- **Git Attributes Documentation:** https://git-scm.com/docs/gitattributes
- **Official macports-ports Repository:** https://github.com/macports/macports-ports

---

## Summary of Changes

### `.gitattributes` - NEW FILE
Ensures consistent line ending handling across platforms and prevents patch corruption.

### Permission Fixes - MULTIPLE FILES
Removes executable bits from:
- All 8 Portfiles in the repository
- All documentation files (`.md` files)
- Configuration files (`.env`, `.gitignore`, etc.)
- Data files (`PortIndex`, `PortIndex.quick`)
- Docker configuration files

### Result
✅ blakeports permissions now match official MacPorts standards
✅ Ready for clean pull requests to macports-ports
✅ Reduced friction during code review
✅ Better repository hygiene and professionalism




