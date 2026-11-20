# Proxmox-NetBox

> **Stub** - only this README exists. Design intent, not a working deployment.

Ansible deployment of [NetBox](https://github.com/netbox-community/netbox) onto a Proxmox VM:

- clones a base template from [`../Shared/Ansible/`](../Shared/Ansible/README.md) and configures it over Ansible
- uses the shared `svc_ansible@pve` credential and the repo-local venv (`../Shared/Ansible/bootstrap.sh`)
- gitignored real config with committed `*.yaml.example`; secrets via Ansible Vault
- one `Deploy.sh` entry point and its own `CHANGELOG.md`

The **source of truth for the network and the machines on it**: IP address management (prefixes, VLANs, addresses), and a record of the devices and VMs this repo provisions.

## Planned

- NetBox application server (Python/Django behind gunicorn), with the web front end served through `Proxmox-nginx`
- PostgreSQL and Redis as external endpoints taken as configuration, since NetBox requires both. Following the repo's database default, PostgreSQL is `Proxmox-PostgreSQL` and Redis is `Proxmox-Redis`.
- TLS certificates issued under the environment root of trust (`Proxmox-CA`)
- Login against `Proxmox-FreeIPA` over LDAP
- Backups of the database and of NetBox's media and configuration
- IP allocation for the template build network, replacing the derived address in `Shared/Ansible/create-template-linux.yaml`

## Decisions

- **No cross-project dependency.** PostgreSQL, Redis, the reverse proxy and LDAP are each reached through configured endpoints, never by calling another `Proxmox-*` project's playbooks. This project depends only on `Shared/`.

## Open questions

- **Deployment shape.** NetBox from source on a VM.
- **Authentication.** LDAP against FreeIPA is the starting point. OIDC SSO is a possible later layer, matching the `Proxmox-FreeIPA` plan.
- **Feeding Ansible.** Using NetBox as the Ansible inventory source needs the `netbox.netbox` collection. Add it to this project's `requirements.yaml` when the stub is built into a deployment. It is deliberately not added yet, since nothing installs it while this directory is a stub.
- **Seeding.** The deployment should accept a CSV file containing all the minimum required details at the least, but preferably all we can provide.
