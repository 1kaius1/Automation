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

This project deploys NextCloud with integrated Collabora Office on Proxmox VE LXC containers:

1. **NextCloud Deployment** (`deploy_nextcloud.yaml`) - Deploys and configures NextCloud and Collabora containers
2. **Wrapper Script** (`Deploy.sh`) - Orchestrates the process with prompts and validation

The Proxmox API credential is **not** created here. Every Proxmox-facing project in this mono-repo shares one cluster-wide `svc_ansible@pve` account, provisioned once by [`../Shared/Ansible/create-pve_svc_user.yaml`](../Shared/Ansible/README.md). This project reads it from `../Shared/Ansible/group_vars/proxmox_cluster/` and does not manage its own.

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
- The shared `svc_ansible@pve` credential provisioned once per cluster —
  `cd ../Shared/Ansible && ansible-playbook create-pve_svc_user.yaml`
  (see [`../Shared/Ansible/README.md`](../Shared/Ansible/README.md))
- A vault password file in place so `ansible.cfg`'s `vault_identity_list`
  can decrypt that credential's `vault.yaml`
- LXC template downloaded (e.g., Debian 13)
- Available storage pool (LVM-Thin recommended)
- Network bridge configured

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
3. Verify the shared Proxmox credential is present
4. Run the deployment playbook

### Option 2: Manual Step-by-Step

If you prefer manual control:

```bash
# 1. Install required Ansible collections
ansible-galaxy collection install -r requirements.yaml

# 2. Generate SSH keys for container access
mkdir -p ssh_keys
ssh-keygen -t ed25519 -f ssh_keys/id_ed25519 -N ""

# 3. One-time per cluster: provision the shared svc_ansible@pve credential
cd ../Shared/Ansible && ansible-playbook create-pve_svc_user.yaml && cd -

# 4. One-time: point ansible.cfg at your vault password file
cp ansible.cfg.example ansible.cfg   # then set vault_identity_list

# 5. Deploy NextCloud and Collabora
ansible-playbook deploy_nextcloud.yaml
```

## Detailed Usage

### Prerequisite: the shared Proxmox credential

This project does **not** create a Proxmox API user. It uses the one
cluster-wide `svc_ansible@pve` account shared by every Proxmox project in
this mono-repo, provisioned once by
[`../Shared/Ansible/create-pve_svc_user.yaml`](../Shared/Ansible/README.md)
(role + user + token, written Vault-encrypted to
`../Shared/Ansible/group_vars/proxmox_cluster/`). `deploy_nextcloud.yaml`
loads `vars.yaml` + `vault.yaml` from there via `vars_files:` and fails
fast with a pointer if they're missing or the vault can't be decrypted.

### Playbook: NextCloud Deployment

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
├── Deploy.sh                       # Wrapper script (orchestrates deployment)
├── deploy_nextcloud.yaml           # Playbook: NextCloud deployment
├── config.yaml.example             # Deployment settings (copy to config.yaml)
├── ansible.cfg.example             # Copy to ansible.cfg; set vault_identity_list
├── requirements.yaml               # Ansible collection requirements
├── README.md                       # This file
├── ssh_keys/                       # SSH keys for container access (generated)
│   ├── id_ed25519
│   └── id_ed25519.pub
└── roles/
    ├── create_nextcloud_container/ # Role: Create NextCloud LXC
    ├── create_collabora_container/ # Role: Create Collabora LXC
    ├── configure_nextcloud/        # Role: Install/configure NextCloud
    └── configure_collabora/        # Role: Install/configure Collabora
```

The shared Proxmox credential lives in `../Shared/Ansible/` — see that project's README.

## Configuration

### Proxmox API permissions

The shared `svc_ansible@pve` role's privilege list is
`../Shared/Ansible/proxmox_permissions.yaml` (it covers both VM and LXC
provisioning). Edit it there and re-run
`../Shared/Ansible/create-pve_svc_user.yaml` to change what the account
may do cluster-wide. For reference, it grants:

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

### Proxmox API access

This project uses the shared, cluster-wide `svc_ansible@pve` token (see
`../Shared/Ansible/`). Its least-privilege role can create and manage
guests and allocate storage, but **cannot** open a guest console, manage
users/roles/ACLs, or change host system settings. The token secret is
stored only Ansible Vault-encrypted, in
`../Shared/Ansible/group_vars/proxmox_cluster/vault.yaml`.

### Credential Management

**Best Practices**:

1. **Keep the shared token in Vault** — never in `config.yaml` or on a
   command line. `create-pve_svc_user.yaml` writes it encrypted;
   `-e rotate_api_token=true` rotates it.

2. **Protect private SSH keys**:
   ```bash
   chmod 600 ssh_keys/id_ed25519
   ```

3. **Use strong passwords** for container root, the database, and the
   NextCloud admin account (these live in the gitignored `config.yaml`).

4. **Store the rest securely** — a password manager for `config.yaml`
   values; never commit `config.yaml` or `ansible.cfg`.

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
