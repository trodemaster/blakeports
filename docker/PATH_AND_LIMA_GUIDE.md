# Docker Runners - Path and Lima Setup Guide

## Understanding the Path Problem

Your system has three layers that need to align:

```
macOS (your machine)
  ↓
Lima VM (Linux)  
  ↓
Docker Containers (in Lima)
```

### Current Path Mapping

| Layer | Path | Notes |
|-------|------|-------|
| macOS | `/Users/blake/Developer/blakeports/` | Your actual filesystem |
| Lima VM | Mounted as `/Users/blake/Developer/blakeports/` | Lima auto-mounts macOS folders |
| Docker | Uses Lima mounts | Containers see Linux paths |

## The SSH Key Issue

The error you're seeing means:
- Docker can't find `/Users/blake/code/blakeports/docker/ssh_keys/oldmac`
- This path doesn't exist (notice it's `/code/` not `/Developer/`)

### Solution: Create the SSH Key File

**In your terminal on macOS:**

```bash
cd /Users/blake/Developer/blakeports/docker

# Verify the directory exists
ls -la ssh_keys/

# Create the SSH key file
# Option 1: If you have the key in your terminal
echo "$OLDMAC_KEY" > ssh_keys/oldmac

# Option 2: If you need to get it from GitHub
gh secret view OLDMAC_KEY > ssh_keys/oldmac

# Set correct permissions
chmod 600 ssh_keys/oldmac

# Verify
ls -la ssh_keys/oldmac
# Should show: -rw------- 1 blake staff
```

## Path Resolution in docker-compose.yml

The docker-compose file now uses `${PWD}/ssh_keys/oldmac` which:

1. ✅ **On macOS**: Resolves to `/Users/blake/Developer/blakeports/ssh_keys/oldmac`
2. ✅ **In Lima VM**: Lima mounts it as `/Users/blake/Developer/blakeports/ssh_keys/oldmac` (same path)
3. ✅ **For Docker**: Lima shares this as `/Users/blake/Developer/blakeports/ssh_keys/oldmac`

This works because Lima preserves the full `/Users/blake/...` path.

## Verifying Your Setup

```bash
# Run the diagnostics script
bash docker/diagnose.sh

# This will check:
# ✓ SSH key file exists
# ✓ File permissions correct
# ✓ Docker is installed
# ✓ Lima VM is running
# ✓ .env file exists and has tokens
```

## If You Still Get Mount Errors

### Option 1: Use Relative Paths (Current Default)
Already configured in docker-compose.yml using `${PWD}/ssh_keys/oldmac`

**Pros**: Works across systems  
**Cons**: Requires correct working directory

**Usage**:
```bash
cd /Users/blake/Developer/blakeports/docker
docker compose up -d
```

### Option 2: Use Absolute Paths (If Relative Fails)
Edit `docker-compose.yml` volumes section:

```yaml
volumes:
  - /Users/blake/Developer/blakeports/docker/ssh_keys/oldmac:/home/runner/.ssh/oldmac:ro
```

**Pros**: Always works, no matter where you run the command  
**Cons**: Not portable between machines

### Option 3: Create SSH Key as Directory (Not Recommended)
This would only work if you copy keys into a directory, but our setup expects a single file.

## Lima Mount Paths

Lima auto-mounts your macOS home directory at the same path. To verify:

```bash
# SSH into Lima VM
limactl shell default

# Inside Lima, check the mount
ls -la /Users/blake/Developer/blakeports/docker/ssh_keys/
# Should show: oldmac file
```

## Quick Fixes

### "oldmac file doesn't exist"
```bash
cd /Users/blake/Developer/blakeports/docker
echo "$OLDMAC_KEY" > ssh_keys/oldmac
chmod 600 ssh_keys/oldmac
```

### "Permission denied" on oldmac
```bash
chmod 600 /Users/blake/Developer/blakeports/docker/ssh_keys/oldmac
```

### "Mount path is wrong"
1. Verify you're in the right directory: `pwd`
2. Should be: `/Users/blake/Developer/blakeports/docker`
3. Check SSH key exists: `ls -la ssh_keys/oldmac`

### Docker can't find Lima
```bash
# Start Lima if not running
limactl start default

# Verify Docker socket
ls -la ~/.lima/default/sock/docker.sock
```

## Working Directory Requirements

**Docker must be run from the docker directory:**

```bash
# ✅ Correct
cd /Users/blake/Developer/blakeports/docker
docker compose up -d

# ❌ Wrong - relative paths won't resolve
cd /Users/blake/Developer/blakeports
docker compose -f docker/docker-compose.yml up -d
```

If you want to run from the parent directory, change docker-compose.yml to:
```yaml
volumes:
  - ./docker/ssh_keys/oldmac:/home/runner/.ssh/oldmac:ro
```

## Path Verification Steps

1. **SSH key exists**:
   ```bash
   [ -f ~/Developer/blakeports/docker/ssh_keys/oldmac ] && echo "✅ Exists" || echo "❌ Missing"
   ```

2. **SSH key readable**:
   ```bash
   [ -r ~/Developer/blakeports/docker/ssh_keys/oldmac ] && echo "✅ Readable" || echo "❌ Not readable"
   ```

3. **Docker compose is in right directory**:
   ```bash
   [ -f docker-compose.yml ] && echo "✅ Found" || echo "❌ Not in docker directory"
   ```

4. **Lima VM can see the path**:
   ```bash
   limactl shell default "test -f /Users/blake/Developer/blakeports/docker/ssh_keys/oldmac && echo ✅ || echo ❌"
   ```

## Next Steps After Fix

```bash
# Run diagnostics
bash docker/diagnose.sh

# If all checks pass:
docker compose build
docker compose up -d

# Verify
docker compose ps
```
