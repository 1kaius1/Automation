#!/usr/bin/env bash
# ============================================
# create-templates_from_manifest.sh
# ============================================
#
# Build every template in template_manifest.yaml, one `ansible-playbook`
# run per template.
#
# create-template-linux.yaml itself builds exactly ONE template (the one
# named by template_target) and fails fast if it already exists — that is
# the right behaviour for a single, deliberate build. This wrapper is the
# "make all the base templates" entry point: it walks the manifest and
# invokes the playbook once per row with `-e batch_mode=true`, which turns
# the "already exists" hard-fail into a logged skip. Rows that still need
# building are built; rows already present as templates are skipped with a
# warning; a VMID occupied by something that is NOT the expected template
# still stops that row (and is reported at the end).
#
# Usage:
#   cd Shared/Ansible
#   ./create-templates_from_manifest.sh [extra ansible-playbook args...]
#
# Any extra arguments are passed through to every ansible-playbook call
# (e.g. -v, --check, --vault-password-file PATH).
# ============================================
set -euo pipefail

cd "$(dirname "$0")"

MANIFEST="template_manifest.yaml"
PLAYBOOK="create-template-linux.yaml"
CONFIG="template_configuration.yaml"

[ -f "$MANIFEST" ] || { echo "error: $MANIFEST not found (run from Shared/Ansible)" >&2; exit 1; }
[ -f "$PLAYBOOK" ] || { echo "error: $PLAYBOOK not found (run from Shared/Ansible)" >&2; exit 1; }

# PyYAML ships with Ansible, so python3 -c 'import yaml' is safe here.
# Emits "<name>\t<state>" per row, where <state> is:
#   stub    - row has stub: true in the manifest (build path not implemented)
#   config  - name is in template_skip in template_configuration.yaml
#             (intentionally not built in THIS environment, e.g. a template
#             whose CPU model this cluster's nodes can't provide)
#   (empty) - build it
mapfile -t ROWS < <(python3 -c '
import sys, yaml
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f)
skip = []
try:
    with open(sys.argv[2]) as f:
        skip = (yaml.safe_load(f) or {}).get("template_skip", []) or []
except FileNotFoundError:
    pass
for row in (doc or {}).get("templates", []):
    name = row["name"]
    state = "stub" if row.get("stub") else ("config" if name in skip else "")
    print("%s\t%s" % (name, state))
' "$MANIFEST" "$CONFIG")

if [ "${#ROWS[@]}" -eq 0 ]; then
    echo "error: no templates listed in $MANIFEST" >&2
    exit 1
fi

echo "Manifest lists ${#ROWS[@]} row(s)."
echo

built=() failed=() skipped_stub=() skipped_config=()
for row in "${ROWS[@]}"; do
    name="${row%%$'\t'*}"
    state="${row#*$'\t'}"
    if [ "$state" = "stub" ]; then
        echo "skipped (stub): $name"
        skipped_stub+=("$name")
        continue
    fi
    if [ "$state" = "config" ]; then
        echo "skipped (template_skip): $name"
        skipped_config+=("$name")
        continue
    fi
    echo "======================================================================"
    echo "=== $name"
    echo "======================================================================"
    if ansible-playbook "$PLAYBOOK" -e "template_target=${name}" -e "batch_mode=true" "$@"; then
        built+=("$name")
    else
        rc=$?
        echo "!!! $name: ansible-playbook exited $rc — see output above" >&2
        failed+=("$name")
    fi
    echo
done

echo "======================================================================"
echo "Done."
echo "  ok                    : ${built[*]:-(none)}"
echo "  failed                : ${failed[*]:-(none)}"
echo "  skipped (stub)        : ${skipped_stub[*]:-(none)}"
echo "  skipped (template_skip): ${skipped_config[*]:-(none)}"
echo "(a template that already existed is reported as ok — it was skipped,"
echo " not rebuilt; see each run's log above for which.)"

[ "${#failed[@]}" -eq 0 ]
