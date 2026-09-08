# Shared

Code and configuration reused by more than one project in this repo. If a
thing is only ever used by one project, it lives in that project; when a
second project needs it, it moves here. Dependencies flow one way —
projects depend on `Shared/`, never the reverse.

## Layout

One subdirectory per language / toolchain. Each holds self-contained,
referenceable units (a role, a package, a module, a library) and its own
README once it's more than a single file.

| Dir | For | Status |
|---|---|---|
| `Ansible/` | Playbooks, roles and inventory shared by the Proxmox-facing projects — the `svc_ansible` cluster credential and the VM-template pipeline. | In use — see [`Ansible/README.md`](Ansible/README.md) |
| `Python/` | Helper packages/modules: logging setup, credential prompts that return a token for further automation, config-file CRUD, and similar. | Empty scaffold |
| `Go/` | Standalone utilities and reusable packages. | Empty scaffold |
| `BASH/` | Sourceable shell function libraries and small shared scripts. | Empty scaffold |
| `C/`, `CPP/` | Reusable C / C++ sources and headers. | Empty scaffold |
| `dotNET/` | Shared .NET class libraries. | Empty scaffold |

The empty directories are kept as placeholders so the intended home for
each kind of code is obvious before anything is written there.

## How projects consume it

- **Ansible** — a project playbook pulls shared vars in with a relative
  `vars_files:` include (not a symlink), so the dependency is visible in
  the file itself. See [`Ansible/README.md`](Ansible/README.md).
- **Everything else** — reference by relative path, a git submodule, or
  the language's local-path dependency mechanism (a Go `replace`
  directive, an editable pip install, a .NET project reference). Anything
  that keeps the link explicit and avoids copy-paste drift.

## Conventions (all of `Shared/`)

- **One changelog.** The whole tree shares a single
  [`CHANGELOG.md`](CHANGELOG.md) (Keep a Changelog format). Any commit
  that touches files here adds an entry under `## [Unreleased]`, in the
  same commit. Per-language subdirectories do not get their own.
- **Public repo.** Never commit real host names, IPs, internal domains,
  admin emails, or internal CIDRs. Site-specific files are gitignored;
  only placeholder `*.example` companions are committed (`Ansible/`
  established the pattern). Secrets go through Ansible Vault — and the
  real vault files here are gitignored too, since even ciphertext exposes
  the vault-id in its header.
- **Self-contained.** A unit under `Shared/` must not reach back into a
  specific project's files or assume that project's layout.
