#!/usr/bin/env bash
##########
# Install/verify everything create-steam_linux.yaml needs to run.
# Single source of truth for prerequisites — Deploy.sh calls this rather
# than duplicating its own copy of these checks.
##########
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Use the repo-local Ansible toolchain (built by Shared/Ansible/bootstrap.sh).
# Deploy.sh sets these too; repeated here so this script also works when run
# on its own.
ROOT="$(git rev-parse --show-toplevel)"
if [ ! -x "${ROOT}/.venv/bin/ansible-playbook" ]; then
  echo "No Ansible venv at ${ROOT}/.venv."
  echo "Build the repo-local toolchain once:  ${ROOT}/Shared/Ansible/bootstrap.sh"
  exit 1
fi
export PATH="${ROOT}/.venv/bin:${PATH}"
export ANSIBLE_COLLECTIONS_PATH="${ROOT}/.ansible/collections"
ansible --version | head -n1

echo
echo "Refreshing this project's Ansible collections..."
# ANSIBLE_COLLECTIONS_PATH (exported above) drives the install location.
ansible-galaxy collection install -r requirements.yaml

echo
echo "Checking required Python packages (proxmoxer, requests) in the venv..."
missing_py=()
for pkg in proxmoxer requests; do
  if ! "${ROOT}/.venv/bin/python" -c "import ${pkg}" >/dev/null 2>&1; then
    missing_py+=("${pkg}")
  fi
done
if [ "${#missing_py[@]}" -gt 0 ]; then
  echo "Missing from the venv: ${missing_py[*]} — re-run ${ROOT}/Shared/Ansible/bootstrap.sh"
  exit 1
fi
echo "OK."

echo
echo "Checking for site-specific config files (not committed to this public repo)..."
missing_config=()
for f in \
  "ansible.cfg" \
  "inventory/hosts.ini" \
  "inventory/group_vars/steam_linux/vars.yaml"
do
  if [ ! -f "${f}" ]; then
    missing_config+=("${f}")
  fi
done
if [ "${#missing_config[@]}" -gt 0 ]; then
  echo "Missing:"
  for f in "${missing_config[@]}"; do
    if [ "${f}" = "ansible.cfg" ]; then
      echo "  ansible.cfg  (copy from ../Shared/Ansible/ansible.cfg.example — the single"
      echo "               canonical example; keep the COMMON + Proxmox-Steam-Linux sections)"
    else
      echo "  ${f}  (copy from ${f}.example and edit it)"
    fi
  done
  exit 1
fi
echo "OK."

echo
echo "Checking for the shared node/storage/template/backup config..."
if [ ! -f "../Shared/Ansible/group_vars/proxmox_pve1/vars.yaml" ]; then
  echo "Missing: ../Shared/Ansible/group_vars/proxmox_pve1/vars.yaml"
  echo "  (shared across every Proxmox-facing project in this mono-repo — copy from"
  echo "  ../Shared/Ansible/group_vars/proxmox_pve1/vars.yaml.example and edit it once;"
  echo "  later projects reuse it as-is)"
  exit 1
fi
echo "OK."

echo
echo "Checking for vault password file(s)..."
# Read the real paths out of ansible.cfg rather than assuming the default
# "homelab" label/filename — ansible.cfg is a personal file and the user
# may have renamed/relocated it (see ../Shared/Ansible/ansible.cfg.example),
# and vault_identity_list may hold several "label@path" entries.
vault_identity_line="$(grep -E '^\s*vault_identity_list\s*=' ansible.cfg | head -n1 | cut -d'=' -f2-)"
if [ -z "${vault_identity_line// }" ]; then
  echo "Could not find vault_identity_list in ansible.cfg — check it wasn't accidentally removed."
  exit 1
fi
vault_missing=0
IFS=',' read -ra _ids <<< "${vault_identity_line}"
for _id in "${_ids[@]}"; do
  _path="$(echo "${_id}" | cut -d'@' -f2- | xargs)"
  _path="${_path/#\~/${HOME}}"
  [ -n "${_path}" ] || continue
  if [ -e "${_path}" ]; then
    echo "  OK  $(echo "${_id}" | cut -d'@' -f1 | xargs) -> ${_path}"
  else
    echo "  MISSING  $(echo "${_id}" | cut -d'@' -f1 | xargs) -> ${_path}"
    vault_missing=1
  fi
done
if [ "${vault_missing}" -ne 0 ]; then
  echo "One or more vault password files/scripts are missing."
  echo "See ../Shared/Ansible/docs/ANSIBLE_VAULT_GUIDE.md section 2 — required before any"
  echo "vault-encrypted file (the shared Proxmox credential) can be decrypted."
  exit 1
fi

echo
echo "Checking for the shared Proxmox credential..."
if [ ! -f "../Shared/Ansible/group_vars/proxmox_cluster/vault.yaml" ]; then
  echo "Not found. Run the shared bootstrap once per cluster:"
  echo "  cd ../Shared/Ansible && ansible-playbook create-pve_svc_user.yaml"
  exit 1
fi
echo "OK."

echo
echo "This project has no project-local vault.yaml yet — Phase A uses anonymous"
echo "SteamCMD login and needs no secret. See README.md 'Known limitations' for"
echo "when that changes."

echo
echo "All prerequisites satisfied."
