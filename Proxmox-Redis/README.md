# Proxmox-Redis

> **Stub** — only this README exists. Design intent, not a working deployment.

Ansible deployment of Redis onto a Proxmox VM, on the same foundation as `Proxmox-Forgejo`:

- clones a base template from [`../Shared/Ansible/`](../Shared/Ansible/README.md) and configures it over Ansible
- uses the shared `svc_ansible@pve` credential and the repo-local venv (`../Shared/Ansible/bootstrap.sh`)
- gitignored real config with committed `*.yaml.example`; secrets via Ansible Vault
- one `Deploy.sh` entry point and its own `CHANGELOG.md`

Cache, queue, and session store for the application projects.

## Planned

- Single node, with an optional replicated setup — Sentinel or Cluster mode (TBD)
- Per-app keyspace / ACL conventions
- Persistence (RDB + AOF) and a backup policy
