# CLAUDE.md

Repo-wide instructions for Claude Code sessions working in this mono-repo.

Git workflow rules - branching, commits, pull requests, destructive-operation
confirmation - live in `.claude/rules/git-workflow.md` and load automatically;
see that file, not this one, for those.

## Toolchain

Ansible runs from a repo-local virtualenv at `<repo>/.venv`, built by `Shared/Ansible/bootstrap.sh` (collections in `<repo>/.ansible/`, both gitignored). **Never `pip install` Ansible or its dependencies onto the system Python.** Run playbooks through a project's `Deploy.sh` / `Install-Prerequisites.sh` (they put `.venv/bin` on `PATH` and export `ANSIBLE_COLLECTIONS_PATH`), or `source .venv/bin/activate` for ad-hoc commands.

## Project structure

- Each top-level project is `Proxmox-<Component>/`, self-contained, and depends only on `Shared/` — never on another `Proxmox-*` project.
- A project directory with only a `README.md` is a **stub**: design intent, not a working deployment. Don't run it.
- Playbooks and scripts take a CRUD-verb prefix — `create-`, `read-`, `update-`, `delete-` (e.g. `create-template-linux.yaml`, `update-vm_disk-grow.yaml`).
- YAML files use the `.yaml` extension, never `.yml`.

## Idempotency

Every playbook and role must be safely re-runnable. Before considering a playbook
done, run it twice against the same target and confirm the second run reports
`changed=0` — not just that the first run succeeded. Prefer Ansible's built-in
modules (idempotent by design) over `shell`/`command` tasks; when `shell`/`command`
is unavoidable, guard it with `creates`, `changed_when`, or an explicit check so
re-runs don't misreport or repeat work.

## Changelog workflow

Every project directory (`Proxmox-Forgejo/`, `Proxmox-NextCloud/`, `Shared/`, and any future top-level project) has its own `CHANGELOG.md` in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. The root `CHANGELOG.md` is separate and scoped differently.

- **Scope**: a directory's `CHANGELOG.md` only logs changes to files within that directory and its subdirectories — unless a subdirectory has its own `CHANGELOG.md` (none do today), in which case that subdirectory's changes belong there instead.
- **When to update**: any commit that changes tracked files under a project directory adds an entry to that directory's `CHANGELOG.md` under `## [Unreleased]`. This must happen in the same commit and never be deferred to a later cleanup pass.
- **Categories**: use the standard Keep a Changelog headings as needed — `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`. Omit headings with nothing under them.
- **Root `CHANGELOG.md`**: high-level, cross-cutting entries only — e.g. "Added new project: Proxmox-Forgejo" — never implementation detail (that belongs in the project's own `CHANGELOG.md`). Most commits only touch one project's `CHANGELOG.md`, not root's.
- **Versioning**: none of these projects currently cut version numbers or tags. Entries accumulate under `[Unreleased]` indefinitely. If a project starts tagging releases later, convert the top of its `CHANGELOG.md` to dated version headings at that point, per the Keep a Changelog spec — don't do this preemptively.

## Public repo

This repository is public. Never commit real cluster/node names, IPs, internal domains, admin emails, or internal-network CIDRs — see `Proxmox-Forgejo/README.md` and `Shared/Ansible/README.md` for the established `.example`-file convention (real, site-specific files are gitignored; only placeholder `.example` files are committed). Secrets always go through Ansible Vault (encrypted ciphertext is safe to commit) — see `Shared/Ansible/docs/ANSIBLE_VAULT_GUIDE.md`. Never call `ansible-vault` in a way that prints decrypted content to a log a CI system or shell history would retain.
