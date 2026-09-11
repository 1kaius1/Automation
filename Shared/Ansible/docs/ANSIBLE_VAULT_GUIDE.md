# Ansible Vault: a complete walkthrough

This guide assumes you have never used Ansible Vault before. Every section names the exact command to run, what you should see if it works, and what it looks like when it doesn't. It applies to every Ansible project in this mono-repo, not just one — the running example below is the shared Proxmox credential in `Shared/Ansible/`, and commands are shown as run from that directory.

> **A note on `homelab` / `vault_pass_homelab.txt`:** every command below uses these as concrete, copy-pasteable examples — they're just the default label and filename in the canonical [`../ansible.cfg.example`](../ansible.cfg.example) (see the comment there), not a fixed requirement. No playbook in this repo hardcodes this name; they only ever read whatever `vault_identity_list` says in the project's `ansible.cfg`. If you personalize the label/filename, use the **same** one in every project's `ansible.cfg` and substitute it everywhere `homelab`/`vault_pass_homelab.txt` appears below. (For a *per-vault* identity split instead of one shared password, see section 12.)

## 1. What Vault is, and why this repo uses it this way

Ansible Vault encrypts a file (or a single value) at rest using AES256. Ansible decrypts it transparently in memory whenever a playbook runs, as long as it has the right password — nothing about how you write a task changes. A task that needs a password just references `{{ proxmox_api_token_secret }}` like any other variable.

Every set of secrets is split into two files:

- `vars.yaml` — plaintext, committed to git. Holds normal config plus *references* to secrets, e.g. `proxmox_api_token_secret: "{{ vault_proxmox_api_token_secret }}"`.
- `vault.yaml` — fully encrypted, and **gitignored** — not committed at all. Holds the actual values.

The encrypted file is kept out of this public repo even as ciphertext: its first line, `$ANSIBLE_VAULT;1.2;AES256;<vault-id>`, is cleartext, and the `<vault-id>` label there names a real credential. Only `vault.yaml.example` (plaintext placeholders, the variable reference) is committed. Recovery of a real `vault.yaml` is via the vault password + `ansible-vault create` from the `.example`, or an out-of-band copy of the file — **not** git history. Losing the vault password means losing access to everything it protects, so section 2 matters more than it looks.

The `vault.yaml` files in this repo (all gitignored):

- `group_vars/proxmox_cluster/vault.yaml` — the Proxmox API token, shared across every project. **Generated** by `create-pve_svc_user.yaml`, not written by hand. *(This guide's running example.)*
- `template_configuration_vault.yaml` — the `sysadmin` console password baked into VM templates. Hand-created.
- `../Proxmox-Forgejo/inventory/group_vars/forgejo/vault.yaml` — that project's own secrets (DB password, admin password, Forgejo's internal tokens). Hand-created.

Unless you have split them (section 12), all of these use the same vault password (vault-id `homelab` in the examples).

## 2. One-time setup: your vault password file

The vault password itself is **not** a file you commit. It lives outside the repo, and Ansible is told where to find it.

```bash
mkdir -p ~/.ansible
chmod 700 ~/.ansible
openssl rand -base64 32 > ~/.ansible/vault_pass_homelab.txt
chmod 600 ~/.ansible/vault_pass_homelab.txt
```

**Expected result:** no output from any of these commands. Check it worked:

```bash
$ cat ~/.ansible/vault_pass_homelab.txt
Xk3p9...   (a random base64 string)
$ ls -l ~/.ansible/vault_pass_homelab.txt
-rw------- 1 you you 45 Sep  1 12:00 /home/you/.ansible/vault_pass_homelab.txt
```

The `-rw-------` (mode 600) matters — anyone who can read this file can decrypt every secret it protects.

**This is the single most important file in this whole setup.** If you lose it, every `vault.yaml` it encrypts becomes permanently unreadable — there is no recovery. Back it up somewhere durable (a password manager entry is ideal) before going further. See also `../RUNBOOK-Regenerate_Vaults.md` for the rebuild-from-scratch procedure if it does happen.

## 3. How the password file is wired to Ansible

Every project's `ansible.cfg` (each copied from the one canonical [`../ansible.cfg.example`](../ansible.cfg.example), `COMMON` section) contains:

```ini
[defaults]
vault_identity_list = homelab@~/.ansible/vault_pass_homelab.txt
```

This tells Ansible: "there's a vault identity labeled `homelab`, and its password lives at that path." Any `ansible-playbook` or `ansible-vault` command run from a project directory picks this up automatically — no `--ask-vault-pass` flag needed.

**What it looks like if the file is missing:**
```
$ ansible-playbook create-pve_svc_user.yaml
ERROR! Attempting to decrypt but no vault secrets found
```

**What it looks like if the file exists but has the wrong permissions on some systems (rare, but shows as):**
```
ERROR! Unable to read vault password file '/home/you/.ansible/vault_pass_homelab.txt': [Errno 13] Permission denied
```
Fix: `chmod 600 ~/.ansible/vault_pass_homelab.txt`.

## 4. Creating a new vaulted file

You won't do this for `group_vars/proxmox_cluster/vault.yaml` — `create-pve_svc_user.yaml` runs `ansible-vault create` internally and writes it for you. You *do* create the hand-written ones this way — `template_configuration_vault.yaml` here, or a project's own vault such as `../Proxmox-Forgejo/inventory/group_vars/forgejo/vault.yaml`, using its `vault.yaml.example` as the reference for which variables it needs:

```bash
ansible-vault create ../Proxmox-Forgejo/inventory/group_vars/forgejo/vault.yaml
```

No `--vault-id` flag needed — with one identity configured in `vault_identity_list` (section 3), Ansible unambiguously uses it, reading the password straight from `~/.ansible/vault_pass_homelab.txt`. (You'd need `--vault-id`/`--encrypt-vault-id` once more than one identity is configured — see section 12.)

**What happens:** no password prompt at all (it's read from the file silently), then your `$EDITOR` opens an empty file. Type the real content, matching the `vault.yaml.example`, e.g.:

```yaml
---
vault_forgejo_db_password: "a-real-generated-password"
vault_forgejo_admin_password: "another-real-generated-password"
vault_forgejo_secret_key: "output-of-the-python-command-below"
```

**Watch for app-specific format constraints.** Some applications reject otherwise-valid secret encodings — e.g. Forgejo's `secret_key` / `internal_token` / `jwt_secret` / `lfs_jwt_secret` must be URL-safe, **unpadded** base64 (`python3 -c "import base64,os; print(base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('='))"`); `openssl rand -hex 32` or plain base64 crash it at startup. The authoritative note for each such field is in that project's `vault.yaml.example`. The vault password itself (section 2) has no such constraint.

Save and close the editor. Ansible encrypts the file the moment the editor exits.

**Confirm it worked:**
```bash
$ head -c 15 ../Proxmox-Forgejo/inventory/group_vars/forgejo/vault.yaml
$ANSIBLE_VAULT;1
```
If you see that header, the file is encrypted. If you instead see plain YAML text, encryption did not happen — do not commit it; delete and retry.

## 5. Editing an existing vault file

```bash
ansible-vault edit group_vars/proxmox_cluster/vault.yaml
```

**What happens:** Ansible decrypts the file to a temporary location, opens it in `$EDITOR`, and re-encrypts it the moment you save and close — silently, with no output at all if it succeeds. That silence is normal; a command that prints nothing and returns you to the prompt means it worked.

**What failure looks like** (wrong vault password configured, or file corrupted):
```
ERROR! Decryption failed (no vault secrets were found that could decrypt) on group_vars/proxmox_cluster/vault.yaml
```

## 6. Viewing without editing

```bash
$ ansible-vault view group_vars/proxmox_cluster/vault.yaml
---
vault_proxmox_api_token_secret: "3f9c1e2a-..."
```
Prints the decrypted content to your terminal and exits — the file on disk is untouched. Use this to sanity-check a file before a real run (see section 10).

## 7. Encrypting/decrypting an existing plaintext file in place

If you ever end up with a plaintext file that should have been encrypted (e.g. you `cp`'d `vault.yaml.example` to `vault.yaml` and filled in real values without using `ansible-vault create`):

```bash
ansible-vault encrypt group_vars/proxmox_cluster/vault.yaml
```

The reverse (rarely needed — mainly for one-off inspection with a tool that can't call `ansible-vault` itself):
```bash
ansible-vault decrypt group_vars/proxmox_cluster/vault.yaml
```
**Never leave a file decrypted and walk away from it** — re-encrypt immediately after you're done, and never `git add` a file in a decrypted state (check with the `head -c 15` trick from section 4 before committing anything under a `vault.yaml` name).

## 8. Encrypting a single value inline

For a one-off secret you want inline in an otherwise-plaintext file, rather than a whole separate vault file:

```bash
$ ansible-vault encrypt_string 'my-secret-value' --name 'some_var_name'
some_var_name: !vault |
          $ANSIBLE_VAULT;1.2;AES256;homelab
          66386439653...
```
Paste that whole `some_var_name: !vault |` block directly into a plaintext YAML file. This repo doesn't use this pattern (it uses whole-file vaulting instead), but it's useful to recognize if you see it elsewhere.

## 9. Running a playbook non-interactively

```bash
$ ansible-playbook create-pve_svc_user.yaml
PLAY [Inspect the existing shared credential] *******************************************
...
```
No password prompt appears — `vault_identity_list` in `ansible.cfg` handles it silently. This is what a normal run looks like.

**To see the alternative** (so you recognize it if your `ansible.cfg` ever gets misconfigured), comment out the `vault_identity_list` line and try again:
```
$ ansible-playbook create-pve_svc_user.yaml
Vault password (homelab):
```
It's now waiting on you to type the password interactively. Ctrl+C out, uncomment the line, and don't run it this way normally — a playbook waiting on a password prompt can't run from cron or unattended.

## 10. Sanity-checking before a real run

Before pointing anything at a real Proxmox cluster:
```bash
ansible-vault view group_vars/proxmox_cluster/vault.yaml
ansible-vault view ../Proxmox-Forgejo/inventory/group_vars/forgejo/vault.yaml
ansible-playbook create-pve_svc_user.yaml --syntax-check
```
If the `view` commands print readable YAML and `--syntax-check` prints `playbook: create-pve_svc_user.yaml` with no errors, you're ready.

## 11. Rotating the vault password

If you suspect `~/.ansible/vault_pass_homelab.txt` has been exposed, rotate it — `rekey` every file it protects:

```bash
openssl rand -base64 32 > ~/.ansible/vault_pass_homelab_new.txt
chmod 600 ~/.ansible/vault_pass_homelab_new.txt

for f in group_vars/proxmox_cluster/vault.yaml \
         template_configuration_vault.yaml \
         ../Proxmox-Forgejo/inventory/group_vars/forgejo/vault.yaml ; do
  ansible-vault rekey \
    --vault-id homelab@~/.ansible/vault_pass_homelab.txt \
    --new-vault-id homelab@~/.ansible/vault_pass_homelab_new.txt \
    "$f"
done
```
Then replace the old file with the new one:
```bash
shred -u ~/.ansible/vault_pass_homelab.txt
mv ~/.ansible/vault_pass_homelab_new.txt ~/.ansible/vault_pass_homelab.txt
```
Every project's `ansible.cfg` already points at `vault_pass_homelab.txt` by name, so no config change is needed once the rename above is done — just make sure every machine/user that runs these playbooks gets the new password file, since the old one no longer works.

## 12. Vault-ID strategy — one identity, or several

The examples use one vault-id, `homelab`. As a second Proxmox node or site is added, you don't need to touch existing vault files — just add a second identity:

```ini
# ansible.cfg
vault_identity_list = homelab@~/.ansible/vault_pass_homelab.txt, dc2@~/.ansible/vault_pass_dc2.txt
```

Then create that site's own vault file under the new label. With two identities configured, Ansible can no longer guess which one to encrypt *new* content with, so `create`/`encrypt` need `--encrypt-vault-id` to say which (a bare label, not `label@source` — that form is only for `--vault-id`):
```bash
ansible-vault create --encrypt-vault-id dc2 inventory/group_vars/proxmox_pve2/vault.yaml
```

This only matters for creating/encrypting. **Reading** an already-encrypted file (`view`/`edit`/decrypting for a playbook run) needs no flag at all either way — Ansible tries each configured identity's password against the file and matches by the label stamped in its ciphertext header (`$ANSIBLE_VAULT;1.2;AES256;dc2`), so both identities coexist transparently for everything except creating something new.

### Splitting by vault file, not just by site

The same mechanism gives you **one password per `vault.yaml`** — so a leaked or lost password only burns that file's secrets, not every vault in the repo. Pick a scheme (one identity per project vault, or per environment), name the identities after their *purpose* (the label lands in the cleartext header — don't put a network/host name there), and list them all in `vault_identity_list`, identical in every project's `ansible.cfg`:

```ini
vault_identity_list = proxmox_api@<vault-dir>/proxmox_api, template_build@<vault-dir>/template_build, forgejo@<vault-dir>/forgejo
```

Each `vault.yaml` is then created once under its label:
```bash
ansible-vault create --encrypt-vault-id forgejo ../Proxmox-Forgejo/inventory/group_vars/forgejo/vault.yaml
```
`create-pve_svc_user.yaml` encrypts `group_vars/proxmox_cluster/vault.yaml` for you — with more than one identity configured, pass the label to it as `-e vault_encrypt_id=proxmox_api`.

### The password files

They can live anywhere `ansible.cfg` can reach. Pick a durable location **outside `~/.ansible/`** — a stray cleanup of Ansible's state directory shouldn't take your keys with it — and **back up each one the moment you create it**: the encrypted `vault.yaml`s are gitignored, so a lost password means that ciphertext is gone for good, no git history to fall back on.

A `vault_identity_list` entry may also point at an **executable script** instead of a flat file — Ansible runs it and reads the password from its stdout. Source it from `pass show …`, `gpg -d …`, `bw get password …`, a keyring, etc., and there is no standing plaintext secret on disk.

## 13. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR! Decryption failed (no vault secrets were found that could decrypt)` | Wrong password, or the file's ciphertext is corrupted | Confirm the right vault-id/password file is configured; if the file is genuinely corrupted, restore it from your out-of-band backup or re-create it from `vault.yaml.example` (the real `vault.yaml` is gitignored — there is no earlier commit to restore). See `../RUNBOOK-Regenerate_Vaults.md`. |
| `ERROR! Attempting to decrypt but no vault secrets found` | `vault_identity_list` isn't set, or you're running from a directory without the right `ansible.cfg` | Check you're in a project directory (`Shared/Ansible/`, `Proxmox-Forgejo/`, …) and that its `ansible.cfg` has the `vault_identity_list` line |
| A command prompts interactively for the vault password (`Vault password (...):`) even though `vault_identity_list` is configured | Same cause as above, easy to hit by accident: Ansible only reads `ansible.cfg` from the **current working directory** — never a parent or sibling. The repo root itself has no `ansible.cfg` (each project has its own), so a command run from there finds none | `cd` into the project directory whose `ansible.cfg` you want (`Shared/Ansible/`, `Proxmox-Forgejo/`, …) before running `ansible-vault`/`ansible-playbook`, or pass `--vault-id`/set `ANSIBLE_CONFIG` explicitly |
| `ansible-vault requires the cryptography library in order to function` | Not a vault problem — this is the system (or old `~/.local`) Ansible install running, not this repo's venv | Use the venv explicitly, e.g. `../.venv/bin/ansible-vault view <path>`, or `source .venv/bin/activate` first — see `../README.md` → "The Ansible toolchain" |
| `Unable to read vault password file: Permission denied` | Wrong file permissions | `chmod 600 ~/.ansible/vault_pass_homelab.txt` |
| A `vault.yaml` was `git add -f`'d while **decrypted** | Someone ran `ansible-vault decrypt`, then force-added past the gitignore before re-encrypting | This is a real incident, not a formatting fix: the secret is now in git in plaintext. Rotate every value in that file immediately (new DB password, new tokens, etc.), re-encrypt, and commit the removal. Rewriting history to drop the old blob does not fully solve this — treat the exposed secret as burned. (The `vault.yaml` gitignore normally prevents this — never `-f` past it.) |

## 14. Cheat sheet

```bash
# One-time setup
openssl rand -base64 32 > ~/.ansible/vault_pass_homelab.txt && chmod 600 ~/.ansible/vault_pass_homelab.txt

# Create a new vault file (no --vault-id needed with one identity configured)
ansible-vault create <path>

# Edit
ansible-vault edit <path>

# View (read-only)
ansible-vault view <path>

# Encrypt an existing plaintext file
ansible-vault encrypt <path>

# Decrypt in place (avoid leaving it this way)
ansible-vault decrypt <path>

# Encrypt a single value inline
ansible-vault encrypt_string 'value' --name var_name

# Once a SECOND identity is configured (section 12), create/encrypt need
# --encrypt-vault-id to say which one — reading never does:
ansible-vault create --encrypt-vault-id dc2 <path>

# Rotate the vault password
ansible-vault rekey --vault-id homelab@<old-file> --new-vault-id homelab@<new-file> <path>

# Run a playbook (no prompt, if ansible.cfg is set up)
ansible-playbook create-pve_svc_user.yaml
```
