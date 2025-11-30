# BlakePorts Workflow Consolidation Plan

## Overview

Consolidate GitHub Actions workflows to merge regular (`build-<portname>.yml`) and legacy (`build-legacy-<portname>.yml`) workflows into single files per port. This reduces maintenance overhead while preserving full testing capability across modern and legacy macOS platforms.

## Requirements Summary

- **Trigger behavior**: Each port builds independently when its files change (current behavior maintained)
- **Default builds**: Push/PR triggers run ONLY modern builds (macOS_15, macOS_26)
- **Legacy builds**: Manual dispatch only, never automatic
- **Workflow structure**: Single matrix with conditional steps
- **File naming**: Keep current naming `build-<portname>.yml`
- **Legacy workflows deleted**: Remove `build-legacy-<portname>.yml` files after migration

## Architecture

### Workflow Structure

```yaml
on:
  push:
    paths: ['<category>/<portname>/**']  # Only this port's files
    branches: [main]
  pull_request:
    paths: ['<category>/<portname>/**']
    branches: [main]
  workflow_dispatch:
    inputs:
      branch: <optional branch selector>
      run_legacy: <boolean, default false>

jobs:
  setup-matrix:
    # Dynamically generates matrix based on trigger type
    # - push/PR: Only modern platforms
    # - workflow_dispatch with run_legacy=false: Only modern platforms
    # - workflow_dispatch with run_legacy=true: Modern + legacy platforms

  build-<portname>:
    needs: setup-matrix
    matrix: ${{ fromJSON(needs.setup-matrix.outputs.matrix) }}
    # Conditional steps based on matrix.type (modern vs legacy)
```

### Matrix Generation Logic

**For push/PR triggers** (automatic):
```yaml
matrix:
  include:
    - platform: macOS_15, runner: macOS_15, type: modern
    - platform: macOS_26, runner: macOS_26, type: modern
```

**For workflow_dispatch with run_legacy=true** (manual):
```yaml
matrix:
  include:
    - platform: macOS_15, runner: macOS_15, type: modern
    - platform: macOS_26, runner: macOS_26, type: modern
    - platform: tenfive, runner: [self-hosted, tenfive], type: legacy, ...
    - platform: tenseven, runner: [self-hosted, tenseven], type: legacy, ...
```

### Conditional Step Pattern

```yaml
steps:
  # Modern platform steps
  - name: Checkout repository
    if: matrix.type == 'modern'
    uses: actions/checkout@v4

  - name: Build port (modern)
    if: matrix.type == 'modern'
    run: sudo port -v install <portname>

  # Legacy platform steps
  - name: Download tarball
    if: matrix.type == 'legacy'
    run: curl -L -o /tmp/blakeports.tar.gz ...

  - name: Build port (legacy)
    if: matrix.type == 'legacy'
    uses: appleboy/ssh-action@v1
    with:
      host: ${{ matrix.vm_ip }}
      script: sudo port -v install <portname>
```

## Infrastructure Changes

### GitHub Secrets Consolidation

**Current state** (per-OS secrets):
- `TENFIVE_KEY`
- `TENSEVEN_KEY`

**New state** (unified secret):
- `OLDMAC_KEY` - Single SSH key for all legacy VMs

**Current state** (per-OS variables):
- `TENFIVE_IP`, `TENFIVE_USERNAME`
- `TENSEVEN_IP`, `TENSEVEN_USERNAME`

**New state** (unified naming):
- `LEGACY_TENFIVE_IP`
- `LEGACY_TENSEVEN_IP`
- `LEGACY_USERNAME` - Same username across all legacy VMs

### Runner Configuration

**Modern runners** (Tart VMs):
- `macOS_15` - macOS Sequoia (15.x)
- `macOS_26` - macOS Tahoe Beta (26.x)

**Legacy runners** (self-hosted with tags):
- `[self-hosted, tenfive]` - Mac OS X 10.5
- `[self-hosted, tenseven]` - Mac OS X 10.7

## Port-Specific Customizations

### Port: netatalk

**Location**: `.github/workflows/build-netatalk.yml`
**Port path**: `net/netatalk`

**Customizations**:
- Branch selection input (already in regular workflow)
- Special verification for `afpd` binary
- Legacy verification uses `${prefix}/sbin/netatalk` check

**Verification steps**:
```yaml
# Modern
- which afpd || echo "afpd binary not found in PATH"
- ls -la /opt/local/sbin/afpd || echo "afpd binary not found"
- /opt/local/sbin/afpd -V || echo "Could not get afpd version"

# Legacy
- if [ -f ${prefix}/sbin/netatalk ]; then echo "✅ netatalk binary found"; fi
```

### Port: bstring

**Location**: `.github/workflows/build-bstring.yml`
**Port path**: `textproc/bstring`

**Customizations**:
- Complex cleanup (handles multiple installed versions with variants)
- Tests `+tests` variant after base build

**Special cleanup**:
```yaml
port installed bstring | grep -E "^  bstring @" | awk '{print $1 " " $2}' | while read -r version_spec; do
  sudo port -f uninstall "$version_spec" || true
done
```

**Variant testing**:
```yaml
- name: Test bstring with tests variant
  run: sudo port -v install bstring +tests
```

### Port: libcbor

**Location**: `.github/workflows/build-libcbor.yml`
**Port path**: `devel/libcbor`

**Customizations**:
- Cleans related ports before building
- Standard verification

### Port: libfido2

**Location**: `.github/workflows/build-libfido2.yml`
**Port path**: `security/libfido2`

**Customizations**:
- Cleans related ports (openssl3, libcbor) before building
- Verifies multiple binaries

### Port: previous

**Location**: `.github/workflows/build-previous.yml`
**Port path**: `emulators/previous`

**Customizations**:
- Verifies .app bundle in `/Applications/MacPorts/Previous.app`
- Tests application launch with timeout
- Has variant testing

### Port: nrsc5

**Location**: `.github/workflows/build-nrsc5.yml`
**Port path**: `audio/nrsc5`

**Customizations**:
- Modern-only (no legacy workflow exists)
- Standard build and verification

## Migration Steps

### Phase 1: Preparation (30 minutes)

1. **Setup new GitHub secrets/variables**:
   ```
   Repository Settings → Secrets and variables → Actions

   Secrets:
   - Verify OLDMAC_KEY exists (or create from TENFIVE_KEY)

   Variables:
   - Create LEGACY_USERNAME (copy from TENFIVE_USERNAME)
   - Rename TENFIVE_IP → LEGACY_TENFIVE_IP
   - Rename TENSEVEN_IP → LEGACY_TENSEVEN_IP
   ```

2. **Create feature branch**:
   ```bash
   git checkout -b consolidate-workflows
   ```

### Phase 2: Migrate Each Port (6 ports × 30 min = 3 hours)

For each port (priority order: libcbor, libfido2, nrsc5, bstring, previous, netatalk):

1. **Copy existing regular workflow** as starting point
2. **Add matrix setup job** with conditional logic
3. **Update build job** to use dynamic matrix
4. **Add modern build steps** (from existing regular workflow)
5. **Add legacy build steps** (from existing legacy workflow)
6. **Add port-specific customizations** (see above)
7. **Test workflow syntax**: `yamllint .github/workflows/build-<portname>.yml`

### Phase 3: Testing (2 hours per port)

For each migrated port:

1. **Test automatic modern build**:
   - Make trivial change to Portfile (e.g., add comment)
   - Push to feature branch
   - Verify ONLY macOS_15 and macOS_26 run
   - Verify build succeeds

2. **Test manual modern-only build**:
   - Trigger workflow_dispatch with `run_legacy: false`
   - Verify ONLY macOS_15 and macOS_26 run

3. **Test manual legacy build**:
   - Trigger workflow_dispatch with `run_legacy: true`
   - Verify macOS_15, macOS_26, tenfive, tenseven all run
   - Monitor for SSH connectivity issues
   - Verify builds complete successfully

4. **Verify no legacy on automatic triggers**:
   - Confirm push/PR never triggers legacy builds

### Phase 4: Rollout (1 hour)

1. **Create pull request** with all consolidated workflows
2. **Update CLAUDE.md** documentation with new workflow_dispatch inputs
3. **Test PR builds** to ensure CI runs correctly
4. **Merge to main**
5. **Monitor production builds** for 24-48 hours

### Phase 5: Cleanup (30 minutes)

After 1-2 weeks of stable operation:

1. **Delete legacy workflow files**:
   ```bash
   git rm .github/workflows/build-legacy-*.yml
   ```

2. **Delete old secrets** (if desired):
   - `TENFIVE_KEY` (if different from OLDMAC_KEY)
   - `TENSEVEN_KEY` (if different from OLDMAC_KEY)

3. **Delete old variables** (if desired):
   - `TENFIVE_IP`, `TENFIVE_USERNAME`
   - `TENSEVEN_IP`, `TENSEVEN_USERNAME`

4. **Commit cleanup**:
   ```bash
   git commit -m "Remove legacy workflow files after consolidation"
   git push
   ```

## Workflow Template

### Complete Template Structure

```yaml
name: Build <PORTNAME>

on:
  push:
    paths: ['<PORTPATH>/**']
    branches: [main]
  pull_request:
    paths: ['<PORTPATH>/**']
    branches: [main]
  workflow_dispatch:
    inputs:
      branch:
        description: 'Branch to build from'
        required: false
        default: 'main'
        type: string
      run_legacy:
        description: 'Run legacy platform builds (10.5, 10.7)'
        required: false
        default: false
        type: boolean

defaults:
  run:
    shell: bash

jobs:
  setup-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - name: Generate build matrix
        id: set-matrix
        run: |
          # Always include modern platforms
          MATRIX='{"include":['
          MATRIX+='{"platform":"macOS_15","runner":"macOS_15","type":"modern","port":"<PORTPATH>"},'
          MATRIX+='{"platform":"macOS_26","runner":"macOS_26","type":"modern","port":"<PORTPATH>"}'

          # Add legacy platforms only if manually requested
          if [[ "${{ inputs.run_legacy }}" == "true" ]]; then
            MATRIX+=',{"platform":"tenfive","runner":["self-hosted","tenfive"],"type":"legacy","port":"<PORTPATH>","vm_ip":"${{ vars.LEGACY_TENFIVE_IP }}","vm_username":"${{ vars.LEGACY_USERNAME }}","vm_name":"TenFive","os_version":"10.5","timeout":"60"}'
            MATRIX+=',{"platform":"tenseven","runner":["self-hosted","tenseven"],"type":"legacy","port":"<PORTPATH>","vm_ip":"${{ vars.LEGACY_TENSEVEN_IP }}","vm_username":"${{ vars.LEGACY_USERNAME }}","vm_name":"TenSeven","os_version":"10.7","timeout":"60"}'
          fi

          MATRIX+=']}'

          echo "matrix=$MATRIX" >> $GITHUB_OUTPUT
          echo "Generated matrix for trigger: ${{ github.event_name }}"
          echo "$MATRIX" | jq '.'

  build-<PORTNAME>:
    needs: setup-matrix
    name: build-<PORTNAME> (${{ matrix.platform }})
    runs-on: ${{ matrix.runner }}
    strategy:
      matrix: ${{ fromJSON(needs.setup-matrix.outputs.matrix) }}
      fail-fast: false

    steps:
      #
      # MODERN PLATFORM STEPS
      #
      - name: Show macOS version
        if: matrix.type == 'modern'
        run: |
          echo "Running on: ${{ matrix.platform }}"
          echo "Building port: <PORTNAME>"
          echo "Building from branch: ${{ inputs.branch || github.ref_name }}"
          sw_vers

      - name: Checkout repository
        if: matrix.type == 'modern'
        uses: actions/checkout@v4
        with:
          ref: ${{ inputs.branch || github.ref }}

      - name: Setup MacPorts and BlakePorts Environment
        if: matrix.type == 'modern'
        run: ./scripts/installmacports

      - name: Lint portfile
        if: matrix.type == 'modern'
        run: |
          source ./setupenv.bash
          port lint --nitpick ${{ matrix.port }}

      - name: Clean existing installation
        if: matrix.type == 'modern'
        run: |
          source ./setupenv.bash
          if port installed <PORTNAME> | grep -q <PORTNAME>; then
            echo "Removing existing <PORTNAME> installation..."
            sudo port -f uninstall <PORTNAME>
            sudo port clean --dist <PORTNAME>
          else
            echo "No existing <PORTNAME> installation found"
          fi

      - name: Install dependencies
        if: matrix.type == 'modern'
        run: ./scripts/install-deps <PORTNAME>

      - name: Build port
        if: matrix.type == 'modern'
        run: |
          source ./setupenv.bash
          sudo port -v install <PORTNAME>

      - name: Verify installation
        if: matrix.type == 'modern'
        run: |
          source ./setupenv.bash
          port installed <PORTNAME>
          # PORT-SPECIFIC VERIFICATION HERE

      #
      # LEGACY PLATFORM STEPS
      #
      - name: Checkout repository (for tarball)
        if: matrix.type == 'legacy'
        uses: actions/checkout@v4
        with:
          ref: ${{ inputs.branch || github.ref }}

      - name: Verify VM configuration
        if: matrix.type == 'legacy'
        run: |
          if [ -z "${{ matrix.vm_ip }}" ]; then
            echo "Error: VM IP not set for ${{ matrix.platform }}"
            exit 1
          fi
          if [ -z "${{ matrix.vm_username }}" ]; then
            echo "Error: VM username not set for ${{ matrix.platform }}"
            exit 1
          fi
          echo "Will connect to: ${{ matrix.vm_username }}@${{ matrix.vm_ip }}"

      - name: Show macOS version (legacy VM)
        if: matrix.type == 'legacy'
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.vm_ip }}
          username: ${{ matrix.vm_username }}
          key: ${{ secrets.OLDMAC_KEY }}
          script: |
            set -e
            set -o pipefail
            if [ -f ~/.profile ]; then
              source ~/.profile
            fi
            echo "=================================================="
            echo "  Building <PORTNAME> on Mac OS X ${{ matrix.os_version }} (${{ matrix.vm_name }})"
            echo "=================================================="
            sw_vers
            echo ""
            uname -a

      - name: Download repository tarball
        if: matrix.type == 'legacy'
        run: |
          echo "Downloading blakeports repository..."
          BRANCH="${{ inputs.branch || 'main' }}"
          curl -L -o /tmp/blakeports.tar.gz "https://github.com/trodemaster/blakeports/archive/refs/heads/${BRANCH}.tar.gz"
          echo "✅ Tarball downloaded: $(ls -lh /tmp/blakeports.tar.gz)"

      - name: Transfer tarball to legacy VM
        if: matrix.type == 'legacy'
        run: |
          echo "Transferring tarball to ${{ matrix.vm_name }} VM..."
          scp -i /home/runner/.ssh/oldmac \
              -o StrictHostKeyChecking=no \
              -o UserKnownHostsFile=/dev/null \
              -o HostKeyAlgorithms=+ssh-rsa \
              -o PubkeyAcceptedKeyTypes=+ssh-rsa \
              /tmp/blakeports.tar.gz \
              ${{ matrix.vm_username }}@${{ matrix.vm_ip }}:/tmp/
          echo "✅ Tarball transferred"

      - name: Extract repository on legacy VM
        if: matrix.type == 'legacy'
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.vm_ip }}
          username: ${{ matrix.vm_username }}
          key: ${{ secrets.OLDMAC_KEY }}
          script: |
            set -e
            set -o pipefail
            if [ -f ~/.profile ]; then
              source ~/.profile
            fi
            echo "Setting up blakeports directory..."
            mkdir -p /Users/blake/code
            if [ -d /Users/blake/code/blakeports ]; then
              echo "Cleaning existing directory..."
              rm -rf /Users/blake/code/blakeports/*
              rm -rf /Users/blake/code/blakeports/.[!.]*
            else
              mkdir -p /Users/blake/code/blakeports
            fi
            cd /Users/blake/code/blakeports
            echo "Extracting tarball..."
            tar xzf /tmp/blakeports.tar.gz --strip-components=1
            rm /tmp/blakeports.tar.gz
            echo "✅ Repository ready"

      - name: Verify MacPorts and setup environment
        if: matrix.type == 'legacy'
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.vm_ip }}
          username: ${{ matrix.vm_username }}
          key: ${{ secrets.OLDMAC_KEY }}
          script: |
            set -e
            set -o pipefail
            set -x
            if [ -f ~/.profile ]; then
              source ~/.profile
            fi
            if ! command -v port &> /dev/null; then
              echo "❌ ERROR: MacPorts not found"
              exit 1
            fi
            port version
            cd /Users/blake/code/blakeports
            source ./setupenv.bash
            portindex
            echo "✅ MacPorts verified"

      - name: Lint portfile (legacy)
        if: matrix.type == 'legacy'
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.vm_ip }}
          username: ${{ matrix.vm_username }}
          key: ${{ secrets.OLDMAC_KEY }}
          script: |
            set -e
            set -o pipefail
            set -x
            if [ -f ~/.profile ]; then
              source ~/.profile
            fi
            cd /Users/blake/code/blakeports
            source ./setupenv.bash
            LINT_OUTPUT=$(port lint --nitpick ${{ matrix.port }} 2>&1)
            echo "$LINT_OUTPUT"
            if echo "$LINT_OUTPUT" | grep -q "Error:"; then
              echo "❌ Lint failed"
              exit 1
            fi
            echo "✅ Lint passed"

      - name: Clean existing installation (legacy)
        if: matrix.type == 'legacy'
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.vm_ip }}
          username: ${{ matrix.vm_username }}
          key: ${{ secrets.OLDMAC_KEY }}
          script: |
            set -e
            set -o pipefail
            if [ -f ~/.profile ]; then
              source ~/.profile
            fi
            cd /Users/blake/code/blakeports
            source ./setupenv.bash
            sudo port -f uninstall <PORTNAME> || true
            sudo port clean --dist <PORTNAME>
            echo "✅ Clean complete"

      - name: Install dependencies (legacy)
        if: matrix.type == 'legacy'
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.vm_ip }}
          username: ${{ matrix.vm_username }}
          key: ${{ secrets.OLDMAC_KEY }}
          command_timeout: ${{ matrix.timeout }}m
          script: |
            set -e
            set -o pipefail
            set -x
            if [ -f ~/.profile ]; then
              source ~/.profile
            fi
            cd /Users/blake/code/blakeports
            ./scripts/install-deps <PORTNAME>
            echo "✅ Dependencies installed"

      - name: Build port (legacy)
        if: matrix.type == 'legacy'
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.vm_ip }}
          username: ${{ matrix.vm_username }}
          key: ${{ secrets.OLDMAC_KEY }}
          command_timeout: ${{ matrix.timeout }}m
          script: |
            set -e
            set -o pipefail
            set -x
            if [ -f ~/.profile ]; then
              source ~/.profile
            fi
            cd /Users/blake/code/blakeports
            source ./setupenv.bash
            sudo port -v install <PORTNAME>
            echo "✅ Build complete"

      - name: Verify installation (legacy)
        if: matrix.type == 'legacy'
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.vm_ip }}
          username: ${{ matrix.vm_username }}
          key: ${{ secrets.OLDMAC_KEY }}
          script: |
            set -e
            set -o pipefail
            if [ -f ~/.profile ]; then
              source ~/.profile
            fi
            cd /Users/blake/code/blakeports
            source ./setupenv.bash
            port installed <PORTNAME>
            # PORT-SPECIFIC VERIFICATION HERE
            echo "✅ Installation verified"

      - name: Cleanup (legacy)
        if: matrix.type == 'legacy' && always()
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.vm_ip }}
          username: ${{ matrix.vm_username }}
          key: ${{ secrets.OLDMAC_KEY }}
          script: |
            if [ -f ~/.profile ]; then
              source ~/.profile
            fi
            rm -f /tmp/blakeports.tar.gz
            echo "✅ Cleanup complete"
```

### Template Variables

For each port, replace these placeholders:

| Placeholder | Example Value | Description |
|-------------|---------------|-------------|
| `<PORTNAME>` | `netatalk` | Port name (lowercase) |
| `<PORTPATH>` | `net/netatalk` | Category/portname path |
| `PORT-SPECIFIC VERIFICATION` | See port-specific sections above | Custom verification steps |

## Critical Files

### Files to Modify (6 workflows)

1. `.github/workflows/build-libcbor.yml` - Consolidate with build-legacy-libcbor.yml
2. `.github/workflows/build-libfido2.yml` - Consolidate with build-legacy-libfido2.yml
3. `.github/workflows/build-netatalk.yml` - Consolidate with build-legacy-netatalk.yml
4. `.github/workflows/build-bstring.yml` - Consolidate with build-legacy-bstring.yml
5. `.github/workflows/build-previous.yml` - Consolidate with build-legacy-previous.yml
6. `.github/workflows/build-nrsc5.yml` - Add legacy capability (no legacy workflow exists yet)

### Files to Delete (5 legacy workflows)

After successful testing and rollout:

1. `.github/workflows/build-legacy-libcbor.yml`
2. `.github/workflows/build-legacy-libfido2.yml`
3. `.github/workflows/build-legacy-netatalk.yml`
4. `.github/workflows/build-legacy-bstring.yml`
5. `.github/workflows/build-legacy-previous.yml`

### Documentation to Update

- `CLAUDE.md` - Update workflow_dispatch instructions
- `README.md` - Update CI/CD architecture section if needed

## Benefits

1. **Reduced maintenance**: 11 workflow files → 6 workflow files (45% reduction)
2. **Consistent structure**: All ports follow same pattern
3. **Resource efficiency**: Legacy builds only run when manually triggered
4. **Simplified secrets**: Single OLDMAC_KEY instead of per-OS keys
5. **Better visibility**: Single workflow run shows all platforms tested
6. **Easier updates**: Changes to build process only need updating in one place per port

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Legacy builds accidentally trigger on push/PR | Matrix setup job explicitly checks trigger type; extensive testing required |
| SSH key consolidation breaks legacy builds | Test legacy builds before deleting old secrets |
| Large workflow files harder to read | Use clear section comments and consistent structure |
| Matrix generation logic complexity | Thorough testing and clear documentation |
| Breaking existing workflows during migration | Feature branch testing, phased rollout, keep legacy files until stable |

## Success Criteria

- ✅ Push/PR triggers run ONLY modern builds (macOS_15, macOS_26)
- ✅ workflow_dispatch with run_legacy=false runs ONLY modern builds
- ✅ workflow_dispatch with run_legacy=true runs modern + legacy builds
- ✅ All port-specific customizations preserved (variants, verification steps)
- ✅ Legacy builds complete successfully on tenfive and tenseven
- ✅ Total workflow files reduced from 13 to 6-7
- ✅ No regression in build success rates
