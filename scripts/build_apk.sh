#!/usr/bin/env bash
# Build UHIS Next debug APK using env.<flavor>.json for config.
# Usage:
#   scripts/build_apk.sh                    # uses env.development.json
#   scripts/build_apk.sh staging            # uses env.staging.json
#   scripts/build_apk.sh production --release  # uses env.production.json, release mode
set -euo pipefail

cd "$(dirname "$0")/.."

FLAVOR="${1:-development}"
shift || true

ENV_FILE="env.${FLAVOR}.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "✗ $ENV_FILE not found. Copy env.example.json → $ENV_FILE and fill values." >&2
  exit 1
fi

MODE="--debug"
TARGET="android-arm64"
EXTRA_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --release|--profile|--debug) MODE="$arg" ;;
    *) EXTRA_ARGS+=("$arg") ;;
  esac
done

echo "▶ Building UHIS Next ($FLAVOR, $MODE)"
flutter build apk \
  "$MODE" \
  --target-platform "$TARGET" \
  --dart-define-from-file="$ENV_FILE" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
