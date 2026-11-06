#!/bin/sh
# One-time (idempotent) developer setup for the LEAPWELL SDLC tooling.
#   - activates the repo git hooks (.githooks: commit-msg, pre-commit)
#   - checks python3 >= 3.11 (the hooks and CI checks need it)
#   - checks gh is installed and signed in (warning only)
# Usage: sh scripts/setup_dev.sh
set -e
cd "$(git rev-parse --show-toplevel)"

ok() { printf '  [ok]   %s\n' "$1"; }
warn() { printf '  [warn] %s\n' "$1"; }

echo "LEAPWELL dev setup"

chmod +x .githooks/commit-msg .githooks/pre-commit
git config core.hooksPath .githooks
ok "git hooks active (core.hooksPath=.githooks)"

if command -v python3 >/dev/null 2>&1 &&
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
  ok "$(python3 --version)"
else
  warn "python3 3.11+ not found - the git hooks will fail until it is installed"
fi

if ! command -v gh >/dev/null 2>&1; then
  warn "gh (GitHub CLI) not installed - needed by /lw-start and /lw-pr in Claude Code"
elif gh auth status >/dev/null 2>&1; then
  ok "gh signed in"
else
  warn "gh not signed in - run: gh auth login"
fi

cat <<'EOF'

Next steps:
  1. Read docs/process/SDLC.md (sizes, branches, Definition of Ready/Done).
  2. Tickets are filed in leapwell (https://github.com/Medtronic-LABS/leapwell); start Claude from
     the leapwell workspace (clone it, run /lw-setup) and route items with /lw-route.
  3. Pick up a sub-issue: /lw-start <issue-number>  (creates type/<N>-<slug>).
  4. Open a draft PR to develop: /lw-pr
  5. Run the SDLC checks: python3 -m unittest discover -s scripts/sdlc/tests -t .
EOF
