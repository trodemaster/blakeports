# Legacy macOS VM Setup Guide

This guide explains how to add new legacy macOS VMs to the testing workflows.

## Current Configuration

### TenSeven (Mac OS X 10.7)
- **Variables**: `TENSEVEN_IP`, `TENSEVEN_USERNAME`
- **Secret**: `TENSEVEN_KEY`
- **Status**: ✅ Configured and working

### TenFive (Mac OS X 10.5)  
- **Variables**: `TENFIVE_IP`, `TENFIVE_USERNAME`
- **Secret**: `TENFIVE_KEY`
- **Status**: ⚠️ Needs configuration

## Adding a New VM (e.g., TenFive)

### Step 1: Set Up GitHub Repository Variables

Go to: **Settings** → **Secrets and variables** → **Actions** → **Variables**

Add these variables:
- `TENFIVE_IP` = `192.168.x.x` (the VM's IP address)
- `TENFIVE_USERNAME` = `blake` (or your SSH username)

### Step 2: Set Up GitHub Repository Secret

Go to: **Settings** → **Secrets and variables** → **Actions** → **Secrets**

Add this secret:
- `TENFIVE_KEY` = (paste the SSH private key content)

### Step 3: Set Up SSH Key on Runner

The self-hosted runner needs the SSH key at `/home/runner/.ssh/oldmac`

This is already configured for existing VMs. The same key should work for all legacy VMs.

### Step 4: Prepare the VM

On the target VM (TenFive), ensure:

1. **MacPorts is installed** and in PATH
2. **SSH is enabled** and accepts the runner's key
3. **User has sudo access** (required for port install)
4. **Profile is configured**: `~/.profile` should source MacPorts paths
5. **Directory structure**: `/Users/blake/code/` should exist or be creatable

Example `~/.profile`:
```bash
# MacPorts
export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
```

### Step 5: Test SSH Connection

From the runner host, test the connection:
```bash
ssh -i /home/runner/.ssh/oldmac \
    -o StrictHostKeyChecking=no \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedKeyTypes=+ssh-rsa \
    blake@192.168.x.x
```

### Step 6: Replace the Workflow File

Replace the existing single-VM workflow with the multi-VM version:
```bash
cd /Users/blake/code/blakeports
mv .github/workflows/build-legacy-bstring-multi.yml .github/workflows/build-legacy-bstring.yml
git add .github/workflows/build-legacy-bstring.yml
git commit -m "build-legacy-bstring: add multi-VM support for TenFive and TenSeven"
git push
```

## Workflow Features

### Automatic Triggers
- On push to `textproc/bstring/**` → runs on **all** VMs
- On PR to `textproc/bstring/**` → runs on **all** VMs

### Manual Dispatch Options
- **all** (default) → runs on both TenFive and TenSeven
- **tenfive** → runs only on TenFive
- **tenseven** → runs only on TenSeven

### Parallel Execution
Both VMs run in parallel jobs, so total time = slowest VM (not sum of times)

## VM Naming Convention

| VM Name  | OS Version      | Variable Prefix |
|----------|-----------------|-----------------|
| TenFive  | Mac OS X 10.5   | TENFIVE_        |
| TenSix   | Mac OS X 10.6   | TENSIX_         |
| TenSeven | Mac OS X 10.7   | TENSEVEN_       |
| SnowLeopard | Mac OS X 10.6 | SNOWLEOPARD_  |
| Lion     | Mac OS X 10.7   | LION_           |

## Troubleshooting

### "VM_IP not set" Error
→ Check that repository variables are configured correctly

### "Permission denied (publickey)" Error  
→ Check that TENFIVE_KEY secret contains the correct private key

### "MacPorts not found" Error
→ Ensure MacPorts is installed on the VM and ~/.profile sources it

### "sudo: sorry, you must have a tty to run sudo"
→ On the VM, run: `sudo visudo` and add: `Defaults:blake !requiretty`

### SSH Connection Issues on Old Macs
The workflow uses these SSH options for compatibility:
- `HostKeyAlgorithms=+ssh-rsa`
- `PubkeyAcceptedKeyTypes=+ssh-rsa`

These are required for older SSH versions on Mac OS X 10.5-10.7.

## Example: Testing TenFive Only

```bash
gh workflow run build-legacy-bstring.yml -f os_selection=tenfive
```

## Example: Testing Both VMs

```bash
gh workflow run build-legacy-bstring.yml -f os_selection=all
```

Or just push to textproc/bstring/ and both will run automatically!

