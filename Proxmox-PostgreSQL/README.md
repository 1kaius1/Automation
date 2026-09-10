# Proxmox-PostgreSQL

> **Stub** — only this README exists. Design intent, not a working deployment.

Ansible deployment of a PostgreSQL server onto a Proxmox VM, on the same foundation as `Proxmox-Forgejo`:

- clones a base template from [`../Shared/Ansible/`](../Shared/Ansible/README.md) and configures it over Ansible
- uses the shared `svc_ansible@pve` credential and the repo-local venv (`../Shared/Ansible/bootstrap.sh`)
- gitignored real config with committed `*.yaml.example`; secrets via Ansible Vault
- one `Deploy.sh` entry point and its own `CHANGELOG.md`

This is the default database for projects in this repo; the app projects (`Proxmox-Forgejo`, `Proxmox-NextCloud`, …) point at it rather than each running their own.

## Planned

- Single node, with an optional HA cluster (auto-failover — mechanism TBD)
- Per-app database + least-privilege role provisioning
- Base backup + WAL archiving to off-node storage
- Tuned defaults from the VM's resource size
