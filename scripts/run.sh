#!/usr/bin/env bash
# `flutter run` UHIS Next using env.<flavor>.json for config.
# Usage:
#   scripts/run.sh                  # development on first attached device
#   scripts/run.sh staging          # staging
#   scripts/run.sh dev -d chrome    # development on chrome
set -euo pipefail

cd "$(dirname "$0")/.."

FLAVOR="${1:-development}"
shift || true

ENV_FILE="env.${FLAVOR}.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "✗ $ENV_FILE not found. Copy env.example.json → $ENV_FILE and fill values." >&2
  exit 1
fi

flutter run \
  --dart-define-from-file="$ENV_FILE" \
  "$@"
