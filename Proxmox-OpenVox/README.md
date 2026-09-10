# Proxmox-OpenVox

> **Stub** — only this README exists. Design intent, not a working deployment.

Ansible deployment of [OpenVox](https://voxpupuli.org/openvox/) (an open Puppet distribution) with PuppetDB and Puppetboard, onto a Proxmox VM, on the same foundation as `Proxmox-Forgejo`:

- clones a base template from [`../Shared/Ansible/`](../Shared/Ansible/README.md) and configures it over Ansible
- uses the shared `svc_ansible@pve` credential and the repo-local venv (`../Shared/Ansible/bootstrap.sh`)
- gitignored real config with committed `*.yaml.example`; secrets via Ansible Vault
- one `Deploy.sh` entry point and its own `CHANGELOG.md`

Where the other projects *build* a VM, this one *keeps it configured*: ongoing OS and application configuration management for the guests this repo provisions. Ansible does the provisioning and first-boot; OpenVox owns steady state.

## Planned

- OpenVox server (latest stable) + a PostgreSQL-backed PuppetDB + Puppetboard
- Agent bootstrap baked into the shared VM template
- Control-repo layout and module management (r10k or equivalent)

## Open question — the CA

OpenVox needs a PKI for agent ↔ server auth; Puppet ships its own built-in CA for this. The goal is **one CA for the whole environment** (`Proxmox-CA`), not a second one living inside OpenVox — how that integrates (external CA mode, an intermediate delegated to OpenVox, or agent certs issued out of band) is undecided.

