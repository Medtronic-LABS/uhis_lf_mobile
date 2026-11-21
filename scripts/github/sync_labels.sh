#!/usr/bin/env bash
# Create/update repo labels from .github/labels.yml. Dry-run by default.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat <<USAGE
Usage: scripts/github/sync_labels.sh [--apply] [--help]

Reads .github/labels.yml and runs, for every label:
  gh label create NAME --color C --description D --force --repo $OWNER/$REPO
Default is a dry-run that only prints the commands.
USAGE
}

parse_common_flags usage "$@"
banner

LABELS_FILE="$REPO_ROOT/.github/labels.yml"
[ -f "$LABELS_FILE" ] || { echo "missing $LABELS_FILE" >&2; exit 1; }

# One tab-separated "name<TAB>color<TAB>description" row per label (stdlib parse).
rows="$(python3 - "$LABELS_FILE" <<'PY'
import re, sys

def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v

labels, cur = [], None
for line in open(sys.argv[1], encoding="utf-8"):
    if line.lstrip().startswith("#") or not line.strip():
        continue
    m = re.match(r"^- name:\s*(.*)$", line)
    if m:
        cur = {"name": unquote(m.group(1)), "color": "", "description": ""}
        labels.append(cur)
        continue
    m = re.match(r"^\s+(color|description):\s*(.*)$", line)
    if m and cur is not None:
        cur[m.group(1)] = unquote(m.group(2))
for l in labels:
    print("\t".join([l["name"], l["color"], l["description"]]))
PY
)"

while IFS=$'\t' read -r name color description; do
  [ -n "$name" ] || continue
  run gh label create "$name" --color "$color" --description "$description" --force --repo "$OWNER/$REPO"
done <<< "$rows"
