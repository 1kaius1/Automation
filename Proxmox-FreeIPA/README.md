# Proxmox-FreeIPA

> **Stub** — only this README exists. Design intent, not a working deployment.

Ansible deployment of [FreeIPA](https://www.freeipa.org/) onto Proxmox VMs, on the same foundation as `Proxmox-Forgejo`:

- clones a base template from [`../Shared/Ansible/`](../Shared/Ansible/README.md) and configures it over Ansible
- uses the shared `svc_ansible@pve` credential and the repo-local venv (`../Shared/Ansible/bootstrap.sh`)
- gitignored real config with committed `*.yaml.example`; secrets via Ansible Vault
- one `Deploy.sh` entry point and its own `CHANGELOG.md`

The **central auth provider** for workstations and servers: one place to maintain accounts and their group memberships, with LDAP, Kerberos, sudo rules, host-based access control and SSH key distribution. Hosts enroll as SSSD clients.

## Planned

- At least two replicas, so the directory is not a single point of failure for logins everywhere
- Client enrollment (`ipa-client-install` or the `freeipa.ansible_freeipa` collection) baked into the shared VM template
- Backups of the directory and its CA
- Web apps (`Proxmox-Forgejo`, `Proxmox-NextCloud`, `Proxmox-NetBox`) authenticating against it over LDAP; OIDC SSO (Keycloak or Authentik backed by this directory) is a possible later layer, not a starting point

## Decisions

- **FreeIPA's CA is subordinate to `Proxmox-CA`.** The environment has one root of trust, and this project never creates a second. Install with `ipa-server-install --external-ca`: the install emits a CSR, the offline root signs it, and the install resumes with the signed chain. IPA can still issue host and service certificates to enrolled machines from its own subordinate CA. See `Proxmox-CA/README.md` for the signing rules.
- **The signed chain is an input file.** This project depends only on `Shared/` and never calls `Proxmox-CA`'s playbooks. `Deploy.sh` must pause at the CSR handoff and resume once the signed chain is supplied.
- **`svc_ansible@pve` stays in the local `pve` realm**, not in this directory, so automation keeps working when the directory is down.
- **Break-glass local accounts on every host**, since this is a tier-0 dependency: if it is unavailable, logins fail everywhere.
- **Named for the product, not the abbreviation**, matching `Proxmox-Forgejo`, `Proxmox-NextCloud` and the others.

## Open questions

- **Windows workstations.** FreeIPA is the right fit for Linux-only clients. If Windows clients are in scope, Samba AD may fit better, since FreeIPA's AD trust is awkward.
- **DNS.** Kerberos needs consistent forward and reverse DNS and synced clocks. Whether IPA's integrated DNS is used, or the existing DNS stays authoritative, is undecided.
- **OS release.** FreeIPA is RHEL-family only; check which release the shared template pipeline can currently build before picking the server OS.
