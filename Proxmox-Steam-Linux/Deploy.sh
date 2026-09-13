#!/usr/bin/env bash
##########
# Convenience wrapper around create-steam_linux.yaml — playbook ONE of two
# (see README.md "Two playbooks"). This only provisions the base
# Steam-Linux host; deploy a game-server instance onto the resulting host
# separately with create-steam_gameserver.yaml.
#
# create-steam_linux.yaml itself is fully non-interactive — no
# vars_prompt/pause anywhere, so it's already safe to run from cron/CI.
# This script only adds a couple of local conveniences: prerequisite
# checks, and generating an SSH keypair if one doesn't exist yet.
##########
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Use the repo-local Ansible toolchain (Shared/Ansible/bootstrap.sh).
ROOT="$(git rev-parse --show-toplevel)"
if [ ! -x "${ROOT}/.venv/bin/ansible-playbook" ]; then
  echo "No Ansible venv at ${ROOT}/.venv — run it once:" >&2
  echo "  ${ROOT}/Shared/Ansible/bootstrap.sh" >&2
  exit 1
fi
export PATH="${ROOT}/.venv/bin:${PATH}"
export ANSIBLE_COLLECTIONS_PATH="${ROOT}/.ansible/collections"

# That PATH/ANSIBLE_COLLECTIONS_PATH only applies inside this script and
# what it calls — a script can't change your interactive shell's
# environment. For ad-hoc commands afterwards (ansible-vault view, a
# manual ansible-playbook run, ...), get the same venv in your own shell:
echo "(Ansible venv: ${ROOT}/.venv — for ad-hoc commands in this shell, run: source ${ROOT}/.venv/bin/activate)"

./Install-Prerequisites.sh

if [ ! -f "ssh_keys/id_ed25519" ]; then
  echo
  echo "Generating an SSH keypair for the Steam-Linux VM..."
  mkdir -p ssh_keys
  ssh-keygen -t ed25519 -f ssh_keys/id_ed25519 -N "" -C "proxmox-steam-linux-deploy"
  chmod 600 ssh_keys/id_ed25519
fi

echo
echo "Running create-steam_linux.yaml..."
ansible-playbook create-steam_linux.yaml "$@"

echo
echo "Base host is up. To deploy a game-server instance onto it — e.g. the"
echo "HLDS deathmatch validation instance — run playbook TWO separately:"
echo "  ansible-playbook create-steam_gameserver.yaml \\"
echo "    -e @gameservers/hlds-dm01.vars.yaml"
