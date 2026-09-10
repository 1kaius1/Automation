# Proxmox-nginx

> **Stub** — only this README exists. Design intent, not a working deployment.

Ansible deployment of a standalone nginx server onto a Proxmox VM, on the same foundation as `Proxmox-Forgejo`:

- clones a base template from [`../Shared/Ansible/`](../Shared/Ansible/README.md) and configures it over Ansible
- uses the shared `svc_ansible@pve` credential and the repo-local venv (`../Shared/Ansible/bootstrap.sh`)
- gitignored real config with committed `*.yaml.example`; secrets via Ansible Vault
- one `Deploy.sh` entry point and its own `CHANGELOG.md`

Two roles on one server:

- **Shared reverse proxy** — TLS termination and routing for the app projects that run their own application server (Gunicorn, Passenger, a Node process, …). See e.g. [`../Proxmox-Forgejo/docs/reverse-proxy.nginx.conf.example`](../Proxmox-Forgejo/docs/reverse-proxy.nginx.conf.example), a hand-off to this project.
- **General web / application server** — for everything nginx serves directly and that doesn't need a separate app-server process: static sites, PHP (via PHP-FPM), and other FastCGI/CGI languages.

## Planned

- HTTP/HTTPS vhosts + a `stream {}` layer for raw-TCP passthrough (git-SSH, etc.)
- PHP-FPM (and a FastCGI story for other languages) for directly-served apps
- Certificates pulled from `Proxmox-CA` (ACME), not per-service certs
- Per-vhost config generated from a small inventory
