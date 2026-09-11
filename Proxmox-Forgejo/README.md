# Proxmox-Forgejo

Deploys [Forgejo](https://forgejo.org/) (a lightweight, self-hosted Git service) onto a Proxmox VM, built with the following opinions:

- **Ansible only** — no Terraform/OpenTofu/other lifecycle-management tool. VM provisioning (`community.proxmox.proxmox_kvm`) and configuration both live in this repo.
- **VM (KVM), not LXC** — chosen specifically because this environment's storage is local-only per node today (no Ceph/ZFS-replication/NFS), and QEMU's live migration story is more mature than LXC's for that case. See "Disaster Recovery" below.
- **Ansible Vault for every secret**, using the standard `vars.yaml`/`vault.yaml` split. The real `vault.yaml` is encrypted **and gitignored** — its `$ANSIBLE_VAULT;1.2;AES256;<vault-id>` header is cleartext and the `<vault-id>` label names a real credential, so even the ciphertext stays out of this public repo. Only `vault.yaml.example` is committed; you create the real file locally with the shared repo vault password. New to Vault? Read the [Ansible Vault guide](../Shared/Ansible/docs/ANSIBLE_VAULT_GUIDE.md) first.
- **One shared, cluster-wide Proxmox credential** in [`../Shared/Ansible/`](../Shared/Ansible/README.md), not a private copy in this project. Every Proxmox-facing project in this mono-repo is meant to use the same `svc_ansible@pve` API token.
- **No local reverse proxy** — this environment already has a dedicated shared reverse proxy for all ingress. Forgejo listens on plain HTTP; TLS terminates upstream. See "Reverse Proxy" below.
- **`.yaml` everywhere a file is actually YAML.**

## Prerequisites

1. A Proxmox cluster reachable from wherever you run this. `Install-Prerequisites.sh` checks the rest of this list for you.
2. **This repo is public — copy every `.example` config file to its real name and fill in your own values before anything else.** The real files are gitignored so your cluster/node names, domain, admin email, and (if you personalize it) your vault-id label never end up committed:
   ```bash
   cp ../Shared/Ansible/ansible.cfg.example ansible.cfg
   cp inventory/hosts.ini.example inventory/hosts.ini
   cp inventory/group_vars/proxmox_pve1/vars.yaml.example inventory/group_vars/proxmox_pve1/vars.yaml
   cp inventory/group_vars/forgejo/vars.yaml.example inventory/group_vars/forgejo/vars.yaml
   ```
   Then edit each real file, replacing every `REPLACE_ME` placeholder. `ansible.cfg` comes from the one canonical example in [`../Shared/Ansible/`](../Shared/Ansible/ansible.cfg.example) — a `COMMON` block every project uses verbatim plus a per-project section — and works as-is; only rename its `homelab` vault-id label/filename if you want something more personal, keeping the same label across every Ansible project in this repo since one shared vault password decrypts them all. `inventory/hosts.ini` needs no Proxmox-node entry — this project reaches Proxmox only over the API, and the Forgejo VM adds itself to the inventory at runtime.
3. The shared Proxmox credential set up (once per cluster, not once per project) by `create-pve_svc_user.yaml` — this generates `group_vars/proxmox_cluster/vars.yaml`/`vault.yaml` (the API token this project uses), so there's no `.example` to copy here. That same playbook also creates the per-node `svc_ansible` SSH account, which this project doesn't need but `../Shared/Ansible/create-template-linux.yaml` does:
   ```bash
   cd ../Shared/Ansible
   ansible-playbook create-pve_svc_user.yaml
   ```
4. A vault password file at `~/.ansible/vault_pass_homelab.txt` — see the [Ansible Vault guide](../Shared/Ansible/docs/ANSIBLE_VAULT_GUIDE.md) section 2 if you've never done this.
5. This project's own vault file:
   ```bash
   ansible-vault create inventory/group_vars/forgejo/vault.yaml
   ```
   using [`inventory/group_vars/forgejo/vault.yaml.example`](inventory/group_vars/forgejo/vault.yaml.example) as the variable reference.
6. **An off-node backup storage target already configured in Proxmox** (Proxmox Backup Server, or an NFS/CIFS share added as storage) — see "Disaster Recovery." This is a hard prerequisite, not optional polish, if the goal is surviving a node's hardware failure. Don't have one yet and just want to test the rest of the deploy? Set `backup_storage_target: "none"` in `inventory/group_vars/proxmox_pve1/vars.yaml` — `proxmox_preflight` turns the check into a loud warning instead of blocking you, but this does **not** give you working disaster recovery.

## Quick start

```bash
./Deploy.sh
```

This runs `Install-Prerequisites.sh`, generates an SSH keypair under `ssh_keys/` if one doesn't exist, then runs `deploy_forgejo.yaml`. The playbook itself has no interactive prompts — `./Deploy.sh` is a convenience wrapper, not a requirement; `ansible-playbook deploy_forgejo.yaml` works the same from cron or CI once the prerequisites above are met.

## What it does

1. **Preflight** (`proxmox_preflight`) — validates the target node, storage pools, network bridge, and off-node backup target exist, and that `forgejo_hostname` isn't already taken. This project does **not** build its own VM template — `vm_template_name`/`vm_template_vmid` must already exist, built out-of-band with [`../Shared/Ansible/create-template-linux.yaml`](../Shared/Ansible/README.md) (shared across every project in this mono-repo); `proxmox_preflight` fails fast, with the exact build command, if it's missing or isn't a template. Fails on any problem with a clear message rather than partway through VM creation.
2. **VM creation** (`create_forgejo_vm`) — clones the template over the API, applies cloud-init settings (SSH key, sizing, network), resizes the OS disk (`scsi0`) to `forgejo_disk_size`, starts it, waits for SSH. The `/opt` data disk (`scsi1`) is left at the template's size — grow it later (see "Disk layout").
3. **Configuration** (`forgejo_prereqs`, `forgejo_database`, `forgejo_install`) — base packages, a dedicated non-root `git` system user, PostgreSQL, the Forgejo binary (checksum-verified download) with systemd hardening, and an idempotent first-admin bootstrap.
4. **Verification** (`forgejo_verify`) — confirms the service is active and the local healthz endpoint responds.

## Reverse proxy

Nothing in this project builds or manages a reverse proxy. On the VM, `ufw` allows **only** `reverse_proxy_source_cidr` to reach `forgejo_http_port` (web, default 3000) and `forgejo_ssh_port` (git-SSH, default 2222) — the shared proxy is the sole ingress for both. Once the VM is up:

1. **Web** — add an upstream route for `forgejo_domain` → `<vm-ip>:3000`. TLS terminates at the proxy; this VM never holds a certificate.
2. **git-over-SSH** — a raw-TCP `stream {}` listener on the proxy forwards `forgejo_ssh_public_port` (default 10000) → `<vm-ip>:2222`. `forgejo_ssh_public_port` is also what Forgejo advertises in clone URLs (`ssh://git@<domain>:10000/…`); a high non-standard port keeps git-SSH off the ports mass scanners hammer. Set `forgejo_ssh_public_port` equal to `forgejo_ssh_port` if you don't proxy SSH.

A full worked config — HTTPS vhost (with the git-push body-size / timeout / forwarded-header tuning) plus the `stream {}` block — is in [`docs/reverse-proxy.nginx.conf.example`](docs/reverse-proxy.nginx.conf.example).

## Disk layout

Both disks come from the shared two-disk template ([`../Shared/Ansible/README.md`](../Shared/Ansible/README.md) → "Disk layout & growing a template's disks"); this project just clones it (`full: true`) and inherits them.

| Path | Disk | Holds |
|---|---|---|
| `/` | `scsi0` | OS only. `create_forgejo_vm` grows it to `forgejo_disk_size` GiB. |
| `/opt/app/forgejo` | `scsi1` (`/opt`) | The versioned `forgejo` binary + the stable `forgejo` symlink. |
| `/opt/data/forgejo` | `scsi1` (`/opt`) | Everything stateful — `repositories/`, LFS, attachments, `log/`, and the `git` user's home. |
| `/etc/forgejo/app.ini` | `/` | Config, rendered by Ansible, read-only to the service. |

`/opt` ships at the template's size (16 GiB) and is **not** resized during deploy. Grow it — or `/`, live, with no downtime and no reboot — with the shared playbook:

```bash
cd ../Shared/Ansible
ansible-playbook update-vm_disk-grow.yaml \
  -e VMID=<vmid> -e blockdev=/dev/sdb -e size=+20G \
  -e grow_ssh_user=<forgejo_deploy_user> -e grow_ssh_key=../Proxmox-Forgejo/ssh_keys/id_ed25519
```

## Disaster recovery: surviving a node's hardware failure

Storage in this environment is local-only per node today. **A backup stored on the same node it's protecting does not survive that node's hardware failure** — so this project treats off-node backup storage as a stated prerequisite, not something it provisions itself.

Two equally valid ways to get backups to that off-node target, once it exists in Proxmox:

- **Simplest — no Ansible involved:** register the Forgejo VM's VMID in Proxmox's own **Datacenter → Backup** scheduled job, pointed at the off-node storage.
- **Ansible-driven:** `ansible-playbook backup_forgejo.yaml -e forgejo_vm_vmid=<vmid>`, wrapping `community.proxmox.proxmox_backup` — useful for cron/systemd-timer-driven or fully-as-code backup triggering.

`vzdump` (either method) captures **both** disks, so size the off-node target for `forgejo_disk_size` + the current `/opt` size.

**The actual "move to another node" runbook** is: restore the latest backup onto a healthy node (`qmrestore`, or via the Proxmox UI). That's what delivers the portability goal today — not live migration, since no shared storage spans nodes yet. If Ceph or ZFS replication is added later, true live migration becomes available for this VM with no changes to these roles.

Run a real DR drill periodically: restore the latest backup to a *different* node than the one that created it, and confirm Forgejo comes up healthy there.

## Verification checklist

- `ansible-playbook deploy_forgejo.yaml --syntax-check`
- `ansible-vault view` each `vault.yaml` before a real run
- Re-run the full playbook — `create_forgejo_vm` and `forgejo_install` should report `changed=0` on the second pass
- On the Proxmox host: VM visible with correct VMID/resources, `cloud-init status --long` clean inside the VM, `ss -tlnp` shows Forgejo bound only where expected, `ufw status` shows port 3000 restricted to the reverse proxy's CIDR
- Inside the VM: `lsblk` shows `sdb` mounted at `/opt` (whole-disk, no `sdb1`); `findmnt /opt` is xfs with `nodev,nosuid,nofail` and **no** `noexec`; the binary is at `/opt/app/forgejo/forgejo` and repositories under `/opt/data/forgejo/repositories`
- `curl http://<vm-ip>:3000/api/healthz` returns 200
- Log in as the vaulted admin account, create a test repo; test git-over-SSH via the proxy (`git clone ssh://git@<forgejo_domain>:<forgejo_ssh_public_port>/…`) and directly from the proxy host (`ssh -p 2222 git@<vm-ip>`)

## Known limitations / next steps

- `forgejo_version` is pinned deliberately — check for updates yourself rather than tracking "latest." (The base image is likewise pinned, in the shared template.)
- Forgejo's built-in SSH server binds `forgejo_ssh_port` (2222) in the VM, reachable only from the reverse proxy, which re-exposes it on `forgejo_ssh_public_port` (10000). Port 22 on the VM stays OpenSSH for management. Unifying git-SSH onto 22 via `AuthorizedKeysCommand` is a documented future enhancement, not built here.
- `Proxmox-NextCloud` is expected to be refactored onto this same shared-credential/Vault tooling once this project is proven out — not done yet.
