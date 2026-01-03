# VMware Fusion REST API Reference

**API Version**: 1.3.1  
**Base Path**: `/api`  
**Schemes**: HTTP, HTTPS  
**Authentication**: HTTP Basic Auth  
**Server**: darkstar.jibb.tv:8697

## Overview

The VMware Fusion REST API provides programmatic access to manage virtual machines and network configurations on the local system. This is the official reference for all available endpoints and their usage.

**Web UI**: https://darkstar.jibb.tv:8697/

## Authentication

All API endpoints require HTTP Basic Authentication.

### Method 1: Using curl with -u flag
```bash
curl -k -u 'username:password' https://darkstar.jibb.tv:8697/api/vms
```

### Method 2: Using Authorization header
```bash
# Create base64-encoded credentials
CREDS=$(echo -n 'username:password' | base64)

# Use in header
curl -k -H "Authorization: Basic $CREDS" https://darkstar.jibb.tv:8697/api/vms
```

### Security Notes
- Always use HTTPS (default port 8697)
- Accept self-signed certificates with `-k` flag in curl
- Store credentials in environment variables, not in scripts
- Restrict firewall access to trusted hosts only

---

## VM Management Endpoints

### GET /vms
**Summary**: Returns a list of VM IDs and paths for all VMs

**Parameters**: None

**Example Request**:
```bash
curl -k -u 'vmware:password' https://darkstar.jibb.tv:8697/api/vms
```

**Example Response**:
```json
[
  {
    "id": "runner-tenfive",
    "paths": {
      "vmx": "/Volumes/JonesFarm/actions-runners/runner-tenfive.vmwarevm/runner-tenfive.vmx"
    }
  },
  {
    "id": "runner-tenseven",
    "paths": {
      "vmx": "/Volumes/JonesFarm/actions-runners/runner-tenseven.vmwarevm/runner-tenseven.vmx"
    }
  }
]
```

**Response Codes**:
- `200`: All VMs' ID and path
- `401`: Authentication failed
- `403`: Permission denied
- `500`: Server error

---

### POST /vms
**Summary**: Creates a copy (clone) of a VM

**Parameters**:
- `params` (body, required): VMCloneParameter object
- `vmPassword` (query, optional): VM password (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  -X POST \
  -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
  -d '{
    "params": {
      "name": "new-vm-clone",
      "parentId": "runner-tenfive"
    }
  }' \
  https://darkstar.jibb.tv:8697/api/vms
```

**Response Codes**:
- `201`: VM created successfully
- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Permission denied
- `404`: Source VM not found
- `406`: Content type not supported
- `409`: Resource state conflict
- `500`: Server error

---

### GET /vms/{id}
**Summary**: Returns the VM setting information of a specific VM

**Parameters**:
- `id` (path, required): ID of VM (string)
- `vmPassword` (query, optional): VM password (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive
```

**Example Response**:
```json
{
  "id": "runner-tenfive",
  "paths": {
    "vmx": "/Volumes/JonesFarm/actions-runners/runner-tenfive.vmwarevm/runner-tenfive.vmx"
  },
  "name": "runner-tenfive",
  "cpu": 2,
  "memory": 4096,
  "disks": [
    {
      "controller": 0,
      "unit": 0,
      "capabilities": ["discard"]
    }
  ],
  "nics": [
    {
      "type": "nat",
      "mac": "00:0c:29:12:34:56"
    }
  ],
  "power": "off"
}
```

**Response Codes**:
- `200`: VM information
- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `406`: Content type not supported
- `500`: Server error

---

### PUT /vms/{id}
**Summary**: Updates the VM settings

**Parameters**:
- `id` (path, required): ID of VM (string)
- `params` (body, required): VMInformation object with updated settings
- `vmPassword` (query, optional): VM password (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  -X PUT \
  -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
  -d '{
    "cpu": 4,
    "memory": 8192
  }' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive
```

**Response Codes**:
- `200`: VM updated successfully
- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `406`: Content type not supported
- `409`: VM is running (cannot update)
- `500`: Server error

---

### DELETE /vms/{id}
**Summary**: Deletes a VM

**Parameters**:
- `id` (path, required): ID of VM (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  -X DELETE \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive
```

**Response Codes**:
- `204`: VM deleted successfully
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `409`: VM is still running
- `500`: Server error

---

## VM Power Management

### GET /vms/{id}/power
**Summary**: Gets the power state of a VM

**Parameters**:
- `id` (path, required): ID of VM (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/power
```

**Example Response**:
```json
{
  "power": "off"
}
```

Possible values: `on`, `off`, `paused`, `suspended`

**Response Codes**:
- `200`: Current power state
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `500`: Server error

---

### PUT /vms/{id}/power
**Summary**: Sets the power state of a VM

**Parameters**:
- `id` (path, required): ID of VM (string, can be UUID or VM name)
- `operation` (body, required): Power operation as a **raw string** (not JSON object)
  - Valid values: `on`, `off`, `shutdown`, `suspend`, `pause`, `unpause`

**IMPORTANT**: The body must be sent as a plain string, NOT as a JSON object or JSON-encoded string.

**Example Requests**:

**Start VM**:
```bash
curl -k -u 'vmware:password' \
  -X PUT \
  -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
  -d 'on' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/power
```

**Stop VM**:
```bash
curl -k -u 'vmware:password' \
  -X PUT \
  -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
  -d 'off' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/power
```

**Graceful Shutdown**:
```bash
curl -k -u 'vmware:password' \
  -X PUT \
  -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
  -d 'shutdown' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/power
```

**Suspend VM**:
```bash
curl -k -u 'vmware:password' \
  -X PUT \
  -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
  -d 'suspend' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/power
```

**Pause VM**:
```bash
curl -k -u 'vmware:password' \
  -X PUT \
  -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
  -d 'pause' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/power
```

**Unpause VM**:
```bash
curl -k -u 'vmware:password' \
  -X PUT \
  -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
  -d 'unpause' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/power
```

**Example Response (successful start)**:
```json
{
  "power_state": "poweringOn"
}
```

or when already running:
```json
{
  "power_state": "poweredOn"
}
```

**Common Mistakes**:
- ❌ DON'T use: `{"power": "on"}` (JSON object)
- ❌ DON'T use: `"on"` (JSON-encoded string)
- ❌ DON'T use: `{"operation": "on"}` (JSON object)
- ✅ DO use: `on` (raw string)

**Response Codes**:
- `200`: Power state set successfully
- `400`: Invalid power state
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `406`: Content type not supported
- `409`: Invalid state transition
- `500`: Server error

---

## VM Network Information

### GET /vms/{id}/ip
**Summary**: Gets the IP address(es) of a VM

**Parameters**:
- `id` (path, required): ID of VM (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/ip
```

**Example Response**:
```json
{
  "ips": ["192.168.1.100", "fe80::1"]
}
```

**Response Codes**:
- `200`: IP address information
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `500`: Server error

---

### GET /vms/{id}/nicips
**Summary**: Gets IP addresses for each NIC on a VM

**Parameters**:
- `id` (path, required): ID of VM (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/nicips
```

**Example Response**:
```json
[
  {
    "index": 0,
    "ips": ["192.168.1.100", "fe80::1"]
  }
]
```

**Response Codes**:
- `200`: NIC IP information
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `500`: Server error

---

## VM Network Adapters

### GET /vms/{id}/nic
**Summary**: Gets all network adapters on a VM

**Parameters**:
- `id` (path, required): ID of VM (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/nic
```

**Example Response**:
```json
[
  {
    "index": 0,
    "startConnected": true,
    "allowGuestControl": true,
    "type": "nat",
    "mac": "00:0c:29:12:34:56"
  }
]
```

**Response Codes**:
- `200`: Network adapter information
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `500`: Server error

---

### GET /vms/{id}/nic/{index}
**Summary**: Gets a specific network adapter on a VM

**Parameters**:
- `id` (path, required): ID of VM (string)
- `index` (path, required): NIC index (integer, typically 0)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/nic/0
```

**Response Codes**:
- `200`: Network adapter information
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM or NIC not found
- `500`: Server error

---

### PUT /vms/{id}/nic/{index}
**Summary**: Updates a network adapter on a VM

**Parameters**:
- `id` (path, required): ID of VM (string)
- `index` (path, required): NIC index (integer)
- `nic_config` (body, required): Network adapter configuration object

**Response Codes**:
- `200`: Network adapter updated
- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM or NIC not found
- `406`: Content type not supported
- `409`: VM is running
- `500`: Server error

---

### DELETE /vms/{id}/nic/{index}
**Summary**: Removes a network adapter from a VM

**Parameters**:
- `id` (path, required): ID of VM (string)
- `index` (path, required): NIC index (integer)

**Response Codes**:
- `204`: Network adapter removed
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM or NIC not found
- `409`: VM is running
- `500`: Server error

---

## VM Shared Folders

### GET /vms/{id}/sharedfolders
**Summary**: Gets all shared folders for a VM

**Parameters**:
- `id` (path, required): ID of VM (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vms/runner-tenfive/sharedfolders
```

**Response Codes**:
- `200`: Shared folders list
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `500`: Server error

---

### POST /vms/{id}/sharedfolders
**Summary**: Adds a shared folder to a VM

**Parameters**:
- `id` (path, required): ID of VM (string)
- `folder_config` (body, required): Shared folder configuration

**Response Codes**:
- `201`: Shared folder created
- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM not found
- `406`: Content type not supported
- `409`: Folder already exists
- `500`: Server error

---

### GET /vms/{id}/sharedfolders/{folder_id}
**Summary**: Gets a specific shared folder for a VM

**Parameters**:
- `id` (path, required): ID of VM (string)
- `folder_id` (path, required): Shared folder ID (string)

**Response Codes**:
- `200`: Shared folder information
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM or folder not found
- `500`: Server error

---

### PUT /vms/{id}/sharedfolders/{folder_id}
**Summary**: Updates a shared folder configuration

**Parameters**:
- `id` (path, required): ID of VM (string)
- `folder_id` (path, required): Shared folder ID (string)
- `folder_config` (body, required): Updated shared folder configuration

**Response Codes**:
- `200`: Shared folder updated
- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM or folder not found
- `406`: Content type not supported
- `500`: Server error

---

### DELETE /vms/{id}/sharedfolders/{folder_id}
**Summary**: Removes a shared folder from a VM

**Parameters**:
- `id` (path, required): ID of VM (string)
- `folder_id` (path, required): Shared folder ID (string)

**Response Codes**:
- `204`: Shared folder removed
- `401`: Authentication failed
- `403`: Permission denied
- `404`: VM or folder not found
- `500`: Server error

---

## Host Networks Management

### GET /vmnets
**Summary**: Lists all virtual networks on the host

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vmnets
```

**Example Response**:
```json
[
  "vmnet0",
  "vmnet1",
  "vmnet8"
]
```

**Response Codes**:
- `200`: List of virtual networks
- `401`: Authentication failed
- `403`: Permission denied
- `500`: Server error

---

### GET /vmnet/{vmnet}
**Summary**: Gets information about a specific virtual network

**Parameters**:
- `vmnet` (path, required): Virtual network name (e.g., "vmnet8")

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vmnet/vmnet8
```

**Response Codes**:
- `200`: Virtual network information
- `401`: Authentication failed
- `403`: Permission denied
- `404`: Virtual network not found
- `500`: Server error

---

### GET /vmnet/{vmnet}/mactoip
**Summary**: Gets all MAC-to-IP mappings for a virtual network

**Parameters**:
- `vmnet` (path, required): Virtual network name (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vmnet/vmnet8/mactoip
```

**Response Codes**:
- `200`: MAC-to-IP mappings
- `401`: Authentication failed
- `403`: Permission denied
- `404`: Virtual network not found
- `500`: Server error

---

### GET /vmnet/{vmnet}/mactoip/{mac}
**Summary**: Gets the IP address for a specific MAC address

**Parameters**:
- `vmnet` (path, required): Virtual network name (string)
- `mac` (path, required): MAC address (string, e.g., "00:0c:29:12:34:56")

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vmnet/vmnet8/mactoip/00:0c:29:12:34:56
```

**Response Codes**:
- `200`: IP address for MAC
- `401`: Authentication failed
- `403`: Permission denied
- `404`: MAC address not found
- `500`: Server error

---

### GET /vmnet/{vmnet}/portforward
**Summary**: Gets all port forwarding rules for a virtual network

**Parameters**:
- `vmnet` (path, required): Virtual network name (string)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vmnet/vmnet8/portforward
```

**Response Codes**:
- `200`: Port forwarding rules
- `401`: Authentication failed
- `403`: Permission denied
- `404`: Virtual network not found
- `500`: Server error

---

### GET /vmnet/{vmnet}/portforward/{protocol}/{port}
**Summary**: Gets a specific port forwarding rule

**Parameters**:
- `vmnet` (path, required): Virtual network name (string)
- `protocol` (path, required): Protocol ("tcp" or "udp")
- `port` (path, required): Port number (integer)

**Example Request**:
```bash
curl -k -u 'vmware:password' \
  https://darkstar.jibb.tv:8697/api/vmnet/vmnet8/portforward/tcp/8080
```

**Response Codes**:
- `200`: Port forwarding rule
- `401`: Authentication failed
- `403`: Permission denied
- `404`: Rule not found
- `500`: Server error

---

### POST /vmnet/{vmnet}/portforward
**Summary**: Creates a port forwarding rule

**Parameters**:
- `vmnet` (path, required): Virtual network name (string)
- `rule` (body, required): Port forwarding rule configuration

**Response Codes**:
- `201`: Rule created
- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Permission denied
- `404`: Virtual network not found
- `406`: Content type not supported
- `409`: Rule already exists
- `500`: Server error

---

### PUT /vmnet/{vmnet}/portforward/{protocol}/{port}
**Summary**: Updates a port forwarding rule

**Parameters**:
- `vmnet` (path, required): Virtual network name (string)
- `protocol` (path, required): Protocol ("tcp" or "udp")
- `port` (path, required): Port number (integer)
- `rule` (body, required): Updated rule configuration

**Response Codes**:
- `200`: Rule updated
- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Permission denied
- `404`: Rule not found
- `406`: Content type not supported
- `500`: Server error

---

### DELETE /vmnet/{vmnet}/portforward/{protocol}/{port}
**Summary**: Deletes a port forwarding rule

**Parameters**:
- `vmnet` (path, required): Virtual network name (string)
- `protocol` (path, required): Protocol ("tcp" or "udp")
- `port` (path, required): Port number (integer)

**Response Codes**:
- `204`: Rule deleted
- `401`: Authentication failed
- `403`: Permission denied
- `404`: Rule not found
- `500`: Server error

---

## VM Registration

### POST /vms/registration
**Summary**: Registers a VM with the VMware hypervisor

**Parameters**:
- `vm_registration` (body, required): VM registration parameters

**Response Codes**:
- `201`: VM registered
- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Permission denied
- `406`: Content type not supported
- `409`: VM already registered
- `500`: Server error

---

## Common HTTP Status Codes

- **200 OK**: Request succeeded, response contains data
- **201 Created**: Resource created successfully
- **204 No Content**: Request succeeded, no response body
- **400 Bad Request**: Invalid parameters or malformed request
- **401 Unauthorized**: Authentication failed (wrong credentials)
- **403 Forbidden**: Authenticated but not authorized
- **404 Not Found**: Resource does not exist
- **406 Not Acceptable**: Content type not supported
- **409 Conflict**: Resource state conflict or resource already exists
- **500 Internal Server Error**: Server error

---

## Error Response Format

All error responses follow this format:

```json
{
  "error": "Error message describing what went wrong",
  "error_code": "error_type"
}
```

---

## Best Practices

1. **Always use HTTPS** - The REST API requires HTTPS when accessed remotely
2. **Accept self-signed certificates** - Use `-k` flag with curl
3. **Secure credentials** - Never commit passwords to version control
4. **Use environment variables** - Store API credentials in environment variables
5. **Handle errors gracefully** - Always check HTTP status codes
6. **Rate limiting** - The API does not appear to have rate limiting, but use reasonable delays
7. **Timeouts** - Set reasonable timeouts on API calls
8. **Verify SSL** - In production, properly validate SSL certificates

---

## Integration Examples

### Bash Function to List All VMs

```bash
list_vms() {
    local host="${VMWARE_REST_API_HOST:-darkstar.jibb.tv}"
    local port="${VMWARE_REST_API_PORT:-8697}"
    local user="${VMWARE_REST_API_USER:-vmware}"
    local pass="${VMWARE_REST_API_PASS}"
    
    curl -s -k -u "$user:$pass" \
        "https://$host:$port/api/vms" | jq .
}
```

### Bash Function to Get VM Power State

```bash
get_vm_power() {
    local vm_id=$1
    local host="${VMWARE_REST_API_HOST:-darkstar.jibb.tv}"
    local port="${VMWARE_REST_API_PORT:-8697}"
    local user="${VMWARE_REST_API_USER:-vmware}"
    local pass="${VMWARE_REST_API_PASS}"
    
    curl -s -k -u "$user:$pass" \
        "https://$host:$port/api/vms/$vm_id/power" | jq '.power'
}
```

### Bash Function to Start a VM

```bash
start_vm() {
    local vm_id=$1
    local host="${VMWARE_REST_API_HOST:-darkstar.jibb.tv}"
    local port="${VMWARE_REST_API_PORT:-8697}"
    local user="${VMWARE_REST_API_USER:-vmware}"
    local pass="${VMWARE_REST_API_PASS}"
    
    curl -s -k -u "$user:$pass" \
        -X PUT \
        -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
        -d 'on' \
        "https://$host:$port/api/vms/$vm_id/power"
}
```

### Bash Function to Stop a VM

```bash
stop_vm() {
    local vm_id=$1
    local host="${VMWARE_REST_API_HOST:-darkstar.jibb.tv}"
    local port="${VMWARE_REST_API_PORT:-8697}"
    local user="${VMWARE_REST_API_USER:-vmware}"
    local pass="${VMWARE_REST_API_PASS}"
    
    curl -s -k -u "$user:$pass" \
        -X PUT \
        -H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
        -d 'off' \
        "https://$host:$port/api/vms/$vm_id/power"
}
```

---

## References

- **Official VMware Fusion REST API Documentation**: https://techdocs.broadcom.com/us/en/vmware-cis/desktop-hypervisors/fusion-pro/13-0/using-vmware-fusion/guide-and-help-using-the-vmware-fusion-rest-api.html
- **Enabling Remote REST API Access**: https://williamlam.com/2017/09/how-to-enable-remote-rest-api-access-for-vmware-fusion-10.html
- **API Explorer**: https://darkstar.jibb.tv:8697/

