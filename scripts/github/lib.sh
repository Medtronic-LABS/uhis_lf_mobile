#!/usr/bin/env bash
# Shared helpers for scripts/github/*.sh (sourced, not executed).
# Constants are overridable from the environment for forks.

OWNER="${OWNER:-Medtronic-LABS}"
REPO="${REPO:-uhis_lf_mobile}"
PROJECT="${PROJECT:-4}"
APPLY=0

# Repo root, independent of the caller's cwd.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Print the mutating command in dry-run; execute it with --apply.
run() {
  if [ "$APPLY" -eq 1 ]; then
    echo "+ $*"
    "$@"
  else
    echo "[dry-run] $*"
  fi
}

# Like run(), but the first argument is a body fed to the command on stdin.
run_stdin() {
  local body="$1"
  shift
  if [ "$APPLY" -eq 1 ]; then
    echo "+ $* <<'JSON'"
    printf '%s\n' "$body"
    echo "JSON"
    printf '%s\n' "$body" | "$@"
  else
    echo "[dry-run] $* <<'JSON'"
    printf '%s\n' "$body"
    echo "JSON"
  fi
}

# Parse the flags shared by every script; unknown flags are collected in REST.
# usage: parse_common_flags usage_fn "$@"
REST=()
parse_common_flags() {
  local usage_fn="$1" arg
  shift
  for arg in "$@"; do
    case "$arg" in
      --apply) APPLY=1 ;;
      -h|--help) "$usage_fn"; exit 0 ;;
      *) REST+=("$arg") ;;
    esac
  done
}

banner() {
  if [ "$APPLY" -eq 1 ]; then
    echo "== APPLY mode: changes WILL be made to $OWNER/$REPO =="
  else
    echo "== DRY-RUN (default): nothing is changed. Re-run with --apply to execute. =="
  fi
}
