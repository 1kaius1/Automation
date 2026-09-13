# Changelog

All notable changes to `Proxmox-NextCloud/` are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Changes prior to this file's adoption aren't reconstructed here — see `git log` for that history. Entries below start from this point forward.

## [Unreleased]

### Changed

- **Migrated onto the shared `svc_ansible@pve` Proxmox credential.** `deploy_nextcloud.yaml` now loads `../Shared/Ansible/group_vars/proxmox_cluster/vars.yaml` + `vault.yaml` via `vars_files:` and asserts they resolved; the hardcoded/`.proxmox_credentials.yaml`/prompt paths for `proxmox_api_host`/`proxmox_api_token_id`/`proxmox_api_token_secret` are gone. `config.yaml`/`config.yaml.example` keep only `proxmox_node` in the Proxmox section. `Deploy.sh` drops the "create an API user" step and the credentials-file cleanup, and gains a check that the shared vault file is present.
- `ansible.cfg` now sets `vault_identity_list` (needed to decrypt the shared credential) and is gitignored, with a committed `ansible.cfg.example` — matching the `Proxmox-Forgejo`/`Shared` convention. The real file is untracked from git in this same change (`git rm --cached`); its previously-committed version predated this migration entirely and never carried a `vault_identity_list` line, so no vault-id label was ever actually exposed in git history — it goes straight from untracked-content to untracked-file.

### Removed

- `setup_proxmox_api.yaml`, `roles/proxmox_setup/`, `proxmox_permissions.yaml`, and the stale `test.yaml` (a duplicate of `setup_proxmox_api.yaml`) — this project no longer creates its own Proxmox API user. The shared role's privilege list lives in `../Shared/Ansible/proxmox_permissions.yaml` and already covers LXC provisioning.
- Local secret files `.proxmox_credentials.yaml` and `token` (both gitignored) — obsolete; the token secret now lives only Vault-encrypted under `../Shared/Ansible/`. The old standalone `ansible@pve!automation-token` on the cluster can be removed with `pveum user token remove ansible@pve automation-token` (and `pveum user delete ansible@pve`).
