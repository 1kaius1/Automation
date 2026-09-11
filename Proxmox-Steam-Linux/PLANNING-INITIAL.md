# Proxmox-Steam-Linux: SteamCMD dedicated-game-server deployment

## Context

`Proxmox-Steam-Linux/` currently exists as an empty directory. The goal is to
build it on the same foundation as `Proxmox-Forgejo/` — clone the shared
`T-Debian-13-Cloud` template, configure over Ansible, use the shared
cluster-wide Proxmox credential and Vault tooling from `Shared/Ansible/` — but
for a fundamentally different workload: headless dedicated game servers
managed via **SteamCMD** (not the GUI Steam client — confirmed with the user;
no desktop environment, no streaming stack).

The user's stated goal is two-phase:
- **Phase A (build now)**: prove the base VM + SteamCMD pipeline end-to-end by
  installing HLDS (Half-Life Dedicated Server, Steam AppID 90, anonymous
  login) running a standard deathmatch map rotation with a 10-minute
  `mp_timelimit`.
- **Phase B (design only, not built)**: a general, data-driven mechanism to
  add/remove/update arbitrary Steam AppID game servers on an already-deployed
  Steam-Linux VM. Phase A's roles are deliberately shaped so this is additive
  work later, not a rewrite.

This plan covers building Phase A completely and documenting Phase B's design
in the project's README as forward-looking intent (mirroring how this repo's
existing stub projects state "Planned" work), consistent with CLAUDE.md's
convention that undone work is documented, not half-implemented.

## Key precedent: Proxmox-Forgejo

Forgejo is the model to mirror structurally. Confirmed patterns to reuse
as-is:
- Non-interactive `Deploy.sh` → `Install-Prerequisites.sh` → main playbook,
  wiring the repo-root `.venv`/`.ansible/collections` built by
  `Shared/Ansible/bootstrap.sh`.
- Three-play main playbook: (1) `proxmox_preflight` on `localhost`, (2) VM
  clone/cloud-init/boot on `localhost`, (3) app configuration on the
  dynamically-added inventory group. Every play repeats its own
  `vars_files:`/`module_defaults:` block (plays don't inherit them).
- Consuming the **shared** `svc_ansible@pve` credential via
  `../Shared/Ansible/group_vars/proxmox_cluster/{vars,vault}.yaml` —
  **do not** build a project-local `setup_proxmox_api.yaml`/
  `proxmox_permissions.yaml` (that's the old NextCloud pattern currently being
  deleted/refactored away).
- Clone `T-Debian-13-Cloud` (vmid `90001` in
  `Shared/Ansible/template_manifest.yaml`) via `community.proxmox.proxmox_kvm`
  — full clone, then a second `update_unsafe: true` call for cloud-init/net0
  re-pointing (**critical**: the template's NIC defaults to the shared build
  VLAN), then `community.proxmox.proxmox_disk` resize (size **must** have a
  `G` suffix — a bare number is misread as a shrink and fails), start, pause,
  resolve IP (static parsed directly or DHCP polled via
  `community.proxmox.proxmox_vm_info` + guest-agent), `wait_for` port 22, a
  real SSH probe, `add_host` with `cacheable: yes` facts for the next play.
- `.example`/real-gitignored file split for every site-specific config;
  secrets via the standard `vars.yaml`/`vault.yaml` split (`vault.yaml` itself
  gitignored, even encrypted, since its ciphertext header names a real
  vault-id label).
- One canonical `ansible.cfg.example` at `Shared/Ansible/` — adding a project
  means adding its `# ===== <Project> =====` section there, not creating a
  per-project example file.

Reference files already read in full: `Proxmox-Forgejo/deploy_forgejo.yaml`,
`roles/create_forgejo_vm/tasks/main.yaml`, `roles/proxmox_preflight/tasks/main.yaml`,
`roles/forgejo_prereqs/tasks/main.yaml`, `README.md`.

## Design decisions for Steam-Linux

| Decision | Choice | Why |
|---|---|---|
| Inventory group | `steam_linux` | Mirrors `forgejo` group naming. |
| Main playbook filename | `create-steam_linux.yaml` | CLAUDE.md's CRUD-prefix rule is the actual documented convention; Forgejo's `deploy_forgejo.yaml` is a known, called-out exception, not a pattern worth propagating into a brand-new project. |
| Backup playbook | `create-steam_linux_backup.yaml` | Same CRUD-prefix reasoning; wraps `community.proxmox.proxmox_backup` like `backup_forgejo.yaml` does. |
| System service user | `steam` (no-login shell, home `/opt/data/steam`) | Mirrors Forgejo's `git` user. |
| Cloud-init deploy user | `steam-deploy` | Mirrors `forgejo-deploy`. |
| Phase A instance name | `hlds-dm01` | Given directly by the user. |
| Ingress model | **No reverse proxy** — `ufw` opens each instance's UDP port directly, default source `0.0.0.0/0` | Game UDP traffic doesn't fit Forgejo's HTTP(S)-terminating-proxy ingress model at all. This is a deliberate, stated difference from every other project in the repo — document it in the README the same way Forgejo states its own ingress opinion. |

### Critical fold-in call: `steam_gameserver_instance` is generic from day one

Rather than writing an HLDS-specific role now and generalizing later, Phase A
builds one **generic**, data-driven role (`steam_gameserver_instance`,
namespaced vars like `steam_gameserver_instance_name/appid/launch_binary/
launch_args/port/source_cidr`) that installs any AppID via SteamCMD, renders a
parameterized systemd unit, and opens its ufw rule — with zero HLDS-specific
content anywhere in its tasks or templates. A separate, small
`hlds_dm_config` role layers HLDS's own `server.cfg`/`mapcycle.txt` on top
(the pattern every future game's own `<game>_config` role would follow in
Phase B). This is what makes Phase B additive: it becomes "loop this same
role over a `steam_gameservers` list var" instead of a rewrite.

## Files to create

```
Proxmox-Steam-Linux/
  ansible.cfg (gitignored, copied from ../Shared/Ansible/ansible.cfg.example)
  .gitignore
  CHANGELOG.md
  README.md
  requirements.yaml                    # community.proxmox>=1.5.0, community.general>=8.0.0
  Deploy.sh
  Install-Prerequisites.sh
  create-steam_linux.yaml              # main deploy playbook, 3 plays
  create-steam_linux_backup.yaml       # standalone on-demand VM backup
  ssh_keys/{id_ed25519, id_ed25519.pub}  (gitignored, generated by Deploy.sh)
  inventory/
    hosts.ini (gitignored) / hosts.ini.example
    host_vars/.gitkeep
    group_vars/
      all/vars.yaml                    # ssh key paths, ansible_python_interpreter
      proxmox_pve1/{vars.yaml(gitignored), vars.yaml.example}
      steam_linux/{vars.yaml(gitignored), vars.yaml.example}
        # No vault.yaml in Phase A — anonymous SteamCMD login needs no
        # secret. Phase B (real Steam account logins) is what introduces one.
  roles/
    proxmox_preflight/{defaults,tasks}/main.yaml
    create_steam_vm/{defaults,tasks}/main.yaml
    steam_prereqs/{defaults,tasks}/main.yaml
    steamcmd_install/{defaults,tasks}/main.yaml
    steam_gameserver_instance/{defaults,tasks,handlers}/main.yaml
      templates/steam-gameserver.service.j2
    hlds_dm_config/{defaults,tasks,handlers}/main.yaml
      templates/{server.cfg.j2, mapcycle.txt.j2}
    steam_verify/{defaults,tasks}/main.yaml
    steam_backup/{defaults,tasks}/main.yaml
```

## Role task sequences

**`proxmox_preflight`** — same `_info`-module-backed checks as Forgejo's
(node/storage/backup-target/template exist, template is actually a template,
`network_bridge` set and non-placeholder via `assert`, DNS required if static
IP, bridge visible on node as a non-fatal warning, hostname not already
taken). Drop Forgejo's reserved-admin-username check — there's no admin web
UI account here to collide with anything.

**`create_steam_vm`** — same 16-task clone/cloud-init/boot/SSH-wait sequence
as `create_forgejo_vm`, with two deviations justified by hosting *multiple
future* game servers rather than one app:
- Resize **both** `scsi0` (root, default 20G) **and** `scsi1` (`/opt`, new var
  `steam_opt_disk_size`, default 60G) — Forgejo never touches `scsi1` because
  one app fits the template's 16G default; several Source-engine servers
  would not. Same `G`-suffix gotcha applies to both resize tasks.
- Default sizing `steam_cores: 2`, `steam_memory: 4096` — modest headroom for
  more than one instance from day one.

**`steam_prereqs`** — apt update + base packages (`curl`, `ca-certificates`,
`tzdata`, `ufw`; no `git`), idempotently enable the `i386` foreign
architecture (`dpkg --print-foreign-architectures` check before adding, only
re-`apt update` if it was just added), install 32-bit runtime deps
(`lib32gcc-s1`, `lib32stdc++6`, `libc6-i386` — both `steamcmd` and
`hlds_run`/`hlds_i686` are 32-bit binaries), create the dedicated `steam`
system user/group (no-login shell, mirrors Forgejo's `git` user), pre-create
its `~/.ansible/tmp` (same `become_user` fragility mitigation Forgejo
documents), create `/opt/app/steamcmd` (root-owned, shared tool) and
`/opt/data/steam` (steam-owned, parent of all instance directories), baseline
`ufw` (allow 22, default deny incoming/allow outgoing, enable — **no game
port opened here**, since no instance exists yet at prereqs time; each
instance opens its own port when created).

**`steamcmd_install`** — download `steamcmd_linux.tar.gz` (only if not
already present) from Valve's standard installer URL, `unarchive` into
`/opt/app/steamcmd`, run `steamcmd.sh +quit` once as `become_user: steam` to
self-update (`changed_when: false` — SteamCMD's own update state isn't
something Ansible can detect cleanly). Explicitly no checksum verification:
Valve doesn't publish one for this tarball (unlike Forgejo's GitHub-release
checksums) — document this as an accepted, real limitation, not an oversight
to silently paper over with a fabricated checksum.

**`steam_gameserver_instance`** (generic — see design decision above) —
`assert` all required vars are set, create
`/opt/data/steam/{{ instance_name }}`, install/update the AppID via SteamCMD
(`steamcmd.sh +force_install_dir <dir> +login anonymous +app_update <appid>
[validate] +quit`, `become_user: steam`, `changed_when: false`), render
`steam-gameserver.service.j2` → `/etc/systemd/system/steam-{{ instance_name
}}.service` (parameterized `WorkingDirectory`/`ExecStart`/`User=steam`,
`Restart=on-failure` — no game-specific content), `community.general.ufw`
allow `{{ port }}/{{ proto }}` from `{{ source_cidr }}`, `daemon_reload` +
start/enable the unit.

**`hlds_dm_config`** (HLDS-specific, Phase A only) — renders
`server.cfg.j2`/`mapcycle.txt.j2` into `{{ install_dir }}/valve/` (HLDS's
mod-relative config path — not the install root), notifies a restart handler.

- `mapcycle.txt.j2` loops the 7 stock HLDS DM maps: `crossfire`, `datacore`,
  `stalkyard`, `snark_pit`, `boot_camp`, `subtransit`, `undertow`.
- `server.cfg.j2` sets `hostname`, `mp_timelimit {{ hlds_dm01_timelimit }}`
  (10), `mp_fraglimit 0`, `mp_friendlyfire 0`, `sv_lan 0`,
  `mp_mapcyclefile "mapcycle.txt"`, logging on. `maxplayers` is deliberately
  set via the **launch command** (`+maxplayers`), not `server.cfg` — GoldSrc
  needs it resolved before the first map spawns. `rcon_password` is
  deliberately left unset (no remote admin in Phase A — flagged in README
  limitations rather than introducing Vault for one cvar).

**`steam_verify`** — `systemctl is-active steam-hlds-dm01` (same pattern as
`forgejo_verify`), then a retried `ss -uln` check that the UDP port is
actually bound (since `wait_for` doesn't support UDP), plus a best-effort
`journalctl` tail surfaced in the final debug summary for manual inspection
(not asserted against a specific string — no confidently-verified GoldSrc
startup log line to gate on yet; capture the real one from a live deploy and
harden this check in a follow-up).

**`steam_backup`** — mirrors `forgejo_backup`, wraps
`community.proxmox.proxmox_backup` against `steam_vm_vmid`/
`backup_storage_target`, invoked by `create-steam_linux_backup.yaml`.

## Top-level playbook: `create-steam_linux.yaml`

Three plays mirroring `deploy_forgejo.yaml`:
1. `hosts: localhost` — `proxmox_preflight`.
2. `hosts: localhost` — `create_steam_vm`, caches `steam_vm_ip`/`steam_vm_vmid`.
3. `hosts: steam_linux` — pulls VM facts back via `hostvars['localhost']`,
   sets Phase A's instance vars as play vars (mapping `hlds_dm01_*` group_vars
   onto the generic `steam_gameserver_instance_*` names — this mapping is
   exactly what a Phase B loop would generate per list item instead of
   writing once by hand), runs `steam_prereqs` → `steamcmd_install` →
   `steam_gameserver_instance` → `hlds_dm_config` → `steam_verify` in order.

## `inventory/group_vars/steam_linux/vars.yaml` (plaintext, no vault in Phase A)

`steam_linux_hostname`, `steam_deploy_user`, VM sizing
(`steam_cores`/`steam_memory`/`steam_disk_size`/`steam_opt_disk_size`),
`steam_ip_config`/nameservers, and the Phase A instance block:
`hlds_dm01_appid: 90`, `hlds_dm01_port: 27015`, `hlds_dm01_hostname`,
`hlds_dm01_maxplayers: 16`, `hlds_dm01_timelimit: 10`, `hlds_dm01_maplist`
(the 7 maps above), plus `steam_game_source_cidr: "0.0.0.0/0"` (overridable
for LAN-only testing). Comment header explicitly notes why no vault split
exists yet.

## Documentation updates

- `Proxmox-Steam-Linux/README.md` — same structure as Forgejo's (opinions,
  prerequisites, quick start, what-it-does, disk layout, disaster recovery,
  verification checklist), with the ingress-model opinion above stated
  explicitly, and a "Known limitations / next steps" section carrying the
  Phase B design summary: `steam_gameservers` data-driven list,
  `create-/update-/delete-steam_gameserver.yaml` CRUD playbooks reusing
  `steam_gameserver_instance`, one `<game>_config` role per new game
  mirroring `hlds_dm_config`; explicitly flagging vaulted per-game Steam
  account credentials and Steam Guard/2FA automation, licensed-game
  entitlement checks, and per-instance disk-space planning as unresolved.
- `Proxmox-Steam-Linux/CHANGELOG.md` — `[Unreleased]` → `### Added`, listing
  the initial project, playbooks, and roles (narrative style matching
  Forgejo's changelog entries).
- Root `README.md` — new table row for `Proxmox-Steam-Linux/`.
- Root `CHANGELOG.md` — one cross-cutting `### Added` entry: "New project:
  `Proxmox-Steam-Linux` — Ansible-based SteamCMD dedicated-game-server
  deployment on Proxmox."
- `Shared/Ansible/ansible.cfg.example` — append a
  `# ===== Proxmox-Steam-Linux =====` placeholder section, per that file's
  own stated convention.
- `Shared/Ansible/README.md` — update the list of consuming projects to
  include Steam-Linux.

## Decisions made without further user input (low-stakes, easily adjusted)

- Include `steam_backup`/`create-steam_linux_backup.yaml` in the initial
  commit for parity with the repo's established per-VM backup pattern.
- Omit `inventory/group_vars/steam_linux/vault.yaml(.example)` entirely in
  Phase A rather than shipping an empty placeholder — nothing exists yet to
  encrypt; Phase B introduces it when real Steam account credentials are
  needed.

## Verification

- `ansible-playbook create-steam_linux.yaml --syntax-check`
- Full run, then re-run: `create_steam_vm`, `steamcmd_install`, and
  `steam_gameserver_instance` should report `changed=0` on the second pass —
  confirm this empirically, since a `changed_when: false` on a command that
  legitimately changes state sometimes is worth double-checking live, not
  just trusting the code.
- On the Proxmox host: VM visible with correct VMID/resources; `ufw status`
  on the VM shows `27015/udp` open from the expected source.
- Inside the VM: `dpkg --print-foreign-architectures` includes `i386`;
  `ldconfig -p | grep i386` shows the 32-bit libs; `/opt/app/steamcmd/steamcmd.sh`
  and `/opt/data/steam/hlds-dm01/valve/server.cfg` exist with expected
  content; `systemctl status steam-hlds-dm01` is `active (running)`;
  `ss -uln | grep 27015` shows the bound socket.
- **Real end-to-end proof**: connect with an actual Half-Life/GoldSrc client
  (or a headless A2S_INFO query tool) from outside the VM's host, confirm the
  server responds with the expected hostname/map/player-slot count, and
  observe the map actually rotate after 10 minutes — this last part needs a
  real timed observation, not just a config-file read.
- Disaster-recovery drill: restore the latest backup to a different node,
  confirm the service comes back up healthy there.
