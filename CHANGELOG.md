# Changelog

All notable high-level, cross-cutting changes to this mono-repo are documented here. Implementation detail for a specific project belongs in that project's own `CHANGELOG.md` instead — see `CLAUDE.md` for the full scoping rule.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Stub directories for planned deployments, each a `README.md` only: `Proxmox-CA`, `Proxmox-MariaDB`, `Proxmox-MySQL`, `Proxmox-OpenVox`, `Proxmox-PostgreSQL`, `Proxmox-Redis`, `Proxmox-nginx`.
- `README.md` expanded from a one-liner into a repo overview — layout table (with per-project status), how projects build on `Shared/Ansible/`, getting-started, and the public-repo / changelog conventions. `CLAUDE.md` gains "Toolchain" (venv, never `pip install` on system Python) and "Project structure" (self-contained `Proxmox-<Component>/`, stub definition, CRUD-verb playbook prefix, `.yaml` not `.yml`) sections.
- New project: `Proxmox-Forgejo` — Ansible-based Forgejo deployment on Proxmox.
- New project: `Proxmox-Steam-Linux` — Ansible-based SteamCMD dedicated-game-server deployment on Proxmox.
- `Shared/Ansible/` — shared, cluster-wide Proxmox automation credential and bootstrap tooling, usable by any project in this repo.
- `CLAUDE.md` — repo-wide conventions for Claude Code sessions, including the changelog workflow itself and the public-repo `.example`-file rule.
- `.claude/rules/git-workflow.md`, `.claude/settings.json`, and `.github/pull_request_template.md` — formalized branching/commit/PR conventions (feature-branch + PR required, Conventional Commits, no AI-attribution, a Shared/ dependency sequencing rule) backed by real guardrails (denies force-push and hard reset, asks before other destructive operations) and a PR template with hard gates for the changelog and public-repo secrecy rules.

### Changed

- **The Ansible toolchain is a repo-local Python virtualenv now.** `Shared/Ansible/bootstrap.sh` builds `<repo-root>/.venv/` (from `requirements.txt`) and `<repo-root>/.ansible/collections/` (from every `requirements.yaml`), both gitignored — nothing is installed on the system Python, which is where installing `cryptography` for Ansible Vault was breaking other distro apps. Every project's `Deploy.sh` / `Install-Prerequisites.sh` and `create-templates_from_manifest.sh` put `.venv/bin` on `PATH` and export `ANSIBLE_COLLECTIONS_PATH` on their own — no activation step. The old `Installers/` dir and its apt-PPA `Install-Ansible.sh` are gone.
- **Every Proxmox-facing project now shares one `svc_ansible@pve` identity.** `Proxmox-NextCloud` was migrated off its own `setup_proxmox_api.yaml` / `ansible@pve` token onto the shared credential in `Shared/Ansible/` (as `Proxmox-Forgejo` already was). In `Shared/Ansible/`, the API-token bootstrap (`setup_proxmox_automation_account.yaml`) was folded into `create-pve_svc_user.yaml`, so one playbook now provisions the whole identity — the cluster API token *and* the per-node SSH account + scoped sudo + image cache dir.
