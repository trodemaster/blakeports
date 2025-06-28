# blakeports
Personal MacPorts repository with custom ports and automated CI/CD workflows.

## Scripts

- `scripts/installmacports` - Installs MacPorts and configures BlakePorts as the default source
- `scripts/boop` - Creates an empty commit to trigger GitHub Actions workflows

## Ports

- `audio/nrsc5` - Software-defined radio for NRSC-5 (HD Radio)
- `devel/libcbor` - CBOR protocol implementation library  
- `security/libfido2` - FIDO2 authentication library
- `net/netatalk4` - Apple Filing Protocol (AFP) server

## GitHub Actions Workflows

### Manual Workflow Triggering

Use the GitHub CLI to manually trigger workflows for debugging without making commits:

```bash
# Trigger individual port workflows
gh workflow run "Build netatalk4"
gh workflow run "Build libfido2" 
gh workflow run "Build libcbor"
gh workflow run "Build nrsc5"

# Trigger the MacPorts installation workflow
gh workflow run "Install MacPorts"
```

### Monitor Workflow Runs

```bash
# List recent workflow runs
gh run list --workflow=build-netatalk4.yml

# View details of the most recent run
gh run view

# Watch a running workflow in real-time
gh run watch

# List all available workflows
gh workflow list

# View workflow logs
gh run view --log
```

### Benefits of Manual Triggering

- **No commits needed** - Perfect for debugging without polluting git history
- **Quick iteration** - Test changes rapidly during development  
- **Selective testing** - Run only the specific port workflow you're debugging
- **Real-time feedback** - Monitor build progress and logs immediately

## Workflow Structure

All workflows use composite actions for consistency:
- `.github/actions/setup-blakeports/` - Reusable setup for checkout, configuration, and port indexing
- Individual port workflows automatically trigger on changes to their respective directories
- Clean builds with automatic uninstall/cleanup of existing port installations

## Development

Generate checksums for new ports:
```bash
openssl dgst -rmd160 rrdtool-1.2.23.tar.gz
openssl dgst -sha256 rrdtool-1.2.23.tar.gz
```