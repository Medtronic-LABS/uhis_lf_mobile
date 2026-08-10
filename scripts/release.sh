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

# `flutter pub get` rewrites android/.../GeneratedPluginRegistrant.java listing
# EVERY plugin, dev_dependencies included (integration_test). The release
# variant's Gradle graph correctly omits dev-dependency artifacts, and in the
# appbundle path :app:compileReleaseJavaWithJavac runs before the task that
# regenerates the registrant — so it compiles the pub-get version and dies with
#   error: package dev.flutter.plugins.integration_test does not exist
# A release-mode `flutter build bundle` rewrites the registrant *without* dev
# plugins and is Dart-only (no Gradle), so run it as a cheap fixup first.
echo "▶ Regenerating plugin registrant for release (drops dev_dependency plugins)"
flutter build bundle --release --dart-define-from-file="$ENV_FILE" >/dev/null

AAB="build/app/outputs/bundle/release/app-release.aab"

# Delete any prior artifact BEFORE building: the existence check below cannot
# tell this run's output from a stale bundle left by an earlier (or failed) run.
rm -f "$AAB"

flutter build appbundle \
  --release \
  --dart-define-from-file="$ENV_FILE"

if [[ ! -f "$AAB" ]]; then
  echo "✗ Expected artifact not found: $AAB" >&2
  exit 1
fi

# ── Signer verification: compute the keystore's fingerprint fresh, don't
#    compare against a hardcoded value that could go stale ─────────────────
STORE_FILE=$(grep '^storeFile=' "$KEY_PROPS" | cut -d= -f2-)
STORE_PASS=$(grep '^storePassword=' "$KEY_PROPS" | cut -d= -f2-)
KEY_ALIAS=$(grep '^keyAlias=' "$KEY_PROPS" | cut -d= -f2-)

# macOS ships /usr/bin/keytool as a stub that satisfies `command -v` but exits
# non-zero with "Unable to locate a Java Runtime" when no JDK is installed. That
# left BOTH fingerprints empty below — and two empty strings compare equal, so
# the signer gate silently PASSED on an unverified bundle. Resolve a keytool
# that actually runs, and treat an empty fingerprint as a hard failure.
resolve_keytool() {
  local candidates=() kt flutter_jdk mac_jdk
  [[ -n "${JAVA_HOME:-}" ]] && candidates+=("$JAVA_HOME/bin/keytool")
  # The JDK Flutter itself builds with — the one that produced this .aab.
  flutter_jdk=$(flutter config --list 2>/dev/null | awk -F': ' '/^[[:space:]]*jdk-dir:/{print $2; exit}')
  [[ -n "$flutter_jdk" ]] && candidates+=("$flutter_jdk/bin/keytool")
  if [[ -x /usr/libexec/java_home ]]; then
    mac_jdk=$(/usr/libexec/java_home 2>/dev/null || true)
    [[ -n "$mac_jdk" ]] && candidates+=("$mac_jdk/bin/keytool")
  fi
  candidates+=("/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/keytool")
  candidates+=("/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool")
  candidates+=("$(command -v keytool 2>/dev/null || true)")
  for kt in "${candidates[@]}"; do
    [[ -n "$kt" && -x "$kt" ]] || continue
    # A working JDK keytool exits 0 on -help; the macOS stub exits 1.
    if "$kt" -help >/dev/null 2>&1; then echo "$kt"; return 0; fi
  done
  return 1
}

if ! KEYTOOL=$(resolve_keytool); then
  echo "✗ No working keytool found (a /usr/bin/keytool stub does not count)." >&2
  echo "  Install a JDK and set JAVA_HOME, e.g. brew install openjdk@21, or" >&2
  echo "  point Flutter at one: flutter config --jdk-dir=\"path/to/jdk\"." >&2
  exit 1
fi

KEYSTORE_FPR=$("$KEYTOOL" -list -v -keystore "$STORE_FILE" -storepass "$STORE_PASS" -alias "$KEY_ALIAS" 2>/dev/null | awk '/SHA256:/{print $2; exit}')
AAB_FPR=$("$KEYTOOL" -printcert -jarfile "$AAB" 2>/dev/null | awk '/SHA256:/{print $2; exit}')

if [[ -z "$KEYSTORE_FPR" ]]; then
  echo "✗ Could not read a SHA-256 fingerprint from the keystore." >&2
  echo "  Check storeFile / storePassword / keyAlias in $KEY_PROPS. Diagnostics:" >&2
  "$KEYTOOL" -list -v -keystore "$STORE_FILE" -storepass "$STORE_PASS" -alias "$KEY_ALIAS" >&2 || true
  exit 1
fi

if [[ -z "$AAB_FPR" ]]; then
  echo "✗ Could not read a signing certificate from $AAB — it may be unsigned." >&2
  echo "  Never upload this artifact. Diagnostics:" >&2
  "$KEYTOOL" -printcert -jarfile "$AAB" >&2 || true
  exit 1
fi

if [[ "$KEYSTORE_FPR" != "$AAB_FPR" ]]; then
  echo "✗ Signer mismatch! aab=$AAB_FPR  keystore=$KEYSTORE_FPR" >&2
  echo "  This build is NOT signed with the expected upload key." >&2
  exit 1
fi

SIZE=$(du -h "$AAB" | cut -f1)
echo "✓ Signed correctly. SHA-256: $AAB_FPR"
echo "✓ Output: $AAB ($SIZE)"

# ── Archive the verified artifact into releases/ ────────────────────────────
# Only reached after the signer check above passes, so releases/ never holds an
# unverified bundle. Gradle overwrites build/.../app-release.aab on every run;
# this keeps each build addressable by version + timestamp. releases/ is
# gitignored — these are large binaries, not source.
# Read the version back from pubspec.yaml so this is correct whether or not a
# bump happened this run.
EFFECTIVE_VERSION=$(awk '/^version:/{print $2; exit}' pubspec.yaml)
RELEASES_DIR="releases"
mkdir -p "$RELEASES_DIR"
RELEASE_COPY="$RELEASES_DIR/app_release_${FLAVOR}_v${EFFECTIVE_VERSION}_$(date +%y-%m-%d_%H-%M-%S).aab"
cp "$AAB" "$RELEASE_COPY"
echo "✓ Archived: $RELEASE_COPY"

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
