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

## Decisions

- **This CA is the root of trust for everything.** It is deliberately not tied closely to any other project, because every other project depends on it. Services that run their own CA internally (FreeIPA, OpenVox) are subordinate to it, never a second root.
- **Subordinate CAs are signed by the offline root**, as peers of the online issuing intermediate, so the root only ever signs intermediates. The signing is a rare manual ceremony (about once per subordinate CA lifetime), not part of an unattended deploy.
- **No cross-project dependency.** Projects depend only on `Shared/`, so the pieces every consumer needs live there, not here: the root and intermediate certificates, the trust-bundle install in the VM template, and the CSR-signing convention. A consuming project takes the signed chain as an input file and never calls this project's playbooks. These `Shared/` changes merge first, as their own PR, per the repo's `Shared/` sequencing rule.
- **Build order:** this CA, then the `Shared/` trust bundle, then `Proxmox-FreeIPA`, then `Proxmox-OpenVox` and the rest.

## Consumers with their own CA

- `Proxmox-FreeIPA` — runs its CA (Dogtag) as a subordinate of this root via `ipa-server-install --external-ca`: the install emits a CSR, the offline root signs it, and the install resumes with the signed chain. Its `Deploy.sh` must pause and resume cleanly at that handoff.
- `Proxmox-OpenVox` — also subordinate to this root; the mechanism (external CA mode, a delegated intermediate, or agent certs issued out of band) is still undecided. See `Proxmox-OpenVox/README.md`.
