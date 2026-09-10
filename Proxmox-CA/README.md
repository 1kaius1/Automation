# Proxmox-CA

> **Stub** — only this README exists. Design intent, not a working deployment.

Ansible deployment of the **single certificate authority for the whole environment** onto a Proxmox VM, on the same foundation as `Proxmox-Forgejo`:

- clones a base template from [`../Shared/Ansible/`](../Shared/Ansible/README.md) and configures it over Ansible
- uses the shared `svc_ansible@pve` credential and the repo-local venv (`../Shared/Ansible/bootstrap.sh`)
- gitignored real config with committed `*.yaml.example`; secrets via Ansible Vault
- one `Deploy.sh` entry point and its own `CHANGELOG.md`

One CA issues every internal TLS certificate — the shared web/reverse proxy (`Proxmox-nginx`), Forgejo, internal APIs — replacing the self-signed stopgaps, so the environment trusts a single root.

## Planned

- Offline root CA + an online issuing intermediate
- ACME endpoint so `Proxmox-nginx` and app VMs request and renew certs directly
- A trust bundle installed into the shared VM template

## Open question — OpenVox

`Proxmox-OpenVox` also needs a PKI (Puppet normally runs its own CA for agent certs). The intent is for it to consume *this* CA rather than stand up its own; the integration (external CA mode / a delegated intermediate) is undecided — see `Proxmox-OpenVox/README.md`.
