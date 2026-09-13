# Proxmox-Steam-Linux

Deploys headless Steam dedicated-game-servers (via **SteamCMD** — not the GUI Steam client; no desktop environment involved) onto a Proxmox VM, built on the same foundation as `Proxmox-Forgejo`:

- **Ansible only** — VM provisioning (`community.proxmox.proxmox_kvm`) and configuration both live in this repo.
- **VM (KVM), not LXC** — same local-storage-per-node rationale as `Proxmox-Forgejo`. See "Disaster Recovery" below.
- **One shared, cluster-wide Proxmox credential** in [`../Shared/Ansible/`](../Shared/Ansible/README.md) — the same `svc_ansible@pve` API token every Proxmox-facing project in this mono-repo uses.
- **No reverse proxy in front of game traffic.** Game servers speak raw UDP directly to players, which doesn't fit an HTTP(S)-terminating proxy model at all — `ufw` opens each instance's UDP port directly (default source `0.0.0.0/0`, since a game server is meant to be reachable by the public/your players, not funneled through internal infrastructure). This is a deliberate, meaningfully different ingress posture from every other project in this repo, not an oversight.
- **Ansible Vault for every secret that exists.** Phase A (see below) currently has none — anonymous SteamCMD login needs no credential — so there's no project-local `vault.yaml` yet. See "Known limitations" for when that changes.
- **`.yaml` everywhere a file is actually YAML.**

## Two playbooks

This project is deliberately split into two playbooks with different jobs and different lifecycles:

1. **`create-steam_linux.yaml`** — provisions the *base host*: clones the shared template, applies cloud-init/sizing, installs SteamCMD and the 32-bit runtime dependencies most dedicated servers need. Ends with a working host and **no game-server instance running**. This is the part that talks to the Proxmox API.
2. **`create-steam_gameserver.yaml`** — installs/updates **one** game-server instance (any Steam AppID) onto an already-provisioned host, entirely over SSH. Fully generic and data-driven: everything game-specific — AppID, launch args, port, which config role to layer on top — comes from an instance vars file passed with `-e @<path>` (see [`gameservers/hlds-dm01.vars.yaml`](gameservers/hlds-dm01.vars.yaml) for a real, ready-to-use example). It makes **no Proxmox API calls at all** — nothing about it is tied to Proxmox specifically, which is deliberate: it's the reusable "install this game server on this already-running node" building block a future orchestration layer could call repeatedly (see "Known limitations / next steps").

`create-steam_linux.yaml` persists the VM it creates into this project's own static inventory (`inventory/host_vars/<hostname>.yaml` + `inventory/hosts.ini`) specifically so `create-steam_gameserver.yaml` — a separate `ansible-playbook` invocation, run whenever you want to add/update an instance — can find and target it without re-running VM creation.

## Prerequisites

1. A Proxmox cluster reachable from wherever you run this. `Install-Prerequisites.sh` checks the rest of this list for you.
2. **This repo is public — copy every `.example` config file to its real name and fill in your own values before anything else.** The real files are gitignored so your cluster/node names and storage/bridge names never end up committed:
   ```bash
   cp ../Shared/Ansible/ansible.cfg.example ansible.cfg
   cp inventory/hosts.ini.example inventory/hosts.ini
   cp inventory/group_vars/steam_linux/vars.yaml.example inventory/group_vars/steam_linux/vars.yaml
   ```
   Then edit each real file, replacing every `REPLACE_ME` placeholder. `ansible.cfg` comes from the one canonical example in [`../Shared/Ansible/`](../Shared/Ansible/ansible.cfg.example) and works as-is.
3. **The shared node/storage/template/backup config** at [`../Shared/Ansible/group_vars/proxmox_pve1/`](../Shared/Ansible/group_vars/proxmox_pve1/vars.yaml.example) — one value per cluster (which node, storage pool, the shared VM template, off-node backup target), used by every Proxmox-facing project in this mono-repo, not just this one:
   ```bash
   cp ../Shared/Ansible/group_vars/proxmox_pve1/vars.yaml.example ../Shared/Ansible/group_vars/proxmox_pve1/vars.yaml
   ```
   Skip this step if another project already set it up — it's shared, not per-project. `network_bridge`/`network_vlan_tag` are **not** here; they're project-local (step 2 above), since a game-server host's bridge/subnet needs can differ from other projects'.
4. The shared Proxmox credential set up (once per cluster, not once per project) by `create-pve_svc_user.yaml`:
   ```bash
   cd ../Shared/Ansible
   ansible-playbook create-pve_svc_user.yaml
   ```
5. A vault password file at `~/.ansible/vault_pass_homelab.txt` — see the [Ansible Vault guide](../Shared/Ansible/docs/ANSIBLE_VAULT_GUIDE.md) if you've never done this. This project has no vault file of its own yet (see above), but the *shared* cluster credential is still vault-encrypted, so this is still required.
6. **An off-node backup storage target already configured in Proxmox** — see "Disaster Recovery." Set `backup_storage_target: "none"` in `../Shared/Ansible/group_vars/proxmox_pve1/vars.yaml` to explicitly defer this for testing (`proxmox_preflight` turns the check into a loud warning instead of blocking you).

## Quick start

```bash
./Deploy.sh
```

This runs `Install-Prerequisites.sh`, generates an SSH keypair under `ssh_keys/` if one doesn't exist, then runs `create-steam_linux.yaml` (playbook one — the base host only). Once it finishes, deploy the HLDS deathmatch validation instance separately:

```bash
ansible-playbook create-steam_gameserver.yaml \
  -e @gameservers/hlds-dm01.vars.yaml
```

Neither playbook has interactive prompts — both work the same from cron or CI once the prerequisites above are met.

## What it does

1. **Preflight** (`proxmox_preflight`) — validates the target node, storage pools, network bridge, and off-node backup target exist, and that `steam_linux_hostname` isn't already taken. This project does **not** build its own VM template — see [`../Shared/Ansible/create-template-linux.yaml`](../Shared/Ansible/README.md).
2. **VM creation** (`create_steam_vm`) — clones the template over the API, applies cloud-init (SSH key, sizing, network), resizes **both** disks (`scsi0` root and `scsi1` `/opt` — unlike `Proxmox-Forgejo`, this host is meant to grow multiple game-server installs over time), starts it, waits for SSH, and persists it into this project's static inventory.
3. **Base configuration** (`steam_prereqs`, `steamcmd_install`, `steam_base_verify`) — 32-bit (`i386`) multiarch support, base packages, a dedicated non-root `steam` system user, SteamCMD itself (downloaded directly from Valve — see "Known limitations" on checksum verification), and a check that the host is ready to receive an instance.
4. **Instance deployment** (`create-steam_gameserver.yaml`, run separately) — `steam_gameserver_instance` installs/updates the AppID and renders its systemd unit and firewall rule; a game-specific config role (`hlds_dm_config` for the Phase A validation instance) layers on the actual game config; `steam_gameserver_verify` confirms the service is active and its UDP port is bound.

## Disk layout

Both disks come from the shared two-disk template ([`../Shared/Ansible/README.md`](../Shared/Ansible/README.md)); this project clones it (`full: true`) and inherits them, then resizes both.

| Path | Disk | Holds |
|---|---|---|
| `/` | `scsi0` | OS only. `create_steam_vm` grows it to `steam_disk_size` GiB. |
| `/opt/app/steamcmd` | `scsi1` (`/opt`) | The shared SteamCMD tool (one install, used by every instance). |
| `/opt/data/steam/<instance-name>/` | `scsi1` (`/opt`) | One directory per game-server instance — repeat this row per instance. `create_steam_vm` grows the whole disk to `steam_opt_disk_size` GiB up front. |

Grow either disk further, live, with the shared playbook:

```bash
cd ../Shared/Ansible
ansible-playbook update-vm_disk-grow.yaml \
  -e VMID=<vmid> -e blockdev=/dev/sdb -e size=+20G \
  -e grow_ssh_user=<steam_deploy_user> -e grow_ssh_key=../Proxmox-Steam-Linux/ssh_keys/id_ed25519
```

## Disaster recovery: surviving a node's hardware failure

Same story as `Proxmox-Forgejo`: storage in this environment is local-only per node today, so a backup stored on the same node it's protecting does not survive that node's hardware failure — off-node backup storage is a stated prerequisite, not something this project provisions itself.

- **Simplest — no Ansible involved:** register the Steam-Linux VM's VMID in Proxmox's own **Datacenter → Backup** scheduled job, pointed at the off-node storage.
- **Ansible-driven:** `ansible-playbook create-steam_linux_backup.yaml -e steam_vm_vmid=<vmid>`, wrapping `community.proxmox.proxmox_backup`. This backs up the whole VM (base host + every instance under `/opt/data/steam/`) at once — there's no per-instance backup.

Restore-to-another-node (`qmrestore`) is the actual "move to another node" runbook, same as `Proxmox-Forgejo` — not live migration, since no shared storage spans nodes yet.

## Verification checklist

- `ansible-playbook create-steam_linux.yaml --syntax-check`
- `ansible-playbook create-steam_gameserver.yaml --syntax-check -e @gameservers/hlds-dm01.vars.yaml` — the instance vars file is required even just to syntax-check this playbook, since Ansible resolves a role's name (`steam_gameserver_config_role`) before evaluating its `when:`
- Re-run `create-steam_linux.yaml` — `create_steam_vm`, `steamcmd_install` should report `changed=0` on the second pass (double check this empirically; `changed_when: false` on a command that legitimately changes state sometimes is worth verifying live, not just trusting the code)
- On the Proxmox host: VM visible with correct VMID/resources; `ufw status` on the VM shows `27015/udp` open
- Inside the VM: `dpkg --print-foreign-architectures` includes `i386`; `ldconfig -p | grep i386` shows the 32-bit libs; `/opt/app/steamcmd/steamcmd.sh` and `/opt/data/steam/hlds-dm01/valve/server.cfg` exist; `systemctl status steam-hlds-dm01` is `active (running)`; `ss -uln | grep 27015` shows the bound socket
- Connect with an actual Half-Life/GoldSrc client (or a headless A2S_INFO query tool) from **outside** the VM's own host, confirm it responds with the expected hostname/map/player-slot count, and observe the map actually rotate after 10 minutes (`mp_timelimit`) — this last part needs a real timed observation, not just a config-file read
- Disaster-recovery drill: restore the latest backup to a different node, confirm the service comes back up healthy there

## Known limitations / next steps

- **This two-phase design is an interim/testing solution, not the end state — and its actual goal has been met.** The point of Phase A was never HLDS or Valheim specifically; it was to prove the underlying design (VM provisioning, generic per-instance SteamCMD install, systemd/ufw management) against a real game, on a real server, with real players connecting over the internet, before investing in a general fleet-management mechanism. That's done: Valheim ran a live session with 5 concurrent real players connecting from the internet, and the server performed well. The generalized "add/remove/update arbitrary AppID game servers" mechanism (Phase B) is **structurally already in place** — `steam_gameserver_instance` is written with zero game-specific knowledge for exactly this reason, proven against two differently-shaped games (HLDS, Valheim) — but not yet wired into a data-driven multi-instance mechanism. Getting there is mostly additive: a `steam_gameservers` list var, and `update-`/`delete-steam_gameserver.yaml` playbooks alongside the existing `create-steam_gameserver.yaml` (which already doubles as "update" — SteamCMD's `app_update` is naturally idempotent-in-place). Each new distinct game gets its own small `<game>_config` role mirroring `hlds_dm_config`'s shape.
- **A more formal management solution is planned.** `create-steam_gameserver.yaml`'s Proxmox-independence (pure SSH/systemd against a reachable host) is deliberate groundwork for it: a fleet-management layer for "Steam Engines" (this project's game-server hosts — see the `engine-1` hostname convention) that will ultimately cover both Linux and Windows engines, not just this project's Linux/SteamCMD scope. Nothing here builds that; this project only keeps the instance-deploy interface clean enough that something else could drive it later.
- **Vaulted per-game credentials and Steam Guard/2FA are unsolved.** Anonymous login (Phase A) covers HLDS and a fair number of other dedicated servers, but any game requiring a real, entitled Steam account reintroduces the vault machinery this project currently has none of, plus SteamCMD's interactive Steam Guard prompt — which has no clean, idempotent, non-interactive Ansible automation path today.
- **No licensed-game entitlement check.** `app_update` on an AppID the configured account doesn't own simply fails; there's no preflight check for this.
- **No per-instance disk-space planning.** `steam_opt_disk_size` is a single up-front number; nothing tracks how much of it successive instances consume. Grow `/opt` manually (`update-vm_disk-grow.yaml`) as instances accumulate.
- **No checksum verification on the SteamCMD download** — Valve doesn't publish one for `steamcmd_linux.tar.gz`, unlike `Proxmox-Forgejo`'s GitHub-release checksums. HTTPS transport security is the only integrity guarantee here.
- **No rcon password configured** for the Phase A instance — HLDS's rcon is simply inert. Set one manually (or via a future vault entry) if remote admin access becomes worth the added secret-handling machinery.
