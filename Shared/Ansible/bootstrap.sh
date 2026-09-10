#!/usr/bin/env bash
##########
# Build the repo-local Ansible toolchain, isolated from the system Python:
#
#   <repo-root>/.venv/                 Python venv (ansible-core + deps)
#   <repo-root>/.ansible/collections/  Galaxy collections
#
# Both are gitignored. Idempotent — safe to re-run to pick up updated
# requirements. The Deploy.sh / Install-Prerequisites.sh wrappers use this
# automatically (they put .venv/bin on PATH and export
# ANSIBLE_COLLECTIONS_PATH); you only run this once per checkout, and
# again after changing a requirements file.
#
# Run it from anywhere in the repo.
##########
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
VENV="$ROOT/.venv"
COLLECTIONS="$ROOT/.ansible/collections"

echo "Repo root:    $ROOT"
echo "venv:         $VENV"
echo "collections:  $COLLECTIONS"
echo

if [ ! -x "$VENV/bin/python" ]; then
  echo "Creating the virtualenv..."
  if ! python3 -m venv "$VENV" 2>/dev/null; then
    echo "python3 -m venv failed — install the venv module:" >&2
    echo "  sudo apt install python3-venv" >&2
    exit 1
  fi
fi

echo "Installing Python packages ($HERE/requirements.txt)..."
"$VENV/bin/pip" install --upgrade pip >/dev/null
"$VENV/bin/pip" install -r "$HERE/requirements.txt"

echo
echo "Installing Ansible collections into $COLLECTIONS ..."
mkdir -p "$COLLECTIONS"
# Drive the install location via the env var (the ansible-recommended way)
# rather than -p, so ansible-galaxy treats it as a configured path and
# doesn't warn about installing "outside" the default.
export ANSIBLE_COLLECTIONS_PATH="$COLLECTIONS"
for req in "$HERE/requirements.yaml" "$ROOT"/*/requirements.yaml; do
  [ -f "$req" ] || continue
  echo "  <- ${req#"$ROOT"/}"
  "$VENV/bin/ansible-galaxy" collection install -r "$req" >/dev/null
done

echo
echo "Done."
"$VENV/bin/ansible" --version | head -n1
echo
echo "The Deploy.sh / Install-Prerequisites.sh wrappers use this venv"
echo "automatically. For an interactive Ansible shell:"
echo "  source \"$VENV/bin/activate\""
echo "  export ANSIBLE_COLLECTIONS_PATH=\"$COLLECTIONS\""
