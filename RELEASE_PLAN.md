# RELEASE_PLAN.md — LEAPWELL (uhis_lf_mobile) — First Play Store Submission

**Status as of this session:** signing is real, a release App Bundle has been built, ABI-trimmed, and
verified, the app is renamed for the listing, screenshot capture and release automation (local script +
CI workflow) now exist, and the privacy/data-deletion policy questions are decided. Everything else in
this document is either a fact gathered from the repo or a manual step for whoever holds Play Console
access — nothing past this point has been submitted anywhere.

Decisions locked in for this plan (confirmed with the requester):
- **Play Console account**: Organization (Workspace-verified) → no forced 14-day closed-testing gate;
  Internal testing can promote directly to Production.
- **applicationId**: kept as `com.medtroniclabs.uhis_next` (see §1).
- **App / listing name**: **LEAPWELL**, approved by BRAC alongside "Apon Sushashthya" — LEAPWELL is
  the primary name for recall, with Apon Sushashthya used as the tagline shown beneath it at startup
  (manifest label + pubspec description updated; Play listing title should use LEAPWELL too, with
  Apon Sushashthya as the subtitle/tagline in the listing copy).
- **Keystore**: generated this session (see §2).
- **minSdk**: reconfirmed 24 as the practical floor — not lowered (see §3).
- **Privacy policy**: reuse the existing UHIS corporate policy link as-is, accepting the known risk
  that it doesn't itemize this app's actual data categories (see §4).
- **Data deletion**: mirror UHIS's own Play declaration — no deletion mechanism provided (see §4).
- **App size**: trimmed to arm64-v8a + armeabi-v7a only, applied globally (including debug/profile
  builds) since AGP has no per-build-type ABI filter (see §3).

---

## 1. App identity

| Item | Value | Notes |
|---|---|---|
| `applicationId` / `namespace` | `com.medtroniclabs.uhis_next` | `android/app/build.gradle.kts:8,21`. **Not** a placeholder (`com.example.*`) and distinct from the reference app `org.medtroniclabs.uhis`. It does not literally match the `org.medtroniclabs.*` namespace originally specified — flagged and explicitly kept as-is per confirmation, since it's real, unique, and already wired through the Kotlin source path (`android/app/src/main/kotlin/com/medtroniclabs/uhis_next/MainActivity.kt`). **This is now permanent** — Play Console locks the applicationId forever after the first upload. |
| Dart package name (`pubspec.yaml` `name:`) | `uhis_next` | Internal identifier only (Dart imports, build artifact naming) — invisible to end users and to Play Store. Deliberately **not** renamed; doing so would mean touching every import in the codebase for zero user-facing benefit. |
| App display name (`android:label`) | `LEAPWELL` | **Changed this session** from `Apon Sushashthya` — `android/app/src/main/AndroidManifest.xml:59`. Both names are BRAC-approved; LEAPWELL is primary, Apon Sushashthya is the startup tagline. |
| `pubspec.yaml` description | `LEAPWELL (Apon Sushashthya) — Powered by Medtronic Labs for frontline health workers` | **Changed this session** from `Apon Sushashthya (আপন সুস্বাস্থ্য) — Powered by Medtronic Labs for frontline health workers`. |
| `versionName` / `versionCode` | `1.0.0` / `1` | `pubspec.yaml:4` (`version: 1.0.0+1`), consistent with a true first release. |
| Icon | Custom flat PNGs in `mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` (3.5–17KB each) | Real branded icons (replaced Flutter's default icon in a prior commit), **not** Flutter template defaults. |
| Adaptive icon (`mipmap-anydpi-v26/`) | **Absent** | Only legacy flat icons exist — no foreground/background layered adaptive icon. Not a submission blocker (Play still accepts legacy icons), but Play's pre-launch report will likely flag it as a recommendation. **Needs a designer to produce separate foreground/background layers** — nothing to generate from the current single flattened PNG without introducing visual regressions, so left out of this session's scope. |
| Splash screen | Custom, hand-built (not `flutter_native_splash`) | `drawable/launch_background.xml` + `drawable/splash_logo.png`, background `#1B2B5E`, day + night variants present (`values-night/styles.xml`). Real and branded — no action needed. |

## 2. Signing — NEW upload keystore (generated this session)

| Item | Value |
|---|---|
| Keystore path | `~/.keystores/uhis-lf-mobile/apon-sushashthya-upload.jks` (**outside the repo**, as required) |
| Key alias | `upload` |
| Algorithm | RSA 2048, SHA384withRSA, valid 10,000 days (until 2053-12-10) |
| Store/key password | Identical (PKCS12 keystores require store and key password to match — `keytool` enforced this; both are the same random 24-char value) |
| Credentials file | `~/.keystores/uhis-lf-mobile/credentials.txt` (`chmod 600`) — **move these values into your team's password manager / secrets vault and delete this file** once transcribed. This is the only copy outside `android/key.properties`. |
| **SHA-256 fingerprint (upload cert)** | `DA:32:CB:B0:59:15:94:EA:F6:3B:FA:3D:3C:54:A6:F3:57:37:12:5C:46:99:AA:A3:2B:D8:59:91:6D:B0:3B:26` |
| SHA-1 fingerprint | `E9:5F:94:5F:90:2A:0C:0B:1A:DC:8B:54:C5:AA:51:28:8D:F3:19:86` |

**Wiring** (`android/app/build.gradle.kts`):
- `android/key.properties` created (contains `storeFile`, `storePassword`, `keyPassword`, `keyAlias`) — confirmed git-ignored via `android/.gitignore:12` (`git check-ignore -v` verified).
- `build.gradle.kts` now loads `key.properties` at configuration time and defines `signingConfigs.release` from it. `buildTypes.release.signingConfig` uses the new `release` config **when `key.properties` exists**, and falls back to the debug key only if it's absent (e.g. a fresh clone without the keystore) so `flutter run --release` still works for other engineers who haven't been handed the keystore.
- **Nothing keystore- or credential-related was committed.** `git status` should be checked before any commit in this repo going forward to confirm `android/key.properties` and the `.jks` never appear staged (both are gitignored, but this is worth a manual double-check the first time you commit after this change).

**Play App Signing (mandatory for new apps):** when creating the app in Play Console, you will be
required to enroll in Play App Signing — Google generates and holds the *app signing key*; you only
ever hold this *upload key*. Upload this `.aab` and let Play extract your upload certificate
automatically on first upload (Console → **Setup → App integrity**), or upload the SHA-256 fingerprint
above manually beforehand if the Console asks for it before the first build. If the upload keystore is
ever lost, Google can rotate it (upload key reset request) — the app signing key itself never changes,
so users are never broken. **Back up `apon-sushashthya-upload.jks` in at least one place outside your
laptop** (e.g. an encrypted company secrets vault) — losing it before Google acknowledges the upload
certificate would require starting over with a brand-new listing.

## 3. Build config / Play compliance

| Check | Finding |
|---|---|
| Output format | `.aab` — Play requires this for new apps; `flutter build appbundle --release` was run and produced one (see §8). |
| `targetSdk` | **36** (Android 16), resolved at build time from the installed Flutter SDK's embedded default (Flutter 3.44.8 → `FlutterExtension.kt`: `compileSdkVersion=36`, `targetSdkVersion=36`). Not hardcoded in `build.gradle.kts` — it tracks whatever Flutter version is installed on the build machine/CI. This comfortably clears Play's current minimum target API requirement for new-app submissions (which trails the latest stable release by at most one year). |
| `minSdk` | **24** (Android 7.0, released 2016) — same Flutter-default mechanism, **reconfirmed this session as the practical floor**: `local_auth_android` (biometric unlock) hard-requires API 24, and Flutter's own build tooling (`DependencyVersionChecker.kt`) throws a hard build error below API 23 regardless of plugins. Not achievable to lower further without dropping biometric unlock (and even then, ML Kit/SQLCipher/speech_to_text all require 21). Reasonable for a CHW field app either way: covers effectively all active Android devices in low/middle-income deployment contexts. |
| AGP / Kotlin / Gradle | AGP `9.0.1`, Kotlin `2.3.20`, Gradle `9.1.0` (`android/settings.gradle.kts`, `gradle-wrapper.properties`) — current, no compatibility concerns found. |
| `multiDexEnabled` | `true` (`defaultConfig`) — appropriate given the plugin surface (ML Kit, camera, audio, etc.). |
| `minifyEnabled` / R8 | **Enabled implicitly** — no explicit `isMinifyEnabled`/`shrinkResources` line exists in `buildTypes.release`, but `dev.flutter.flutter-gradle-plugin` (applied at the top of `build.gradle.kts`) turns both on by default for app builds (`FlutterPlugin.kt`'s `shouldShrinkResources()`), confirmed by the presence of a real R8 `proguard.map` in the built `.aab`'s `BUNDLE-METADATA`. No action needed. |
| ABI filtering (app size) | **Restricted to arm64-v8a + armeabi-v7a** (x86_64 dropped) — `android/app/build.gradle.kts`'s `defaultConfig.ndk.abiFilters`, **plus** `android/gradle.properties`'s `disable-abi-filtering=true`. Both are required: the Flutter Gradle plugin (`FlutterPluginUtils.kt`/`FlutterPlugin.kt`) unconditionally resets `abiFilters` back to its own full platform list after project evaluation unless that Gradle property opts out — a stale code comment in `FlutterPlugin.kt` suggests user-specified `abiFilters` take precedence, but the actual code doesn't check for that, only for the property. **Verified empirically**: without the property, the build silently kept x86_64 with a *broken* slice (third-party plugin `.so` files present but no `libapp.so`/`libflutter.so` — would crash instantly on a real x86_64 device); with the property, x86_64 is fully absent and the remaining two ABIs are complete. This is a **global** change — debug/profile builds on an x86_64 emulator will no longer install, confirmed and accepted (see decisions above). Cut the `.aab` from 105.4MB → **72.3MB**. |
| `android:usesCleartextTraffic="true"` | **Flag, not fixed.** Set unconditionally in `AndroidManifest.xml:62`, i.e. it applies to the release build too, not just local dev (`AppConfig.apiBaseUrl` defaults to HTTPS, but `coachingServiceUrl`'s dev default and any dart-define override are cleartext-permitted app-wide). Recommend a `network_security_config.xml` that scopes cleartext to a `10.0.2.2`/dev-hostname allowlist for debug builds only, removing the blanket manifest flag from release. Not applied here — it's a behavior change that needs its own testing pass, called out for a follow-up, not bundled into this release-signing session. |
| Offline-first behavior in a release build | **Not verified end-to-end in this session** (would require a physical/emulator device, airplane-mode toggling, and a full sync cycle against a real backend — out of scope for a build/signing pass). Existing automated coverage is thin: `test/core/sync/offline_sync_service_wipe_test.dart` only covers the wipe-gate logic (its own doc comment states the full sync payload pipeline is untested, no HTTP mocking library in the project), and `integration_test/household_enrollment_test.dart` is the one test that exercises a real `/offline-sync/create` call end-to-end via the UI. **Recommend a manual offline/reconnect smoke test on the built `.aab` (installed via `bundletool`) before promoting past Internal testing.** |

### App size breakdown (pre-ABI-trim baseline, first `.aab` built this session — 105.4MB raw)

| Category | Compressed size | % of raw `.aab` | Ships to device? |
|---|---:|---:|---|
| Native libs (`base/lib`, all 3 ABIs) | 55.33 MB | 55.1% | Only 1 ABI (~19MB) ships per device even pre-trim — Play always serves per-device splits |
| Debug symbols (`BUNDLE-METADATA`) | 35.43 MB | 35.3% | No — Play Console crash-symbolication only |
| Proguard/R8 mapping (`BUNDLE-METADATA`) | 3.93 MB | 3.9% | No — Play Console deobfuscation only |
| Assets (fonts, images, ML Kit models, forms) | 2.59 MB | 2.6% | Yes |
| DEX | 2.56 MB | 2.6% | Yes |
| Resources | 0.31 MB | 0.3% | Yes |

~39% of the raw `.aab` never reaches a device regardless of ABI trimming — real per-device downloads
were already ~24MB pre-trim, and are smaller still post-trim. The ABI restriction above was still worth
doing since it shrinks the artifact actually uploaded to Play Console and removes a genuinely broken
x86_64 code path, not because per-device downloads were a problem.

## 4. Health-data policy flag — DO NOT SKIP

This app collects and stores **protected health information** (patient names, ages, health
conditions, visit records, GPS coordinates, national ID data) — Google Play's Health Apps / Sensitive
Permissions policies apply, and the listing will very likely trigger manual/human review. Below is
everything needed to fill in Play Console's **App content** section without back-and-forth.

### Full permission list + justification (for Play Console's permissions declaration)

| Permission | Where used | Justification to give Play |
|---|---|---|
| `INTERNET` | App-wide | Sync patient/household records with the backend; AI Scribe upload. |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | `lib/core/services/location_service.dart` | One-shot GPS fix (not continuous/background) stamped on household/member enrollment and every clinical encounter payload (`encounter.latitude/longitude`), mirroring the existing production SPICE Android app's behavior for field-visit verification. Falls back gracefully to `(0.0, 0.0)` if denied. |
| `CAMERA` (+ `android.hardware.camera` feature, optional) | `nid_ocr_service.dart`, `enrollment_entry_sheet.dart` | Live in-app scanner to photograph the household member's National ID card; text is extracted **on-device** via Google ML Kit (no network round-trip for the OCR itself). **Open item**: confirm with engineering whether the captured photo itself is persisted/uploaded anywhere or discarded after OCR — needed to answer the Data Safety "Photos or videos" question precisely (see below). |
| `RECORD_AUDIO` (+ `android.hardware.microphone` feature, optional) | AI Scribe (`scribe_controller.dart`, `realtime_asr_controller.dart`) | Records the clinician-patient consultation so AI Scribe can auto-fill the visit form. User sees a rationale sheet before the OS permission dialog; audio is uploaded to the app's own backend for transcription and **the in-app rationale text states it is deleted from the server after processing.** |
| `USE_BIOMETRIC` | `biometric_service.dart` | Unlocks the app session using the device's existing fingerprint/face/PIN — standard OS-level authentication, no biometric data is read or transmitted by the app itself. |
| `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `WAKE_LOCK`, `VIBRATE` | `notification_service.dart`, `repeat_scheduler.dart` | Local-only referral SLA reminders (critical/warning/completion channels); boot receiver re-arms pending local alarms after device restart. No network or analytics involved. |

Not requested (confirmed absent): contacts, SMS send/read, Bluetooth, background location. The
WhatsApp/SMS/phone "share" actions (`contact_sheet.dart`) only launch the native Phone/Messaging/
WhatsApp app via `url_launcher` with a pre-filled draft — the app never reads contacts or sends
messages itself.

### Data Safety form — draft answers

| Question | Draft answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Data types collected | **Personal info**: Name, National ID number, phone number, date of birth (household/member enrollment). **Health and fitness**: Health info (visit/assessment records, vitals, diagnoses — see CLAUDE.md's documented assessment payload shapes). **Location**: Approximate and precise location (one-shot, not continuous). **Audio**: Voice or sound recordings (AI Scribe consultation audio). |
| Is data encrypted in transit? | **Yes** — backend default is HTTPS (`AppConfig.apiBaseUrl` defaults to `https://…`); confirm no dart-define override ships a plaintext URL in the production build config before answering this definitively (see the `usesCleartextTraffic` flag in §3). |
| Is data encrypted at rest on-device? | **Yes** — SQLCipher (AES-256, `lib/core/db/app_database.dart`) for the local patient database, and Android Keystore-backed `flutter_secure_storage`/`EncryptedSharedPreferences` for the DB key and session tokens (`lib/core/db/key_store.dart`, `lib/core/auth/auth_repository.dart`). |
| Can users request data deletion? | **No** — decided this session: mirrors the existing UHIS app's own Play declaration, which explicitly states "the developer doesn't provide a way for you to request that your data be deleted." No dedicated deletion process exists for UHIS either, so nothing to reuse; the new app declares the same rather than building a new process. Revisit if product/legal later wants to close this gap on both apps. |
| Is data shared with third parties? | Likely **No** — no third-party analytics/crash SDKs found (grepped `pubspec.yaml`, `android/app/build.gradle`, and all of `lib/` for `firebase\|sentry\|crashlytics\|analytics\|mixpanel\|amplitude\|bugsnag\|datadog` — zero matches). All data flows to the app's own backend only. **Still confirm your cloud hosting arrangement/DPA classification with legal** before answering — "third party" in Play's sense can include your own infrastructure vendor depending on contract terms. |
| Is data collection optional? | Household enrollment consent is a **blocking gate** in-app (`declineWarning`: "Without consent, household registration cannot be completed") — reflect this accurately; Play distinguishes "required for core functionality" from "optional." |

### Privacy policy

**Decided this session: reuse the existing UHIS app's privacy policy link as-is.**

> **Privacy Policy URL: `https://www.medtroniclabs.org/privacy-policy`**

This is the same URL the production UHIS app (`org.medtroniclabs.uhis`) links from its own Play Store
Data Safety section. **Known, accepted risk**: this is a general/corporate policy — it covers website
visitor data (name, email, IP, browser/domain info, cookies) and does **not** mention UHIS or Apon
Sushashthya by name, and does **not** itemize health records, GPS location, NID photos, or audio
recordings, which this app actually collects (see the Data Safety table above). Reusing it is faster
than drafting an app-specific policy, but the mismatch between declared data types and policy content
could surface during Play's manual review of a health-data app. If that happens, the fallback is
drafting an app-specific policy modeled on this one's structure — flagging so it isn't a surprise.

## 5. Store listing readiness — draft (manual checklist)

Copy-paste starting points; replace bracketed items with real decisions.

- **App title**: `LEAPWELL`
- **Short description** (≤80 chars): `LEAPWELL (Apon Sushashthya) — AI-assisted app for community health workers` (76 chars)
- **Full description** (≤4000 chars) — draft:
  > LEAPWELL (Apon Sushashthya / আপন সুস্বাস্থ্য) is an offline-first mobile companion for community health workers (Shasthya Kormi) delivering household-centered primary care in the field. It supports antenatal, postnatal, non-communicable disease, tuberculosis, and child health visits with a guided, three-step visit flow: symptom check, vitals and clinical assessment, and an AI-assisted recommendation with clinical decision support.
  >
  > Built for low-connectivity environments, all patient data is captured and encrypted on-device and synchronizes automatically when a connection is available. An on-device AI Scribe transcribes the consultation to help pre-fill visit forms, always reviewed and confirmed by the health worker before saving — nothing is recorded without consent, and every AI suggestion is a proposal, never an automatic action.
  >
  > [Add: supported regions/programme name, sponsoring organization, and any explicit statement that this app is intended for use by trained/credentialed health workers only, not the general public — since data collection is professional, not consumer-facing.]
- **Feature graphic** (1024×500), **hi-res icon** (512×512): still need to be designed — no source assets exist in the repo.
- **Phone screenshots**: run `scripts/capture_screenshots.sh` (see §9) — captures dashboard, patient context, and (best-effort) the visit triage screen from a real running build. The Step 3 AI Recommendation screen is **not** automated (too fragile to drive reliably against real synced test data) — capture that one manually from a QA build.
- **Privacy policy URL**: `https://www.medtroniclabs.org/privacy-policy` — see §4 for the accepted-risk rationale.
- **Content rating questionnaire**: likely lands in the "Reference/Utility" or "Medical" category with no user-generated public content, no ads, no in-app purchases, no violence/mature content — draft as "Everyone" but run the actual questionnaire, since Google's medical-app category can trigger additional questions about clinical claims.
- **Data Safety form**: see §4 draft table.
- **App category**: Medical, or Health & Fitness (pick based on how Play defines each in the current Console — both exist; "Medical" fits a clinician-facing tool better than "Health & Fitness," which skews consumer wellness).
- **Contact email**: [organization support/contact email — not present anywhere in repo, needs a real inbox].
- **Target audience / age**: Adults only (professional tool for credentialed health workers, not intended for children) — answer the target-audience questionnaire accordingly to avoid the stricter Families/child-directed review path.

## 6. Rollout sequencing

Confirmed: publishing under an **Organization (Workspace-verified)** Play Console account.

1. **Internal testing track** — upload the `.aab` from §8 (or a freshly rebuilt one after any further
   changes). Instant availability, no review gate. This is your "developer release."
2. Because this is an Organization account, the mandatory 14-day/12-tester Closed testing gate that
   applies to personal accounts for new apps **does not apply here** — Internal testing can be promoted
   directly to Production once you're satisfied.
3. Still recommended regardless of account type (standard practice, not a Play requirement): run a
   short **Closed testing** round with real field users before Production, given this app handles
   patient health data and offline sync correctness has thin automated coverage (§3) — a staged
   rollout catches sync/regression issues against real backend data before a full release. This is a
   recommendation, not a gate — skip it if the timeline doesn't allow.
4. When ready for Production, use Play Console's **staged rollout** percentage feature (e.g. 20% → 50%
   → 100%) rather than a 100% release on day one.

## 7. CI/CD

**Built this session**: `.github/workflows/release.yml` — triggers on `v*` tag push or manual
`workflow_dispatch`. Sets up Java 21 (temurin) + Flutter 3.44.8, reconstructs `android/key.properties`
and `env.production.json` from repo secrets, then calls `scripts/release.sh` directly (§10) so CI and
local releases share one build path instead of duplicating logic in YAML. Uploads the `.aab` as a
workflow artifact and attaches it to a GitHub Release on tag pushes.

**Required repo secrets** (none created yet — this is a manual GitHub admin step):
`ANDROID_KEYSTORE_BASE64` (base64 of `apon-sushashthya-upload.jks`), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (values from §2's credentials), and
`ENV_PRODUCTION_JSON_BASE64` (base64 of a real `env.production.json`, shaped like `env.example.json`).

**Play Console upload is intentionally not wired live** — left as a commented-out job stub
(`r0adkll/upload-google-play`) gated on a `PLAY_SERVICE_ACCOUNT_JSON` secret that doesn't exist yet.
Creating a Play service account (Play Console → API access) is an admin action outside this codebase;
uncomment that job once the secret is added.

Previously (still true): no Fastlane, no Codemagic config anywhere in the repo. The other existing
workflow, `.github/workflows/confluence-docs.yml`, is unrelated doc-publishing, untouched by this work.

## 8. Build artifact

```
scripts/release.sh production          # or: scripts/release.sh sktest, for a non-production env
```

(Internally: `flutter pub get` + `flutter build appbundle --release --dart-define-from-file=env.<flavor>.json`,
with signer verification and the ABI trim from §3 already applied via Gradle config — no extra flags needed.)

- **Output**: `build/app/outputs/bundle/release/app-release.aab`
- **Size**: **72.3 MB** (post ABI-trim; was 105.4MB before — see §3's size breakdown and ABI-filtering row)
- **Signer verified**: `scripts/release.sh` computes the keystore's SHA-256 fingerprint fresh from
  `android/key.properties` and compares it against the built `.aab`'s `keytool -printcert -jarfile`
  output, hard-failing on any mismatch — `DA:32:CB:B0:59:15:94:EA:F6:3B:FA:3D:3C:54:A6:F3:57:37:12:5C:46:99:AA:A3:2B:D8:59:91:6D:B0:3B:26`,
  matching the upload keystore from §2 exactly.
- One build-time warning, informational only: `audio_waveforms` and `speech_to_text` still apply the Kotlin Gradle Plugin directly rather than Flutter's built-in Kotlin support — Flutter warns this will become a hard build failure in a future release. Not a submission blocker today; worth a dependency-update follow-up.

## 9. Screenshot capture

```
scripts/capture_screenshots.sh <flavor> [-d <device-id>]
```

Drives `integration_test/screenshots_test.dart` via `flutter drive` (companion driver:
`test_driver/integration_test.dart`), writing PNGs directly to `store_assets/screenshots/`
(gitignored — regenerable build output, not committed). No `adb pull` step needed — the current
`integration_test` package streams screenshot bytes over the same VM-service connection `flutter drive`
already holds.

Captures, against the `hyper_sk`/`Spice123` test account and a real synced backend (same test data
dependency the existing functional integration tests already accept):
1. Dashboard/worklist (post-login)
2. Patient context screen (search → tap a known test patient, "Saidul")
3. Visit flow Step 1 (triage/symptom picker) — **best-effort**: wrapped in try/catch since reaching it
   depends on the "Start Visit" CTA resolving to a single eligible service without an extra service-picker
   step; logs a clear message and continues if not reached rather than failing the whole run.

**Not automated**: the Step 3 AI Recommendation screen. Reaching it requires driving the large,
dynamically-generated `VisitFormScreen` through valid Step 1+2 data against real synced vitals — too
fragile to script reliably without a dedicated, stable test-data fixture. Capture this one manually
from a QA build for the Play listing.

## 10. Release automation

**Local**: `scripts/release.sh <flavor> [patch|minor|major|X.Y.Z+N] [--tag]` — refuses to run without
`android/key.properties` (would silently produce a debug-signed "release" otherwise), optionally bumps
`pubspec.yaml`'s version (refusing a non-increasing build number), builds, verifies the signer fresh
against the keystore (not a hardcoded fingerprint), and prints the output path/size/fingerprint.
`--tag` creates an annotated, **unpushed** git tag — but only when the tree is already clean *before*
any bump this run makes. If a bump happens in the same invocation, the script stops and asks you to
commit first, then re-run with an empty version arg and `--tag` — it never auto-commits.

**CI**: `.github/workflows/release.yml` calls this same script (§7) — one source of truth for both
paths.

---

## What's left — manual checklist for whoever has Play Console access

1. Create the app in Play Console under the Organization account; confirm `com.medtroniclabs.uhis_next` as the package name (immutable after this point).
2. Enroll in Play App Signing when prompted (mandatory for new apps) — either let Play extract the upload cert from the first `.aab` upload, or supply the SHA-256 fingerprint from §2 manually if asked first.
3. Run `scripts/release.sh production` (needs a real `env.production.json` — see `env.example.json` for shape) and upload the resulting `.aab` to the **Internal testing** track.
4. Fill in **App content** using §4/§5 of this document: permissions declaration, Data Safety form (privacy policy URL and deletion answer already decided), content rating questionnaire, target audience.
5. Run `scripts/capture_screenshots.sh` for phone screenshots (§9); capture the AI Recommendation screen manually; get the feature graphic (1024×500) and hi-res icon (512×512) designed — no source assets exist yet.
6. Fill in app title/short/full description (draft provided in §5), category, contact email.
7. Decide on a Closed-testing round before Production (recommended, not required for this account type — §6).
8. Create the five GitHub repo secrets listed in §7 if you want `.github/workflows/release.yml` to run; add `PLAY_SERVICE_ACCOUNT_JSON` later to enable the commented-out Play upload job.
9. Move `~/.keystores/uhis-lf-mobile/credentials.txt` into a real secrets vault / password manager, then delete the plaintext file from disk.
10. Back up `~/.keystores/uhis-lf-mobile/apon-sushashthya-upload.jks` outside this machine.
