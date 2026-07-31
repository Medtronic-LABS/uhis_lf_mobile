#!/usr/bin/env bash
# Build, sign-verify, and (optionally) tag a release App Bundle.
# ABI scope (arm64-v8a + armeabi-v7a only, x86_64 dropped) is enforced in
# android/app/build.gradle.kts's defaultConfig.ndk.abiFilters, not here —
# --target-platform cannot safely restrict an .aab's native libraries (it only
# skips compiling Flutter's own libapp.so/libflutter.so for the excluded ABI,
# while AGP's default abiFilters still bundles third-party plugins' .so files
# for it regardless, producing a broken slice with no Flutter engine).
#
# Usage:
#   scripts/release.sh                       # production flavor, current pubspec version
#   scripts/release.sh production patch      # bump patch + build number
#   scripts/release.sh production 1.2.0+15   # explicit version
#   scripts/release.sh production patch --tag   # bump, then stop and ask you to commit
#   scripts/release.sh production "" --tag      # tag the already-committed current version
set -euo pipefail

cd "$(dirname "$0")/.."

FLAVOR="${1:-production}"
VERSION_ARG="${2:-}"
shift $(( $# > 0 ? 1 : 0 )) || true
shift $(( $# > 0 ? 1 : 0 )) || true

DO_TAG=false
for arg in "$@"; do
  [[ "$arg" == "--tag" ]] && DO_TAG=true
done

ENV_FILE="env.${FLAVOR}.json"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "✗ $ENV_FILE not found. Copy env.example.json → $ENV_FILE and fill values." >&2
  exit 1
fi

KEY_PROPS="android/key.properties"
if [[ ! -f "$KEY_PROPS" ]]; then
  echo "✗ $KEY_PROPS missing — refusing to build a 'release' artifact that would" >&2
  echo "  silently fall back to debug signing (see build.gradle.kts). See RELEASE_PLAN.md §2." >&2
  exit 1
fi

# ── --tag requires a clean tree BEFORE any version bump this run makes ──────
if $DO_TAG && [[ -n "$(git status --porcelain)" ]]; then
  echo "✗ --tag requires a clean working tree (checked before any version bump)." >&2
  echo "  Commit or stash pending changes first." >&2
  exit 1
fi

# ── Optional version bump ───────────────────────────────────────────────────
CURRENT_LINE=$(grep '^version:' pubspec.yaml)
if [[ ! "$CURRENT_LINE" =~ ^version:\ ([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]; then
  echo "✗ Could not parse pubspec.yaml version line: $CURRENT_LINE" >&2
  exit 1
fi
CUR_MAJOR="${BASH_REMATCH[1]}"; CUR_MINOR="${BASH_REMATCH[2]}"
CUR_PATCH="${BASH_REMATCH[3]}"; CUR_BUILD="${BASH_REMATCH[4]}"

BUMPED=false
if [[ -n "$VERSION_ARG" ]]; then
  case "$VERSION_ARG" in
    patch) NEW="${CUR_MAJOR}.${CUR_MINOR}.$((CUR_PATCH+1))+$((CUR_BUILD+1))" ;;
    minor) NEW="${CUR_MAJOR}.$((CUR_MINOR+1)).0+$((CUR_BUILD+1))" ;;
    major) NEW="$((CUR_MAJOR+1)).0.0+$((CUR_BUILD+1))" ;;
    *)     NEW="$VERSION_ARG" ;;
  esac
  if [[ ! "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)$ ]]; then
    echo "✗ Bad version format: $NEW (expected X.Y.Z+N)" >&2
    exit 1
  fi
  NEW_BUILD="${BASH_REMATCH[1]}"
  if (( NEW_BUILD <= CUR_BUILD )); then
    echo "✗ New build number ($NEW_BUILD) must exceed current ($CUR_BUILD) — Play requires a strictly increasing versionCode." >&2
    exit 1
  fi
  perl -pi -e "s/^version:.*/version: $NEW/" pubspec.yaml
  BUMPED=true
  echo "▶ Bumped pubspec.yaml version to $NEW"
fi

echo "▶ Building release App Bundle ($FLAVOR)"
flutter pub get
flutter build appbundle \
  --release \
  --dart-define-from-file="$ENV_FILE"

AAB="build/app/outputs/bundle/release/app-release.aab"
if [[ ! -f "$AAB" ]]; then
  echo "✗ Expected artifact not found: $AAB" >&2
  exit 1
fi

# ── Signer verification: compute the keystore's fingerprint fresh, don't
#    compare against a hardcoded value that could go stale ─────────────────
STORE_FILE=$(grep '^storeFile=' "$KEY_PROPS" | cut -d= -f2-)
STORE_PASS=$(grep '^storePassword=' "$KEY_PROPS" | cut -d= -f2-)
KEY_ALIAS=$(grep '^keyAlias=' "$KEY_PROPS" | cut -d= -f2-)

if ! command -v keytool >/dev/null; then
  echo "✗ keytool not found. Set JAVA_HOME to a JDK (e.g. \$(/usr/libexec/java_home -v21) or Homebrew openjdk@21)." >&2
  exit 1
fi

KEYSTORE_FPR=$(keytool -list -v -keystore "$STORE_FILE" -storepass "$STORE_PASS" -alias "$KEY_ALIAS" 2>/dev/null | awk '/SHA256:/{print $2; exit}')
AAB_FPR=$(keytool -printcert -jarfile "$AAB" 2>/dev/null | awk '/SHA256:/{print $2; exit}')

if [[ "$KEYSTORE_FPR" != "$AAB_FPR" ]]; then
  echo "✗ Signer mismatch! aab=$AAB_FPR  keystore=$KEYSTORE_FPR" >&2
  echo "  This build is NOT signed with the expected upload key." >&2
  exit 1
fi

SIZE=$(du -h "$AAB" | cut -f1)
echo "✓ Signed correctly. SHA-256: $AAB_FPR"
echo "✓ Output: $AAB ($SIZE)"

if $DO_TAG; then
  if $BUMPED; then
    echo ""
    echo "✋ Version was bumped this run — not tagging. Commit the pubspec.yaml" >&2
    echo "   change, then re-run with an empty version arg and --tag to tag it:" >&2
    echo "   scripts/release.sh $FLAVOR \"\" --tag" >&2
    exit 1
  fi
  TAG="v${CUR_MAJOR}.${CUR_MINOR}.${CUR_PATCH}+${CUR_BUILD}"
  git tag -a "$TAG" -m "Release $TAG"
  echo "✓ Tag $TAG created locally (not pushed). Push with: git push origin $TAG"
fi
