# Darkstar Setup Documentation

This document describes the manual setup required for the `darkstar` host to work with the `ghrunner` script using the VMware Fusion REST API.

## Prerequisites

- VMware Fusion 13.0 or later installed on darkstar
- Host system running macOS 11 or later
- Network connectivity between host and darkstar
- SSH access to darkstar (for initial setup)

## VMware Fusion REST API Configuration

### 1. Enable REST API Listener

The VMware Fusion REST API must be manually started on the darkstar host. This is not enabled by default.

**On darkstar, run:**

```bash
# Ensure VMware Fusion is running
open -a VMware\ Fusion

# Start the REST API listener (runs on port 8697 by default)
/Applications/VMware\ Fusion.app/Contents/Library/vmrest &
```

Or to run it in the background permanently:

```bash
# Create a launch agent for automatic startup
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.vmware.vmrest.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vmware.vmrest</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/VMware Fusion.app/Contents/Library/vmrest</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/vmrest.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/vmrest-error.log</string>
</dict>
</plist>
EOF

# Load the launch agent
launchctl load ~/Library/LaunchAgents/com.vmware.vmrest.plist
```

### 2. Create API Credentials

Create a credentials file for REST API authentication:

```bash
# Create the vmrest config directory
mkdir -p ~/.vmrest

# Create a credentials file (simple username:password)
echo "your_username:your_password" > ~/.vmrest/httpd.conf

# Set proper permissions
chmod 600 ~/.vmrest/httpd.conf
```

### 3. Verify REST API is Running

Test the API endpoint from any host with network access to darkstar:

```bash
# Basic connectivity test
curl -k -u username:password https://darkstar.local:8697/api/vmrest/v1

# Or use the host IP instead of .local hostname
curl -k -u username:password https://192.168.1.100:8697/api/vmrest/v1
```

Expected response:
```json
{
  "version": "1.0.0",
  "baseVersion": "1.0"
}
```

### 4. Certificate Configuration (for HTTPS)

The VMware REST API uses HTTPS. On first access, you'll encounter a self-signed certificate warning. This is expected and normal. When using `curl`, add the `-k` (insecure) flag or implement proper certificate handling.

For production use, consider:
- Installing a proper certificate on the darkstar host
- Adding the self-signed cert to your system keychain
- Using certificate pinning in your API client

## Host Configuration

### Set Environment Variables

Configure your host machine to connect to the darkstar REST API. Add these to your `.envrc` file (or environment setup):

```bash
# darkstar REST API credentials
export VMWARE_REST_API_HOST="darkstar.local"     # or IP address
export VMWARE_REST_API_PORT="8697"
export VMWARE_REST_API_USER="your_username"
export VMWARE_REST_API_PASS="your_password"
```

If using `direnv`, remember to run:

```bash
direnv allow
```

### Test Connectivity

From your host machine, verify you can reach the darkstar REST API:

```bash
# Test with curl
curl -k -u $VMWARE_REST_API_USER:$VMWARE_REST_API_PASS \
  https://$VMWARE_REST_API_HOST:$VMWARE_REST_API_PORT/api/vmrest/v1

# Or use the ghrunner script to inspect VMs
./scripts/ghrunner -inspect-legacy-vms
```

## Firewall Configuration

If darkstar has a firewall enabled, ensure these ports are accessible:

| Port | Protocol | Purpose |
|------|----------|---------|
| 8697 | TCP | VMware REST API |
| 22 | TCP | SSH (for manual management) |

### Network Requirements

- darkstar must have a stable IP address or resolvable hostname (.local works with mDNS)
- No NAT - direct network connectivity is required for the REST API
- DNS or mDNS must be configured for hostname resolution

## VM Organization on Darkstar

The ghrunner script expects VMs to follow this naming pattern:

```
runner-{name}-base       # Base/template VMs (not typically started)
runner-{name}            # Working VMs created from base images
```

Example VM names:
- `runner-tenfive-base` (base image for 10.5)
- `runner-tenfive` (working 10.5 VM)
- `runner-tenseven-base` (base image for 10.7)
- `runner-tenseven` (working 10.7 VM)

### VM Disk Location

All VM files should be stored in a consistent location on darkstar:

```
/Volumes/JonesFarm/actions-runners/
├── runner-tenfive-base/
├── runner-tenfive/
├── runner-tenseven-base/
└── runner-tenseven/
```

This path is configured in `ghrunner` as `VMWARE_BASE_DIR`.

## API Endpoints Reference

For detailed information about available endpoints, see `VMREST_API.md`.

## Troubleshooting

### REST API Not Responding

1. Verify it's running:
   ```bash
   ps aux | grep vmrest
   ```

2. Check for processes on port 8697:
   ```bash
   lsof -i :8697
   ```

3. Review logs:
   ```bash
   tail -f /var/log/vmrest*.log
   ```

### Certificate Errors

If you get certificate validation errors:

```bash
# For curl, use -k to skip verification (development only)
curl -k -u user:pass https://darkstar:8697/api/vmrest/v1

# In scripts, the curl calls should already use -k
```

### Connection Refused

1. Ensure darkstar is reachable:
   ```bash
   ping darkstar.local
   ```

2. Verify the REST API port:
   ```bash
   nc -zv darkstar.local 8697
   ```

3. Check your credentials are correct in `.envrc`

### VM Operations Fail

1. Ensure VMs exist with the correct naming:
   ```bash
   # On darkstar, list VMs
   vmrun list
   ```

2. Verify file paths match `VMWARE_BASE_DIR`

3. Check darkstar has sufficient resources (disk space, memory)

## Security Notes

- **Credentials**: Keep `VMWARE_REST_API_PASS` secure - don't commit to version control
- **Network**: Only use over trusted networks or VPN
- **HTTPS Certificate**: Use proper certificates in production environments
- **Firewall**: Restrict API access to authorized hosts

## SSH Alternative

For tasks requiring direct VM access, SSH is also configured:

```bash
# SSH into darkstar
ssh blake@darkstar.local

# Then use vmrun or other tools directly
/Applications/VMware\ Fusion.app/Contents/Public/vmrun list
```

## Additional Resources

- VMware Fusion REST API Documentation: See `VMREST_API.md`
- VMware Fusion User Guide: https://docs.vmware.com/en/vmware-fusion/
- API Explorer: https://darkstar.local:8697/ (requires mDNS or IP address)

