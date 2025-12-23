# Docker Runners Configuration Refactoring

## Summary of Changes

We've refactored the Docker runner configuration to minimize `.env` variables and use sensible defaults throughout.

### Before
The old `example.env` had ~50 lines of configuration with variables for almost everything that could vary, creating a large surface area for misconfiguration.

### After
The new `.env` file only contains **one required value per runner: the registration token**.

```
RUNNER_TOKEN_TENFIVE=<generated-token>
RUNNER_TOKEN_TENSEVEN=<generated-token>
```

### Defaults Applied

All configuration is now hardcoded in `docker-compose.yml` and follows your naming conventions:

**GitHub Configuration** (global):
- `GITHUB_OWNER=trodemaster`
- `GITHUB_REPO=blakeports`

**Runner Configuration** (per runner):
| Runner | Container | Hostname | SSH Target | VM FQDN | User | Labels |
|--------|-----------|----------|------------|---------|------|--------|
| tenfive | tenfive-runner | tenfive-runner | tenfive | tenfive-runner.local | admin | ssh-legacy-capable,legacy-macos,tenfive,10-5 |
| tenseven | tenseven-runner | tenseven-runner | tenseven | tenseven-runner.local | admin | ssh-legacy-capable,legacy-macos,tenseven,10-7 |

**SSH Configuration** (universal):
- SSH key: `oldmac` (mounted read-only from `./ssh_keys/oldmac`)
- SSH algorithms: Configured for legacy macOS 10.5-10.10 compatibility
- Workdir: `_work`

### Benefits

1. **Simpler Setup**: Only generate tokens, no configuration files to edit
2. **Less Error-Prone**: Fewer variables = fewer opportunities for misconfiguration
3. **Consistent Naming**: Follows established naming conventions automatically
4. **Maintainability**: Changes to defaults are centralized in docker-compose.yml
5. **Minimal .env**: Easy to review and understand what's actually dynamic

### Usage

```bash
# Generate tokens and create minimal .env
bash docker/setup-runners.sh

# Build and start
docker compose build
docker compose up -d
```

### To Add New Runners

Add a new service to `docker-compose.yml` following the pattern:
- Service name: `<vm-name>-runner` (e.g., `tensix-runner`)
- Container/hostname: `<vm-name>-runner`
- VM_HOSTNAME: `<vm-name>` (short form for SSH config)
- VM_HOSTNAME_FQDN: `<vm-name>-runner.local` (actual network hostname)
- Custom labels: Include version info (e.g., `10-6`)
- Volume: `runner-work-<vm-name>`

Then add corresponding `RUNNER_TOKEN_<VM>` to `.env` via setup script.

### Files Modified

- `docker-compose.yml` - Removed all template variables, hardcoded defaults, removed commented-out runners
- `entrypoint.sh` - Changed to use `VM_HOSTNAME_FQDN` instead of `VM_IP`
- `setup-runners.sh` - Simplified to only generate tokens and create `.env`
- `.env` - Now minimal (only tokens)

### Backwards Compatibility

This is a breaking change from the old `example.env` format. Anyone upgrading should:
1. Delete old `.env` (it's gitignored anyway)
2. Run `bash docker/setup-runners.sh` to generate new minimal `.env`
3. Update any custom VM hostnames in `docker-compose.yml` if different from `.local` convention
