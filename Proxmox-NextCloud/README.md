# NextCloud on Proxmox - Automated Deployment

Automated deployment of NextCloud and Collabora Office on Proxmox LXC containers using Ansible.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
- [Playbook Structure](#playbook-structure)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

## Overview

This project provides a complete, production-ready automation for deploying NextCloud with integrated Collabora Office on Proxmox VE. The deployment is split into modular playbooks that handle different aspects of the setup:

1. **API User Setup** (`setup_proxmox_api.yaml`) - Creates a dedicated Proxmox API user with minimal required permissions
2. **NextCloud Deployment** (`deploy_nextcloud.yaml`) - Deploys and configures NextCloud and Collabora containers
3. **Wrapper Script** (`Deploy.sh`) - Orchestrates the entire process with helpful prompts and validation

## Features

- **Fully Automated**: End-to-end deployment with minimal manual intervention
- **Modular Design**: Separate playbooks for API setup and deployment
- **Security-Focused**: 
  - Minimal privilege API user creation
  - Secure credential handling
  - SSH key-based authentication
  - Automatic credential cleanup
- **Interactive**: Guided prompts for all configuration
- **Validated**: Comprehensive pre-flight checks before deployment
- **Well-Documented**: Extensive inline comments explaining each step
- **Production-Ready**: Follows Ansible and security best practices

## Prerequisites

### Required Software

- **Ansible** >= 2.9
  ```bash
  # Debian/Ubuntu
  sudo apt install ansible
  
  # macOS
  brew install ansible
  
  # pip
  pip install ansible
  ```

- **SSH Client**
  ```bash
  # Usually pre-installed, verify with:
  ssh -V
  ```

### Proxmox Requirements

- Proxmox VE 7.0 or later
- Root SSH access to Proxmox host
- LXC template downloaded (e.g., Debian 12)
- Available storage pool (LVM-Thin recommended)
- Network bridge configured (typically `vmbr0`)

### Network Requirements

- Connectivity from Ansible control node to Proxmox host
- Proxmox API accessible on port 8006
- DNS resolution or /etc/hosts entries for NextCloud/Collabora domains (if using domain names)

## Quick Start

### Option 1: Using the Wrapper Script (Recommended)

The easiest way to deploy is using the wrapper script which handles everything:

```bash
# Clone or download this repository
cd /path/to/nextcloud-proxmox

# Run the deployment script
./Deploy.sh
```

The script will:
1. Check prerequisites (Ansible, SSH, collections)
2. Generate SSH keys if needed
3. Ask if you need to create a Proxmox API user
4. Run the appropriate playbooks
5. Offer to clean up sensitive files

### Option 2: Manual Step-by-Step

If you prefer manual control:

```bash
# 1. Install required Ansible collections
ansible-galaxy collection install -r requirements.yaml

# 2. Generate SSH keys for container access
mkdir -p ssh_keys
ssh-keygen -t ed25519 -f ssh_keys/id_ed25519 -N ""

# 3. (Optional) Create Proxmox API user
ansible-playbook setup_proxmox_api.yaml

# 4. Deploy NextCloud and Collabora
ansible-playbook deploy_nextcloud.yaml

# 5. (Optional) Clean up saved credentials
shred -u .proxmox_credentials.yaml
```

## Detailed Usage

### Playbook 1: API User Setup

**File**: `setup_proxmox_api.yaml`

**Purpose**: Creates a dedicated Proxmox API user with minimal required permissions.

**When to use**:
- First-time setup
- You don't have existing Proxmox API credentials
- You want a dedicated user for Ansible automation

**What it does**:
1. Connects to Proxmox via SSH
2. Creates a custom role with specific permissions (defined in `proxmox_permissions.yaml`)
3. Creates an API user (default: `ansible@pve`)
4. Generates an API token
5. Saves credentials to `.proxmox_credentials.yaml`

**Usage**:
```bash
ansible-playbook setup_proxmox_api.yaml
```

**Prompts**:
- Proxmox SSH connection details
- API user configuration
- Authentication method (password or SSH key)

**Output**:
- API Token ID and Secret (displayed on screen)
- `.proxmox_credentials.yaml` (saved locally for next step)

### Playbook 2: NextCloud Deployment

**File**: `deploy_nextcloud.yaml`

**Purpose**: Deploys and configures NextCloud and Collabora Office containers.

**When to use**:
- After creating API user (or if you already have credentials)
- Every time you want to deploy a new NextCloud instance

**What it does**:
1. Validates prerequisites (API access, storage, templates, SSH keys)
2. Creates NextCloud LXC container
3. Creates Collabora LXC container
4. Configures NextCloud (Apache, PHP, MariaDB, NextCloud)
5. Configures Collabora (Docker, Collabora Online)

**Usage**:
```bash
ansible-playbook deploy_nextcloud.yaml
```

**Prompts**:
- Proxmox connection (host, node, API credentials)
- Storage configuration (pool, template)
- Container resources (CPU, RAM, disk)
- Network configuration (bridge, IPs)
- Credentials (container root, database, NextCloud admin)
- Domains (NextCloud and Collabora URLs)

**Output**:
- Two running LXC containers
- NextCloud accessible at specified URL
- Collabora ready for integration

## Playbook Structure

```
.
├── Deploy.sh                      # Wrapper script (orchestrates deployment)
├── setup_proxmox_api.yaml          # Playbook: API user creation
├── deploy_nextcloud.yaml           # Playbook: NextCloud deployment
├── proxmox_permissions.yaml        # Configuration: API user permissions
├── requirements.yaml               # Ansible collection requirements
├── README.md                      # This file
├── ssh_keys/                      # SSH keys for container access (generated)
│   ├── id_ed25519
│   └── id_ed25519.pub
└── roles/                         # Ansible roles
    ├── proxmox_setup/             # Role: Create API user
    ├── create_nextcloud_container/ # Role: Create NextCloud LXC
    ├── create_collabora_container/ # Role: Create Collabora LXC
    ├── configure_nextcloud/       # Role: Install/configure NextCloud
    └── configure_collabora/       # Role: Install/configure Collabora
```

## Configuration

### Customizing API User Permissions

Edit `proxmox_permissions.yaml` to modify the permissions granted to the API user:

```yaml
proxmox_api_role_name: "Ansible_Automation"
proxmox_api_role_permissions:
  - VM.Allocate
  - VM.Config.Disk
  # ... add or remove permissions as needed
```

### Customizing Deployment Variables

Edit variables in `deploy_nextcloud.yaml` (in the `vars:` section):

```yaml
vars:
  php_version: "8.2"              # PHP version
  nextcloud_version: ""           # Empty = latest, or specify version
  nextcloud_swap: 512             # Swap space in MB
  collabora_swap: 512             # Swap space in MB
  # ... other variables
```

### Container Resources

Adjust during playbook prompts or modify defaults in `deploy_nextcloud.yaml`:

- NextCloud: 2 cores, 2048 MB RAM, 16 GB root disk, 200 GB data disk (defaults)
- Collabora: 2 cores, 2048 MB RAM, 12 GB disk (defaults)

## Troubleshooting

### Common Issues

#### API Connection Fails

**Error**: `Failed to connect to Proxmox API`

**Solutions**:
- Verify Proxmox host is reachable: `ping <proxmox_host>`
- Check API port is open: `telnet <proxmox_host> 8006`
- Verify token credentials are correct
- Check node name matches Proxmox UI

#### SSH Keys Not Found

**Error**: `SSH keys not found`

**Solution**:
```bash
mkdir -p ssh_keys
ssh-keygen -t ed25519 -f ssh_keys/id_ed25519 -N ""
```

#### Storage Pool Not Found

**Error**: `Storage pool 'X' not found`

**Solutions**:
- List available storage: `ssh root@<proxmox_host> "pvesm status"`
- Create storage pool in Proxmox UI
- Use correct storage name (case-sensitive)

#### LXC Template Not Found

**Error**: `LXC template 'X' not found`

**Solutions**:
```bash
# List available templates
ssh root@<proxmox_host> "pveam list local"

# Download template
ssh root@<proxmox_host> "pveam update"
ssh root@<proxmox_host> "pveam download local debian-12-standard_12.2-1_amd64.tar.zst"
```

#### Container Creation Fails

**Possible causes**:
- Insufficient permissions (check API user role)
- Storage full
- VMID already in use
- Network bridge doesn't exist

**Debug**:
```bash
# Check Proxmox logs
ssh root@<proxmox_host> "tail -f /var/log/pve/tasks/active"
```

### Enabling Verbose Output

For detailed Ansible output:

```bash
ansible-playbook -vvv deploy_nextcloud.yaml
```

### Testing API Credentials

Manually test API connection:

```bash
curl -k -H "Authorization: PVEAPIToken=<TOKEN_ID>=<TOKEN_SECRET>" \
  https://<proxmox_host>:8006/api2/json/nodes
```

## Security Considerations

### API User Permissions

The API user created by `setup_proxmox_api.yaml` has **minimal required permissions**:

- Can create and manage LXC containers
- Can allocate storage
- **Cannot** access console
- **Cannot** manage other users
- **Cannot** modify Proxmox system settings

See `proxmox_permissions.yaml` for the complete permission list.

### Credential Management

**Best Practices**:

1. **Delete credential files after use**:
   ```bash
   shred -u .proxmox_credentials.yaml
   ```

2. **Protect private SSH keys**:
   ```bash
   chmod 600 ssh_keys/id_ed25519
   ```

3. **Use strong passwords** for:
   - Container root access
   - Database passwords
   - NextCloud admin account

4. **Store credentials securely**:
   - Use a password manager
   - Don't commit credentials to git
   - Consider using Ansible Vault for sensitive data

### Production Deployment

For production use, additionally implement:

1. **SSL/TLS Certificates**:
   - Use Let's Encrypt for free certificates
   - Configure reverse proxy (nginx/Apache)

2. **Firewall Rules**:
   - Restrict access to Proxmox API (port 8006)
   - Limit container access to necessary ports
   - Use Proxmox firewall or external firewall

3. **Regular Backups**:
   - Backup container configuration
   - Backup NextCloud data
   - Test restore procedures

4. **Monitoring**:
   - Set up monitoring for containers
   - Configure alerts for disk space, CPU, memory
   - Monitor NextCloud logs

5. **Updates**:
   - Keep Proxmox updated
   - Update container OS regularly
   - Update NextCloud and Collabora

## Additional Resources

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [NextCloud Documentation](https://docs.nextcloud.com/)
- [Collabora Online Documentation](https://www.collaboraoffice.com/code/)
- [Ansible Documentation](https://docs.ansible.com/)

## License

This project is provided as-is for educational and production use.

## Acknowledgments

- Proxmox VE team for excellent virtualization platform
- NextCloud community for self-hosted cloud solution
- Collabora for open-source office suite
- Ansible community for automation framework

---

**Questions or Issues?**

Check the [Troubleshooting](#troubleshooting) section or review the inline comments in the playbooks for detailed explanations of each step.
