# Automation

Ansible automation for my homelab — so that if it blows up, I can redeploy it on a fresh Proxmox cluster without having to remember how.

Everything is built on **`Shared/Ansible/`**: a repo-local Ansible virtualenv, one shared least-privilege Proxmox credential (`svc_ansible@pve`), a VM template pipeline, and a single canonical `ansible.cfg`. Each `Proxmox-*` directory is a self-contained deployment that clones a template and configures it — it depends on `Shared/`, never on another project.

## Platform

- Proxmox VE — VMs, and LXC where it fits.

## Layout

| Directory | What | Status |
|---|---|---|
| `Shared/` | Foundation everything else builds on — `Ansible/` (shared credential, template pipeline, venv, `ansible.cfg`), plus by-language scaffolds (see `Shared/README.md`) | in use |
| `Proxmox-Forgejo/` | Forgejo git server | deployed |
| `Proxmox-NextCloud/` | NextCloud + Collabora | in progress |
| `Proxmox-Steam-Linux/` | SteamCMD dedicated-game-server host (HLDS deathmatch now; data-driven add/remove of other AppIDs planned) | in progress |
| `Proxmox-PostgreSQL/` | PostgreSQL — the default database here; single node or HA | stub |
| `Proxmox-MariaDB/` | MariaDB — for MySQL-family apps that don't need Oracle MySQL | stub |
| `Proxmox-MySQL/` | Oracle MySQL — for the rare app that requires it specifically | stub |
| `Proxmox-Redis/` | Redis — cache / queue / session store; single node or cluster | stub |
| `Proxmox-nginx/` | Shared reverse proxy **and** general web/app server (static, PHP-FPM, FastCGI) | stub |
| `Proxmox-CA/` | The single certificate authority for the whole environment | stub |
| `Proxmox-OpenVox/` | OpenVox (Puppet) + PuppetDB + Puppetboard — ongoing OS/app config management for the guests this repo provisions | stub |

A **stub** is a directory with only a `README.md`: the design intent, not a working deployment.

## Getting started

```bash
Shared/Ansible/bootstrap.sh        # build the repo-local Ansible venv (once per checkout)
```

Then provision the shared Proxmox credential (`Shared/Ansible/README.md` → "Provisioning the shared account"), and follow the `README.md` in whichever project you want to deploy.

## Conventions

- **This repo is public.** Real site-specific files (hostnames, IPs, domains, CIDRs) are gitignored; only `*.example` companions are committed. Secrets go through Ansible Vault — see [`Shared/Ansible/docs/ANSIBLE_VAULT_GUIDE.md`](Shared/Ansible/docs/ANSIBLE_VAULT_GUIDE.md).
- Every project directory keeps its own `CHANGELOG.md` (Keep a Changelog format); the root `CHANGELOG.md` is for cross-cutting entries only.
- `CLAUDE.md` has the full working rules for this repo.
