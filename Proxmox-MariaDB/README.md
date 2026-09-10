# Proxmox-MariaDB

> **Stub** — only this README exists. Design intent, not a working deployment.

Ansible deployment of a MariaDB server onto a Proxmox VM, on the same foundation as `Proxmox-Forgejo`:

- clones a base template from [`../Shared/Ansible/`](../Shared/Ansible/README.md) and configures it over Ansible
- uses the shared `svc_ansible@pve` credential and the repo-local venv (`../Shared/Ansible/bootstrap.sh`)
- gitignored real config with committed `*.yaml.example`; secrets via Ansible Vault
- one `Deploy.sh` entry point and its own `CHANGELOG.md`

For MySQL-family apps that don't specifically require Oracle MySQL. Reach for `Proxmox-PostgreSQL` first; use this when an app only supports MySQL/MariaDB.

## Planned

- Single node, with an optional primary/replica pair
- Per-app database + least-privilege user provisioning
- Backups (`mariadb-dump` / snapshot) to off-node storage
