# PLAN — Refactor Proxmox-NextCloud, then split out Proxmox-Collabora

Working plan for the NextCloud/Collabora refactor, tracked on
`feat/nextcloud-vm-rewrite` so it survives across sessions and
workstations. Covers both phases of the refactor; only Phase 1
(`Proxmox-NextCloud`) is in scope for this branch.

## Context

Repo cleanup is complete; `master` (`fc18e7e`) now carries the formal git
workflow this plan follows: `.claude/rules/git-workflow.md`
(feature-branch+PR only, Conventional Commits, no AI attribution ever,
`Shared/` changes sequenced as their own prior PR, confirm before deleting
files, flag new dependencies) and `CLAUDE.md`'s Idempotency rule (verify
`changed=0` on a second run, not just that the first run succeeds) and its
rule against ever letting decrypted Vault content hit a log/shell history.

Both phases were previously planned and approved in concept: NextCloud
rebuilt onto the `Proxmox-Forgejo`/`Proxmox-Steam-Linux` shape (VM not
LXC/container, MariaDB, nginx+PHP-FPM, shared credential + Vault,
non-interactive playbook, fronted by the existing shared reverse proxy),
with Collabora split into its own top-level project rather than bundled in
— tightly-coupled components aside, each top-level thing here is its own
project.

## Phase 1 — Proxmox-NextCloud rewrite (this branch)

### What's being replaced and why

Current `Proxmox-NextCloud/` is an early LXC+Docker+Apache prototype:
interactive (`vars_prompt`-driven), no Vault, Collabora bundled in via
Docker. None of the opinions already established for this project apply
yet. This phase replaces it wholesale with the Forgejo/Steam-Linux shape.

### Files to delete (confirmed, nothing here is reused)

- `roles/create_nextcloud_container/`, `roles/create_collabora_container/`
- `roles/configure_nextcloud/`, `roles/configure_collabora/` (Collabora's
  Docker role goes away entirely — becomes its own project in Phase 2, not
  carried forward even as a stub)
- `test_hybrid_config.sh`, `test_minimal.yaml`
- `Prerequistes.sh` (typo'd name, replaced by `Install-Prerequisites.sh`)
- `config.yaml.example` (replaced by `inventory/group_vars/nextcloud/*`)
- `inventory/hosts.ini` (replaced by `inventory/hosts.ini.example`)
- `group_vars/.gitkeep` (flat `group_vars/` dir goes away entirely)
- `deploy_nextcloud.yaml` content fully replaced, not appended to

`CHANGELOG.md` and `ansible.cfg.example` (already rewritten in the earlier
merged migration commit, PR #3) are kept and extended.

### New structure (mirrors Proxmox-Forgejo)

```
Proxmox-NextCloud/
├── deploy_nextcloud.yaml         # 3 plays: preflight / create VM / configure
├── backup_nextcloud.yaml         # standalone on-demand vzdump
├── Deploy.sh, Install-Prerequisites.sh
├── requirements.yaml             # community.proxmox, community.general, community.mysql
├── ansible.cfg.example           # already exists, kept
├── CHANGELOG.md, README.md
├── docs/reverse-proxy.nginx.conf.example
├── inventory/
│   ├── hosts.ini.example
│   ├── group_vars/
│   │   ├── all/vars.yaml
│   │   ├── proxmox_pve1/vars.yaml.example
│   │   └── nextcloud/{vars.yaml.example, vault.yaml.example}
│   └── host_vars/.gitkeep
└── roles/
    ├── proxmox_preflight/
    ├── create_nextcloud_vm/      # resizes BOTH scsi0 and scsi1, unlike Forgejo
    ├── nextcloud_prereqs/        # packages, www-data dirs, ufw
    ├── nextcloud_database/       # MariaDB + db/user (community.mysql)
    ├── nextcloud_install/        # checksum download, occ bootstrap, nginx vhost, PHP-FPM tuning, cron timer
    ├── nextcloud_verify/         # service status + status.php check
    └── nextcloud_backup/         # vzdump wrapper, like forgejo_backup
```

### Role decisions

- **proxmox_preflight** — copy Forgejo's real API-backed checks (node,
  storage, backup target, template, bridge, DNS-if-static, hostname
  collision). Drop the Forgejo-specific reserved-admin-username check (not
  meaningful for NextCloud's admin account).
- **create_nextcloud_vm** — like create_forgejo_vm, but resizes scsi0
  (`nextcloud_disk_size`, default 20G, matches Forgejo) AND scsi1
  (`nextcloud_data_disk_size`, default 200G, carried over from the old
  config default) — this project's whole point is user file storage, so
  the data disk needs to actually grow at deploy time, unlike Forgejo
  where `/opt` growing later is fine.
- **nextcloud_prereqs** — nginx, php-fpm + required extensions (mysql, gd,
  curl, mbstring, intl, bcmath, gmp, imagick, xml, zip, apcu), MariaDB
  client libs, unzip/bzip2, ufw. Runs as **www-data** (standard NextCloud
  convention) — no dedicated system user like Forgejo's, since NextCloud
  is a PHP-FPM app, not a single static binary running its own systemd
  unit. Stock Debian 13 PHP (8.3), no third-party repo (sury/ondrej) —
  simpler, no added repo dependency; documented as a real version
  constraint (Debian's PHP version bounds which NextCloud majors are
  installable), not hidden.
- **nextcloud_database** — MariaDB install/enable, a dropped-in
  `/etc/mysql/mariadb.conf.d/` file (utf8mb4 default charset/collation,
  `transaction_isolation = READ-COMMITTED`, `binlog_format = ROW` — all
  NextCloud-recommended) rather than `lineinfile`-editing the main conf
  (cleaner for MariaDB's actual conf.d convention — a deliberate small
  deviation from Forgejo's Postgres approach), then
  `community.mysql.mysql_user` / `mysql_db` for the app database.
  Local-socket admin auth only, password auth for the app user over
  loopback only — same shape as forgejo_database otherwise.
- **nextcloud_install** — checksum-verified download of the NextCloud
  release (`.tar.bz2` + published `.sha256`) into a versioned dir under
  `/opt/app/nextcloud`, symlinked as `current` (same versioned-symlink
  pattern as Forgejo's binary). **config.php is not hand-templated** —
  NextCloud computes its own instance ID/secret/salt at install time and
  idiomatically expects `occ` for config changes, so: `occ
  maintenance:install` (idempotent — skipped if already installed, checked
  via `occ status`) does the real bootstrap (db, admin, data dir at
  `/opt/data/nextcloud`), then `occ config:system:set` calls apply
  `overwrite.cli.url`, `overwriteprotocol=https`, `trusted_proxies`,
  `trusted_domains`, and `memcache.local => \OC\Memcache\APCu`. Also
  renders: the local nginx vhost (HTTP only — TLS terminates at the shared
  proxy, exactly like Forgejo), a PHP-FPM pool/ini drop-in (upload limits,
  `memory_limit`, `max_execution_time`, opcache tuning — NextCloud's stock
  PHP defaults are unusable for a file-sync app), and a systemd
  service+timer running `php -f cron.php` as `www-data` every 5 minutes
  (NextCloud's own recommended replacement for webcron/AJAX cron), set via
  `occ background:job:mode cron`.
- **nextcloud_verify** — mirrors forgejo_verify: services active (mariadb,
  php-fpm, nginx), local `status.php` returns `installed:true`, `occ
  status` clean.
- **nextcloud_backup** — near-verbatim forgejo_backup copy (vzdump to
  `backup_storage_target`, same off-node-only DR story); README notes the
  off-node target needs sizing for both disks, data disk included.

### Reverse proxy — correcting one earlier assumption

NextCloud's desktop-sync feature does NOT need extra ports through the
shared proxy the way Forgejo needs a raw-TCP stream for git-SSH: desktop
and mobile sync clients speak WebDAV over the same HTTPS endpoint as the
web UI (port 443 only). The only proxy-side things that matter are
standard reverse-proxy tuning — `client_max_body_size` big enough for
large uploads, and `X-Forwarded-For`/`X-Forwarded-Proto`/
`X-Forwarded-Host` headers set (which `trusted_proxies`/`overwriteprotocol`
depend on). README states this explicitly.
`docs/reverse-proxy.nginx.conf.example` (mirroring Forgejo's) shows the one
HTTPS vhost with those headers and body-size setting — no `stream {}`
block needed.

### Known limitations documented, not built

- Redis (locking/caching) — APCu alone is used; a valid future addition,
  not required for correctness at single-node scale.
- Collabora — Phase 2 below; integrated manually after both projects
  exist (WOPI allow-list on the Collabora side, "Nextcloud Office" app
  pointed at it from the NextCloud side).
- Talk — explicitly out of scope; nothing here blocks adding it later,
  since this is a stock NextCloud install.

### Root-level files

`README.md`'s `Proxmox-NextCloud` row stays **"in progress"** (not flipped
to "deployed") until validated against a real cluster — same bar
Steam-Linux was held to. Root `CHANGELOG.md` gets one cross-cutting line
once the PR is ready, not implementation detail.

### Execution sequence

1. Delete the enumerated old files/roles (commit).
2. Build `inventory/group_vars/`, `proxmox_preflight`, `create_nextcloud_vm`,
   first two plays of `deploy_nextcloud.yaml` (commit).
3. Build `nextcloud_prereqs` + `nextcloud_database` (commit).
4. Build `nextcloud_install` + `nextcloud_verify`, finish
   `deploy_nextcloud.yaml` (commit).
5. Build `nextcloud_backup` + `backup_nextcloud.yaml` (commit).
6. `README.md` rewrite, `CHANGELOG.md` extension,
   `docs/reverse-proxy.nginx.conf.example`, `.gitignore`,
   `requirements.yaml` (commit).
7. `--syntax-check` every touched playbook.
8. Push; open PR with the template (Shared/ Dependency: N/A — confirm this
   stays true as work proceeds); review/merge is manual, via the web UI,
   only on explicit instruction.
9. Small follow-up PR: root `README.md`/`CHANGELOG.md`.

### Verification

- `ansible-playbook deploy_nextcloud.yaml --syntax-check` and same for
  `backup_nextcloud.yaml`, both clean.
- `ansible-inventory --graph` resolves with no undefined-var errors given a
  filled-in `nextcloud/vars.yaml.example` copy.
- No LXC/Docker/Apache references remain anywhere under `Proxmox-NextCloud/`
  (`grep -ri` sweep before opening the PR).
- **Idempotency** (CLAUDE.md rule): run `deploy_nextcloud.yaml` twice
  against a real VM, confirm `changed=0` on the second pass — needs real
  cluster access; call it out explicitly in the PR's Test Plan if this
  session can't reach one, rather than leaving it unexplained.
- `occ status` clean, `status.php` returns `installed:true`, reverse-proxy
  route + sync-client test — real-cluster validation, same bar as every
  other project here, not blocking the PR itself.
- No decrypted Vault content appears in any command output/log produced
  while building or testing this.

## Phase 2 — Proxmox-Collabora (separate branch, after Phase 1 merges)

Not started. New top-level project, its own branch/worktree opened only
after this PR merges:

- Native `coolwsd` (not Docker), own VM, own `proxmox_preflight` copy —
  same shape as every other project here, not a shared role with NextCloud
  (the two projects depend only on `Shared/`, never on each other).
- WOPI host allow-list templated from an operator-supplied
  `collabora_wopi_allowed_hosts` var — points at the NextCloud domain from
  Phase 1.
- Integration with NextCloud is fully manual and one-directional after
  both exist: install the "Nextcloud Office" app, point it at Collabora's
  URL. No shared role, no shared inventory group, no cross-project
  playbook dependency — consistent with "each project depends only on
  `Shared/`."
- Talk/TURN stay out of scope here too.
