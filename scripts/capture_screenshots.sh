#!/usr/bin/env bash
# Capture Play Store screenshots by driving integration_test/screenshots_test.dart
# on a connected device/emulator via `flutter drive`.
# Usage:
#   scripts/capture_screenshots.sh                 # development flavor, first device
#   scripts/capture_screenshots.sh staging -d emulator-5554
set -euo pipefail

cd "$(dirname "$0")/.."

FLAVOR="${1:-development}"
shift || true

ENV_FILE="env.${FLAVOR}.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "✗ $ENV_FILE not found. Copy env.example.json → $ENV_FILE and fill values." >&2
  exit 1
fi

OUT_DIR="store_assets/screenshots"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "▶ Capturing screenshots ($FLAVOR)"
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart \
  --dart-define-from-file="$ENV_FILE" \
  "$@"

echo "✓ Screenshots written to $OUT_DIR:"
ls -la "$OUT_DIR"
