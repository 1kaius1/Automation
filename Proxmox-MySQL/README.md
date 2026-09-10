# Proxmox-MySQL

> **Stub** — only this README exists. Design intent, not a working deployment.

Ansible deployment of an Oracle MySQL server onto a Proxmox VM, on the same foundation as `Proxmox-Forgejo`:

- clones a base template from [`../Shared/Ansible/`](../Shared/Ansible/README.md) and configures it over Ansible
- uses the shared `svc_ansible@pve` credential and the repo-local venv (`../Shared/Ansible/bootstrap.sh`)
- gitignored real config with committed `*.yaml.example`; secrets via Ansible Vault
- one `Deploy.sh` entry point and its own `CHANGELOG.md`

Only for the rare app that requires Oracle MySQL specifically. Prefer `Proxmox-PostgreSQL`, then `Proxmox-MariaDB`.

## Planned

- Single node
- Per-app database + least-privilege user provisioning
- Backups to off-node storage
