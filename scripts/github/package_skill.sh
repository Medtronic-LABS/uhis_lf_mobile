#!/usr/bin/env bash
# Zip .claude/skills/lw-ticket/ for claude.ai org upload. Non-mutating (local file only).
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat <<USAGE
Usage: scripts/github/package_skill.sh [--help]

Zips .claude/skills/lw-ticket/ into dist/skills/lw-ticket.zip with the folder
'lw-ticket/' at the zip root. Deterministic: sorted entries, fixed timestamps,
.DS_Store excluded. Writes only under dist/; never touches GitHub.
USAGE
}

parse_common_flags usage "$@"

SKILL_NAME="lw-ticket"
SRC="$REPO_ROOT/.claude/skills/$SKILL_NAME"
OUT="$REPO_ROOT/dist/skills/$SKILL_NAME.zip"

if [ ! -d "$SRC" ]; then
  echo "error: $SRC not found; the $SKILL_NAME skill has not been created yet." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
python3 - "$SRC" "$OUT" "$SKILL_NAME" <<'PY'
import os, sys, zipfile

src, out, name = sys.argv[1:4]
files = []
for root, dirs, names in os.walk(src):
    dirs.sort()
    for n in sorted(names):
        if n == ".DS_Store":
            continue
        full = os.path.join(root, n)
        files.append((os.path.join(name, os.path.relpath(full, src)), full))
files.sort()
if os.path.exists(out):
    os.remove(out)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for arc, full in files:
        info = zipfile.ZipInfo(arc, date_time=(2026, 1, 1, 0, 0, 0))
        info.external_attr = 0o644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        with open(full, "rb") as fh:
            z.writestr(info, fh.read())
print(f"wrote {out} ({len(files)} files)")
PY
