#!/usr/bin/env bash
# Build UHIS Next debug APK using env.<flavor>.json for config.
# Usage:
#   scripts/build_apk.sh                    # uses env.development.json
#   scripts/build_apk.sh staging            # uses env.staging.json
#   scripts/build_apk.sh production --release  # uses env.production.json, release mode
#   scripts/build_apk.sh training --release --app-flavor training  # distinct
#     "LW Training" app (own applicationId, launcher icon, top banner) — see
#     android/app/build.gradle.kts's productFlavors and
#     lib/core/config/app_config.dart's isTrainingBuild.
#
# --app-flavor selects which Android product flavor (Gradle identity) to
# build: "prod" (default, unchanged com.medtroniclabs.uhis_next) or
# "training" (com.medtroniclabs.uhis_next.training). This is independent of
# the env.<flavor>.json selection above — one controls app identity, the
# other controls which backend it talks to.
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
APP_FLAVOR="prod"
EXTRA_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --release|--profile|--debug) MODE="$arg" ;;
    --app-flavor=*) APP_FLAVOR="${arg#--app-flavor=}" ;;
    --app-flavor) APP_FLAVOR_NEXT=1 ;;
    *)
      if [[ "${APP_FLAVOR_NEXT:-0}" == "1" ]]; then
        APP_FLAVOR="$arg"
        APP_FLAVOR_NEXT=0
      else
        EXTRA_ARGS+=("$arg")
      fi
      ;;
  esac
done

if [[ "$APP_FLAVOR" != "prod" && "$APP_FLAVOR" != "training" ]]; then
  echo "✗ --app-flavor must be 'prod' or 'training' (got: $APP_FLAVOR)" >&2
  exit 1
fi

echo "▶ Building UHIS Next ($FLAVOR, $MODE, app-flavor=$APP_FLAVOR)"
flutter build apk \
  "$MODE" \
  --flavor "$APP_FLAVOR" \
  --target-platform "$TARGET" \
  --dart-define-from-file="$ENV_FILE" \
  --dart-define=APP_FLAVOR="$APP_FLAVOR" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
