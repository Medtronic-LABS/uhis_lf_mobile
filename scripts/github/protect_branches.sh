#!/usr/bin/env bash
# Apply branch protection to main and develop. Dry-run by default.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat <<USAGE
Usage: scripts/github/protect_branches.sh [--apply] [--help]

main:    2 approvals, CODEOWNERS review, dismiss stale reviews, strict required checks
develop: 1 approval,  CODEOWNERS review, dismiss stale reviews, strict required checks
Required checks: pr-check, sdlc-scripts, secret-scan, flutter, build-apk
No force push, no deletion, conversation resolution required, enforce_admins false.
Default is a dry-run that only prints the gh api calls and bodies.
USAGE
}

parse_common_flags usage "$@"
banner

CHECKS='["pr-check", "sdlc-scripts", "secret-scan", "flutter", "build-apk"]'

protection_body() {
  local approvals="$1"
  cat <<JSON
{
  "required_status_checks": { "strict": true, "contexts": $CHECKS },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": $approvals,
    "require_code_owner_reviews": true,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
}

protect() {
  local branch="$1" approvals="$2"
  run_stdin "$(protection_body "$approvals")" \
    gh api -X PUT "repos/$OWNER/$REPO/branches/$branch/protection" --input -
}

protect main 2
protect develop 1
