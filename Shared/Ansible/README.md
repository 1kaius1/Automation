# Shared/Ansible

Ansible assets shared across every automation project in this mono-repo that talks to Proxmox — currently `Proxmox-Forgejo` and `Proxmox-NextCloud`.

## Why this exists

Proxmox clusters replicate users, realms, ACLs, and API tokens across every node via `pmxcfs`. A single API token, tied to one dedicated automation account, is valid against the whole cluster — there is no reason for each project (or each node) to hold its own separate credential. Centralizing it here means:

- One account to rotate, audit, and lock down (`svc_ansible@pve`), instead of one per project.
- New projects that need Proxmox access reference this instead of re-running their own account-bootstrap flow.
- The account lives in the local `pve` realm deliberately, even in environments where interactive human logins are AD/LDAP-backed — this decouples automation from AD's rotation and availability, and keeps a leaked token's blast radius scoped to automation only, not a real directory identity.

## The shared `svc_ansible` identity

One name, two mechanisms, both provisioned by **`create-pve_svc_user.yaml`**:

| | What | Where it's used |
|---|---|---|
| **API** | `svc_ansible@pve` PVE user + least-privilege role (`proxmox_permissions.yaml`) + an API token, written to `group_vars/proxmox_cluster/vars.yaml` + `vault.yaml`. Created once — `pmxcfs` replicates it cluster-wide. | Every Proxmox-facing project (Forgejo, NextCloud) — `proxmox_kvm`/`proxmox_lxc` API calls. |
| **SSH** | A Linux `svc_ansible` login account on every node in `[proxmox_nodes]`: key-only, NOPASSWD sudo scoped to `/usr/sbin/qm` and `/usr/sbin/pvesm` only, owner of the on-node image cache dir. | Only `create-template-linux.yaml` (`qm` over SSH). |

## Contents

- `create-pve_svc_user.yaml` — one-time, idempotent. Provisions the whole `svc_ansible` identity above (API token + per-node SSH account). Connects to the node(s) as a privileged admin whose SSH and sudo credentials it **prompts** for — nothing sensitive on the command line or in a file. The SSH account's `authorized_keys` is set to the same `sysadmin_ssh_public_key` string from `template_configuration.yaml`. Re-run to reconcile the role/user/ACL and the SSH side; the API token is left alone unless you pass `-e rotate_api_token=true`.
- `proxmox_permissions.yaml` — the least-privilege privilege list for the shared role (covers both VM and LXC provisioning). Edit it, then re-run `create-pve_svc_user.yaml`, to change what the account may do cluster-wide.
- `group_vars/proxmox_cluster/vars.yaml` — non-secret connection details (`proxmox_api_host`, `proxmox_api_token_id`). This repo is public and `proxmox_api_host` identifies your real cluster, so this file is gitignored — `create-pve_svc_user.yaml` generates it locally. `vars.yaml.example` (committed) documents its shape.
- `group_vars/proxmox_cluster/vault.yaml.example` — documents the one variable the real, encrypted `vault.yaml` defines (`vault_proxmox_api_token_secret`). The real `vault.yaml` is generated (and Vault-encrypted) by `create-pve_svc_user.yaml`, not written by hand — see `Proxmox-Forgejo/docs/ANSIBLE_VAULT_GUIDE.md` for how Ansible Vault works if you've never used it.
- `create-template-linux.yaml` — builds a hardened, cloud-init-ready Proxmox VM template (Debian 12/13, Ubuntu 24.04/26.04, Rocky 9/10, Arch; RHEL 9/10 are stubbed), usable by any project in this mono-repo — not specific to Forgejo. Builds one template per run; **only creates — never deletes or modifies a VM** (see "Building a VM template" below).
- `template_manifest.yaml` — committed source of truth for the `name → VMID → OS/version` mapping of every template the playbook can build. Templates are allocated VMIDs from 90000 up; adding one is a one-line append. Consuming projects copy a `name`/`vmid` pair from here.
- `create-templates_from_manifest.sh` — walks `template_manifest.yaml` and runs `create-template-linux.yaml` once per row, building the templates that are missing and skipping the ones that already exist. The "make all the base templates" entry point.
- `template_configuration.yaml` / `template_configuration_vault.yaml` — `create-template-linux.yaml`'s per-run config: which template to build (`template_target`, a name from the manifest), which node/storage/bridge to build it on, the `sysadmin` SSH key (also used for the `svc_ansible` SSH account). Real files are yours to create from the `.example` companions.

## Provisioning the shared account

```bash
cd Shared/Ansible
cp ansible.cfg.example ansible.cfg                                   # one-time; works as-is
cp inventory/hosts.ini.example inventory/hosts.ini                   # set your Proxmox node name(s) + address(es)
cp template_configuration.yaml.example template_configuration.yaml   # set sysadmin_ssh_public_key (+ node/storage/bridge if you'll build templates)
ansible-playbook create-pve_svc_user.yaml
```

You're prompted once for a privileged admin login on the node(s) in `[proxmox_nodes]` (root, or an account that can `sudo` to root — it needs `pveum`, `useradd`, and to write `/etc/sudoers.d`). Requires a vault password file already in place (this directory's `ansible.cfg` `vault_identity_list`; see `Proxmox-Forgejo/docs/ANSIBLE_VAULT_GUIDE.md` section 2). The generated `group_vars/proxmox_cluster/vault.yaml` is **gitignored** — even as ciphertext its header names your vault-id — so it stays local; re-run this playbook on each machine that needs the credential (or copy the file across out of band).

## How a project consumes the credential

A project's playbook pulls it in with a relative `vars_files:` include — not a symlink, so the dependency is visible and nothing is git-fragile:

```yaml
- hosts: localhost
  vars_files:
    - ../Shared/Ansible/group_vars/proxmox_cluster/vars.yaml
    - ../Shared/Ansible/group_vars/proxmox_cluster/vault.yaml
  module_defaults:
    group/community.proxmox.proxmox:
      api_host: "{{ proxmox_api_host }}"
      api_user: "{{ proxmox_api_token_id.split('!')[0] }}"
      api_token_id: "{{ proxmox_api_token_id.split('!')[1] }}"
      api_token_secret: "{{ proxmox_api_token_secret }}"
      validate_certs: false
```

## Building a VM template

```bash
cd Shared/Ansible
ansible-vault create template_configuration_vault.yaml               # see .example for the one variable it needs

ansible-playbook create-template-linux.yaml                          # builds template_target
ansible-playbook create-template-linux.yaml -e template_target=T-Rocky-10-Cloud
./create-templates_from_manifest.sh                                 # builds every template still missing
```

`template_target` names a row in `template_manifest.yaml`; the OS, version, final template name and VMID all come from that row. Template names are `T-<Os>-<Version>-<Source>[-<Variant>]` — `<Source>` is `Cloud` (this playbook, imports the vendor cloud image) or `ISO` (a separate Packer project, planned); a `-ISO` row makes this playbook fail fast. The node's build steps run `qm` over SSH as the `svc_ansible` account (passwordless sudo for `qm`/`pvesm` only) — see the comment in `inventory/hosts.ini`.

**Cloud images are cached on the node** in `template_image_cache_dir` (`/var/cache/vm-template-images` by default, created by `create-pve_svc_user.yaml`), each next to a `.checksum` sidecar. Before every build the playbook validates the cached image against its sidecar; a valid hit means the whole build runs with **no internet traffic**, so a corrupted template can be rebuilt offline. A cached image that fails validation is deleted and re-pulled with a fresh upstream checksum. `-e refresh_image_cache=true` forces a re-pull. The cache directory persists and is safe to `rm -rf` (it just re-downloads next run).

**The build network is a dedicated `/24`.** `template_build_subnet` names a VLAN that only this pipeline (and the planned ISO/Packer flow) ever touches — just-in-time outbound internet for a build VM, nothing on a production VLAN. The build VM's own address is **derived**, not configured: `<subnet prefix>.<(vmid − 90000) % 220 + 20>/24` (the `.20`–`.239` host range). Because template VMIDs are globally unique, any number of builds can run at once — 5–10 is a routine target for an automated pipeline — and each gets a distinct address with no DHCP server, no IPAM and no lock file. The address is delivered as a netplan-v2 cloud-init snippet via `qm set --cicustom` (Proxmox's `ipconfig0` only emits the legacy network-config v1, which current Ubuntu/Rocky/Arch cloud-init ignore), and both the snippet and the `--cicustom` reference are stripped before the VM is templatized. When a NetBox VM exists, the derivation is replaced by a NetBox allocation call and nothing else changes.

**The QEMU CPU model is pinned.** `qm create` passes `--cpu` (per-OS `cpu_type` from the playbook's `os_catalog`, default `x86-64-v2-AES`; Rocky/RHEL 10 need `x86-64-v3`; override with `template_cpu_type`). Proxmox's own default is `kvm64`, an x86-64-v1 baseline on which RHEL/Rocky 9+ kernels panic at boot. A pre-Haswell build host (no AVX2) cannot build the EL10 templates at all.

**This playbook only ever creates.** If anything already occupies the target VMID — a finished template, a half-built shell from a crashed run, an unrelated guest, or any VM named `T-*` that isn't a template — it stops with a message for you to resolve it by hand. Nothing is purged automatically. A direct run also fails fast if the target template already exists; `create-templates_from_manifest.sh` turns that into a skip so a batch can proceed.

Every template gets the same baseline hardening regardless of OS: `root` gets a random, high-entropy password and is forbidden from SSH entirely (console/noVNC access only, and only in a genuine emergency — see the playbook's own header comment); a `sysadmin` account is created with full NOPASSWD sudo, SSH restricted to key-only (no password-based interactive login for **any** account on the box, not just this one), and an initial console-only password you set in `template_configuration_vault.yaml`. `systemd-ssh-generator` is also masked by default (`template_mask_ssh_generator: true`) — none of these VMs ever get a vsock device, so that generator's boot-time probe only ever fails and logs noise; set it to `false` in `template_configuration.yaml` if you specifically want vsock-based local SSH.

Consuming projects (e.g. `Proxmox-Forgejo`) don't build templates themselves — they just point `vm_template_name`/`vm_template_vmid` at a `name`/`vmid` pair from `template_manifest.yaml`.

## Disk layout & growing a template's disks

Every template has **two disks**:

| disk | mount | size | holds |
|---|---|---|---|
| `scsi0` | `/` | `template_root_size` (default 16 G) | the OS only |
| `scsi1` | `/opt` | `template_opt_size_gb` (default 16 G) | `/opt/app` = applications, `/opt/data` = application data **and logs** |

`/opt` is a whole-disk filesystem (no partition table), `template_opt_fstype` (default `xfs`), mounted from `/etc/fstab` by `UUID=` with `defaults,nodev,nosuid,nofail,x-systemd.growfs` — deliberately **not** `noexec`, since `/opt/app` holds executables.

Neither disk can shrink (xfs never; ext4 only offline) — size **up**, never down.

### Grow `/` on a clone

```bash
qm disk resize <vmid> scsi0 +20G      # on the Proxmox node; then reboot the VM
```
The cloud image's own cloud-init `growpart`/`resizefs` expand the partition and filesystem on the next boot. To do it live without a reboot, in the guest:
```bash
sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1     # ext4 (Debian/Ubuntu/Arch)
sudo growpart /dev/sda 1 && sudo xfs_growfs /            # xfs (EL family)
```

### Grow `/opt` on a clone

```bash
qm disk resize <vmid> scsi1 +50G      # on the Proxmox node; then reboot the VM
```
`x-systemd.growfs` in the fstab entry runs `systemd-growfs@opt.service` on boot and expands the filesystem to the new disk size. No `growpart` step — it's a whole-disk filesystem. Live, in the guest:
```bash
sudo xfs_growfs /opt                  # xfs
sudo resize2fs /dev/sdb               # ext4
```

### Thin vs. thick provisioning

On an **LVM-thin** pool every volume is thin — there is no thick toggle, and `qm clone` can't add one. The declared 16 G disks cost almost nothing until data is written.

For a VM that needs **guaranteed space** or **consistent write latency** (production databases; anything where a full thin pool taking *every* VM on it read-only at once is unacceptable), clone that VM's disks onto a **non-thin** storage instead:
```bash
qm clone <template_vmid> <newid> --name <name> --full --storage <non-thin-pool>
```
(plain LVM, ZFS with `refreservation`, a directory store with `preallocation=full`, or Ceph RBD). Keep templates and ordinary homelab clones on LVM-thin.
