# UHIS Next

Frontline-health worker mobile app for the UHIS Leapfrog programme.
Transforms form-filling and data collection into AI-assisted care delivery.
Flutter, Android-first.

> Companion to the legacy native Android app (`spice_mobile`) and the React
> frontend (`spice_web`) in the parent `platform-setup` repository. UHIS Next
> talks to the same UHIS backend services through the nginx gateway.

---

## Table of Contents

1. [Features](#features)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Setup](#setup)
5. [Configuration (`env.*.json`)](#configuration-envjson)
6. [Running on Android](#running-on-android)
7. [Building APKs](#building-apks)
8. [Authentication Flow](#authentication-flow)
9. [Biometric Login](#biometric-login)
10. [Backend Contract](#backend-contract)
11. [Project Layout](#project-layout)
12. [End-to-End Tests](#end-to-end-tests)
13. [Troubleshooting](#troubleshooting)
14. [Security Notes](#security-notes)
15. [Roadmap / Deferred](#roadmap--deferred)

---

## Features

- **Password sign-in** against `/auth-service/session` (HmacSHA512 client-side hashing, multipart form, cookie + tenant headers).
- **Post-login dashboard** with two live count tiles (patients, households) and a placeholder for high-risk AI triage.
- **Unified top SearchBar** (Material 3 `SearchAnchor.bar`) at the top of the dashboard. Searches patients + households in one query. Scope chips: **All** / **Patients** / **Households**. Auto-detects phone vs NID vs name on patient queries. Falls back from household name → householdNo when first pass returns nothing. Debounced 350 ms with in-flight cancellation.
- **Android biometric login** via the system `BiometricPrompt` (fingerprint / face / PIN / pattern / device password fallback).
- **Auto-lock on background** — banking-app style. App locks the moment it goes to `paused` / `hidden`.
- **Session-token storage only** — never username or password (or hash) at rest. `JSESSIONID` + `AuthCookie` + tenantId persist in `flutter_secure_storage` (Android Keystore-encrypted).
- **Env-driven build configuration** via `--dart-define-from-file=env.<flavor>.json`. No hardcoded URLs / keys in source.

---

## Architecture

```
┌──────────────────────── Flutter (Android) ──────────────────────────┐
│                                                                     │
│  lib/main.dart                                                      │
│    ├─ AppConfig (build-time env)                                    │
│    ├─ ApiClient (Dio + cookie jar + tenantId interceptor)           │
│    ├─ AuthRepository / AuthState (login, session, biometric)        │
│    ├─ BiometricService (local_auth → BiometricPrompt)               │
│    └─ GoRouter                                                      │
│        ├─ /          splash                                         │
│        ├─ /login     password form (cold-start when no biometric)   │
│        ├─ /lock      biometric splash (cold-start + background lock)│
│        ├─ /dashboard counts + search entry                          │
│        ├─ /search/patient                                           │
│        └─ /search/household                                         │
│                                                                     │
│  WidgetsBindingObserver → AuthState.lock() on paused/hidden         │
└─────────────────────────────────────────────────────────────────────┘
              │
              │  cookies + tenantId header (over plain HTTP for dev)
              ▼
┌──────────────────────── UHIS nginx gateway ─────────────────────────┐
│  /auth-service/      → auth-service:8089                            │
│  /user-service/      → user-service:8085  (profile + tenantId)      │
│  /spice-service/     → spice-service:8087 (patient + household)     │
│   ...                                                               │
│  CORS allows http://localhost(:port) origins                        │
└─────────────────────────────────────────────────────────────────────┘
```

State is held by two `ChangeNotifier`s injected via `provider`:
`AuthState` (auth status, biometric flags, lock) and per-feature `Repository`
classes that wrap Dio calls. No Riverpod / BLoC. Lightweight by design.

---

## Prerequisites

- Flutter 3.24+ (`flutter --version` → channel stable, Dart ≥ 3.12).
- Android Studio command-line tools or `~/Library/Android/sdk` populated (emulator + adb on PATH).
- A running UHIS backend stack from the parent `platform-setup/` repo (`bash setup.sh --start`).
- For biometric testing: at least one fingerprint + PIN enrolled on the AVD.

Verify:
```
flutter doctor
adb devices
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/auth-service/actuator/health   # expect 401
```

---

## Setup

```bash
# 1. clone
git clone https://github.com/Medtronic-LABS/uhis_lf_mobile.git
cd uhis_lf_mobile

# 2. dependencies
flutter pub get

# 3. configuration
cp env.example.json env.development.json
$EDITOR env.development.json      # fill in DEV_USER / DEV_PASS / API_BASE_URL

# 4. run
scripts/run.sh                     # uses env.development.json
```

`env.*.json` is gitignored; only `env.example.json` is committed.

---

## Configuration (`env.*.json`)

All runtime config lives in `env.<flavor>.json` and is injected at compile
time via `--dart-define-from-file`. Source of truth: `lib/core/config/app_config.dart`.

| Key                       | Type   | Default               | Purpose                                                                       |
|---------------------------|--------|-----------------------|-------------------------------------------------------------------------------|
| `API_BASE_URL`            | string | `http://10.0.2.2`     | UHIS nginx gateway. `10.0.2.2` = host loopback from Android emulator.         |
| `API_CLIENT`              | string | `web`                 | Value of the `client` request header. `web` or `mob`.                         |
| `PASSWORD_HASH_KEY`       | string | `""`                  | HmacSHA512 key matching `REACT_APP_PASSWORD_HASH_KEY` on the backend.         |
| `AUTH_COOKIE_TTL_SECONDS` | int    | `3600`                | Fallback `AuthCookie` TTL when server omits `Max-Age`.                        |
| `BIOMETRIC_REASON`        | string | `Unlock UHIS Next`    | Localized reason shown inside Android `BiometricPrompt`.                      |
| `DEV_USER`                | string | `""`                  | Optional dev autologin username. **Empty in any non-dev build.**              |
| `DEV_PASS`                | string | `""`                  | Optional dev autologin password. **Empty in any non-dev build.**              |

Anything bundled in the APK is reverse-engineerable. Only put **non-secret**
configuration in `env.*.json`. True secrets stay server-side.

### Per-flavor files

- `env.development.json` — local dev against the docker-compose stack
- `env.staging.json` — staging cluster (kept out of git)
- `env.production.json` — production cluster (injected by CI, never committed)

### CI / secrets

Do NOT commit `env.production.json`. Build it transiently in CI:

```bash
jq -n \
  --arg base   "$API_BASE_URL" \
  --arg client "$API_CLIENT" \
  '{API_BASE_URL:$base, API_CLIENT:$client, PASSWORD_HASH_KEY:"", AUTH_COOKIE_TTL_SECONDS:"3600", BIOMETRIC_REASON:"Unlock UHIS Next", DEV_USER:"", DEV_PASS:""}' \
  > env.production.json

scripts/build_apk.sh production --release
```

---

## Running on Android

### Boot the Pixel 9 AVD

```bash
~/Library/Android/sdk/emulator/emulator -avd Pixel_9 -no-snapshot-load &
adb wait-for-device
adb shell settings put global airplane_mode_on 0
adb shell svc wifi enable
```

Verify network from inside the emulator:

```bash
adb shell ping -c 1 10.0.2.2
```

### Hot-reload dev loop

```bash
scripts/run.sh                      # --debug, attaches to the first device
scripts/run.sh development -d emulator-5554
```

### One-shot install

```bash
scripts/build_apk.sh development
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.medtroniclabs.uhis_next -c android.intent.category.LAUNCHER 1
```

---

## Building APKs

| Flavor      | Mode     | Command                                              |
|-------------|----------|------------------------------------------------------|
| development | debug    | `scripts/build_apk.sh development`                   |
| development | profile  | `scripts/build_apk.sh development --profile`         |
| staging     | release  | `scripts/build_apk.sh staging --release`             |
| production  | release  | `scripts/build_apk.sh production --release`          |

Output: `build/app/outputs/flutter-apk/app-debug.apk` (or `-release.apk`).

`scripts/build_apk.sh` expects `env.<flavor>.json` in repo root. Will exit if
the file is missing.

---

## Authentication Flow

```
                          ┌──────────────────────────┐
                          │ App cold-start           │
                          └──────────┬───────────────┘
                                     ▼
                       ┌────────────────────────────┐
                       │ bootstrap()                │
                       │ - read tenantId from store │
                       │ - read biometric_enabled   │
                       │ - check device support     │
                       └──────────┬─────────────────┘
                                  ▼
                  ┌───────────────┴────────────────┐
                  │                                │
            biometric_enabled               !biometric_enabled
                  │                                │
                  ▼                                ▼
             /lock                            /login
       (BiometricPrompt                  (password form)
        from postFrame)                          │
                  │                              ▼
       OK ───┐    │    cancel                 POST /auth-service/session
             │    │      │                 (multipart, HmacSHA512 hex)
             │    ▼      ▼                      │
             │  rehydrate              ┌────────┴────────┐
             │  cookies              200                non-200
             │     │                   ▼                  ▼
             │     ▼              POST /user-service/   error snackbar
             │  /dashboard        user/profile
             │                          │
             ▼                          ▼
         success                   extract tenantId
                                   store, navigate /dashboard
                                          │
                                          ▼
                               (first time only)
                               "Use device unlock?" dialog
```

- Password hash: `HmacSHA512(password, PASSWORD_HASH_KEY).hex()`. Matches `crypto-js` on the React frontend.
- Cookies: `JSESSIONID` (Spring session) + `AuthCookie` (base64 Bearer). Both stored in cookie_jar with `secure=false` and `domain=null` so Android sends them over plain HTTP and across `10.0.2.2` ↔ `localhost`.
- `tenantId` taken from profile response `entity.tenantId`.

---

## Biometric Login

Uses the `local_auth` Flutter plugin which calls the OS-owned `BiometricPrompt`
on Android. The app does NOT build a Flutter PIN or fingerprint UI. It only
triggers the system sheet; the OS validates against enrolled credentials and
returns success/failure.

### What gets stored on device

| Key                       | Value                                                |
|---------------------------|------------------------------------------------------|
| `biometric_enabled`       | `'true'` once opt-in confirmed                       |
| `bio_jsessionid`          | last `JSESSIONID` cookie value                       |
| `bio_authcookie`          | last `AuthCookie` cookie value                       |
| `bio_authcookie_expiry`   | ISO 8601 expiry derived from `Max-Age`               |
| `bio_tenant_id`           | tenantId of the last-signed-in user                  |
| `bio_last_username`       | username (display only)                              |
| `bio_offered_once`        | `'true'` once the opt-in dialog was shown            |

**Never stored**: username, password, password hash.

`flutter_secure_storage` uses Android `EncryptedSharedPreferences` (Keystore-backed AES).

### Sign-in flow

- **Cold start, biometric enabled**: `/lock` route renders splash + auto-fires `BiometricPrompt`. On success, cookies rehydrate from secure storage into the cookie jar. No network round trip. Dashboard renders.
- **Cold start, biometric disabled**: `/login` renders. After successful manual sign-in, `bio_offered_once` is checked; if absent + device supports biometric, "Use device unlock?" dialog appears on dashboard's first frame. Dismissal (either choice) flips `bio_offered_once`.
- **Logout (overflow menu)**: clears cookies + tenantId + bio session artifacts. Keeps `biometric_enabled` + `bio_last_username`. Next manual login silently re-enrols.
- **Explicit "Disable device unlock"** (overflow menu): clears all bio keys including the preference.

### Auto-lock on background

`UhisNextApp` extends `WidgetsBindingObserver`. On `AppLifecycleState.paused`
or `AppLifecycleState.hidden`, calls `AuthState.lock()` synchronously (no await
to avoid the task-switcher screenshot race).

Mid-session lock is rendered as a full-screen **`LockBarrier` overlay** on
top of the live widget tree (via `MaterialApp.router(builder:)` + `Stack`),
NOT a route swap. This means the underlying screen — TextField text, list
scroll position, in-flight futures — survives the lock/unlock cycle. When
the user returns from background and passes biometric, the barrier dismisses
and the user is back exactly where they left off.

The `/lock` ROUTE is reserved for cold-start with biometric enabled (no
widget tree exists yet to overlay). After cold-start unlock, the router
sends the user to `/dashboard`.

`AppLifecycleState.inactive` is **not** treated as lock — it fires on
transient interruptions (notification shade pull, system dialogs) and would
be too aggressive.

Inside the barrier:
- BiometricPrompt auto-fires from `postFrame`.
- Cancel → "Try again" / "Use password" buttons.
- "Use password" calls `AuthState.requestPasswordFallback()` which drops the
  session client-side, flips `status=signedOut`, then navigates to
  `/login?from=lock`. After successful password login, the biometric slot
  silently re-binds to the new session.
- `PopScope(canPop: false)` blocks the Android back button from leaking past
  the barrier into the dashboard.

### Switching users

Single biometric slot per device. To switch users:
1. On `/lock`, cancel `BiometricPrompt` → "Use password" → `/login?from=lock`.
2. Sign in with new credentials. Successful login silently re-binds biometric to the new user.

For true multi-account picker, biometric state would need to be keyed by username (`bio_jsession:userA`, `bio_jsession:userB`). Out of scope for v1.

---

## Backend Contract

| Action            | Method + Path                       | Body                                                              | Response                          |
|-------------------|-------------------------------------|-------------------------------------------------------------------|-----------------------------------|
| Login             | POST `/auth-service/session`        | `multipart` `username` + `password` (hashed)                      | `JSESSIONID`, `AuthCookie`, `TenantId` header |
| Profile           | POST `/user-service/user/profile`   | (cookie only)                                                     | `entity.tenantId`                 |
| Patient count     | POST `/spice-service/patient/list`  | `{skip:0, limit:1, tenantId}`                                     | `totalCount`                      |
| Patient search    | POST `/spice-service/patient/search`| `{name?\|phoneNumber?\|idCode?, skip, limit, tenantId}`             | `entityList`                      |
| Household list    | POST `/spice-service/household/list`| `{skip, limit, tenantId}`                                         | raw `HouseholdDTO[]` (no count)   |
| Logout            | GET  `/auth-service/logout`         | (cookie only)                                                     | clears server session             |

Required headers on every protected call:
- `client: web` (or `mob` for mobile-suite users)
- `tenantId: <numeric>`
- `Cookie: JSESSIONID=...; AuthCookie=...`

### RBAC seed (dev)

Until proper SK / SHASTIYA_KORMI users are seeded, dev user 171
(`sumaiya.sarkar.171@uhis.test`, role `HEALTH_FACILITY_ADMIN`, suite `web`)
can be granted access to the data endpoints by patching the
`api_role_permission` table for `SPICE_SERVICE`, `ADMIN_SERVICE`, and
`FHIR_MAPPER_SERVICE`. See the parent repo's db-doctor agent or apply manually:

```sql
UPDATE api_role_permission
SET roles = roles || 'HEALTH_FACILITY_ADMIN'::varchar
WHERE api IN ('/patient/list','/patient/search','/household/list','/healthfacility/villages/id')
  AND NOT ('HEALTH_FACILITY_ADMIN' = ANY(roles));

INSERT INTO api_role_permission (method, api, roles, type, service_name, is_active, is_deleted)
VALUES
 ('POST', '/patient/list',   ARRAY['CHW','REGION_ADMIN','SHASTIYA_KORMI','HEALTH_FACILITY_ADMIN']::varchar[], 'PRIVATE', 'FHIR_MAPPER_SERVICE', true, false),
 ('POST', '/patient/search', ARRAY['CHW','REGION_ADMIN','SHASTIYA_KORMI','HEALTH_FACILITY_ADMIN']::varchar[], 'PRIVATE', 'FHIR_MAPPER_SERVICE', true, false),
 ('POST', '/household/list', ARRAY['CHW','REGION_ADMIN','SHASTIYA_KORMI','HEALTH_FACILITY_ADMIN']::varchar[], 'PRIVATE', 'FHIR_MAPPER_SERVICE', true, false);

-- flush role cache:
-- docker exec platform-setup-redisservice-1 redis-cli FLUSHALL
```

This is a **dev-only** workaround. Production deployment must use a properly
seeded SK/CHW role.

---

## Project Layout

```
lib/
  main.dart                            entry point, lifecycle observer
  app/
    router.dart                        GoRouter + redirect rules
    theme.dart
  core/
    config/
      app_config.dart                  build-time env (single source of truth)
    api/
      api_client.dart                  Dio + cookie session + interceptors
      endpoints.dart                   path constants
      browser_adapter_stub.dart        no-op on native
      browser_adapter_web.dart         enables withCredentials on web
    auth/
      auth_repository.dart             login, profile, biometric persistence
      auth_state.dart                  ChangeNotifier: status, locked, bio
      biometric_service.dart           local_auth wrapper
  features/
    login/login_screen.dart            password form
    lock/lock_screen.dart              biometric splash (cold-start + bg lock)
    dashboard/
      dashboard_screen.dart            count tiles, search entry, opt-in dialog
      dashboard_repository.dart        patientCount, householdCount
    search/
      global_search_bar.dart           Material 3 SearchAnchor.bar + SearchView
      global_search_repository.dart    fans out to patient + household repos in parallel
      patient_search_repository.dart   patient REST search wrapper
      household_search_repository.dart paginated client-side filter

android/                                Flutter scaffold + FlutterFragmentActivity
web/                                    flutter web shell (for E2E)
e2e/                                    Playwright web tests
scripts/
  build_apk.sh                          flavor-aware APK build
  run.sh                                flavor-aware flutter run
env.example.json                        template
```

---

## End-to-End Tests

A Playwright suite drives the Flutter web build through the Android-emulator-
hosted backend.

```bash
# 1. build web bundle with same-origin API
flutter build web --dart-define-from-file=env.development.json
# (note: change API_BASE_URL=http://localhost for web cross-port CORS)

# 2. serve
cd build/web && python3 -m http.server 5050 --bind localhost &

# 3. run tests
cd e2e
npm install
npx playwright install chromium
npx playwright test --headed
```

Tests:
- `tests/01-smoke.spec.ts` — Flutter shell mounts, UHIS Next title renders.
- `tests/02-login.spec.ts` — form fields present, credentials post → dashboard.
- `tests/03-patient-search.spec.ts` — chips + name/phone/NID query.
- `tests/04-household-search.spec.ts` — chips + progress indicator + results.

Web build requires `SemanticsBinding.instance.ensureSemantics()` (already in
`main.dart`) so Flutter renders the ARIA tree Playwright queries against.

---

## Troubleshooting

| Symptom                                       | Likely cause                                                                  | Fix                                                                                          |
|-----------------------------------------------|-------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `SocketException: Network is unreachable, 10.0.2.2` | Emulator booted with Airplane Mode on                                       | `adb shell settings put global airplane_mode_on 0 && adb shell svc wifi enable`             |
| `Invalid credentials` 401 every login         | User locked by 5 failed attempts                                              | `UPDATE "user" SET is_blocked=false, invalid_login_attempts=0 WHERE id=...`                  |
| `Failed to load profile (401)`                | Cookie not being sent — server expects `client: web` header                   | Check `AppConfig.apiClient` is `web` and the Cookie header carries both `JSESSIONID` + `AuthCookie` |
| Profile 401 on Android but 200 via curl       | `AuthCookie` has `Secure` flag — cookie_jar refuses on plain HTTP             | Already handled: response interceptor strips `Secure` + `Domain` before saving               |
| 401 on `/patient/list` (with valid session)   | User's role lacks permission on `SPICE_SERVICE` / `FHIR_MAPPER_SERVICE`        | Apply RBAC seed SQL above + `redis-cli FLUSHALL`                                            |
| Biometric prompt never appears                | No fingerprint / PIN enrolled on AVD                                          | Settings → Security & privacy → Device unlock → set PIN → add fingerprint                    |
| `BiometricPrompt` shows native PIN screen     | Expected fallback when `biometricOnly: false` and no biometric is enrolled    | Enrol fingerprint to skip PIN                                                                |
| Web E2E `flt-glass-pane: hidden` errors       | Semantics tree not enabled                                                    | `SemanticsBinding.instance.ensureSemantics()` in `main.dart` — already in place              |
| Tests can't login from `http://localhost:5050`| Origin not on nginx allow-list                                                | nginx allows `localhost(:port)` already. Use `localhost`, not `127.0.0.1`.                   |

---

## Security Notes

- **No password / hash at rest.** Only ephemeral session tokens (`JSESSIONID` + `AuthCookie`) and tenantId.
- **Android Keystore** backs the `flutter_secure_storage` writes.
- **HmacSHA512 client hashing** matches the React frontend so the server never sees plaintext.
- **`usesCleartextTraffic="true"`** is enabled for dev (HTTP to `10.0.2.2`). Production must move to HTTPS — flip the manifest flag back to `false` and configure `network_security_config.xml`.
- **No `FLAG_SECURE`** yet — the dashboard is visible in the recent-apps thumbnail. Deferred.
- **`secure=false` cookie storage** is intentional for dev; production over HTTPS should remove the strip-Secure interceptor.

---

## Roadmap / Deferred

- iOS support (Face ID / Touch ID + lifecycle).
- `FLAG_SECURE` for screenshot + recents-thumbnail protection.
- Server-side household search endpoint (currently client-side filter).
- Offline cache + sync (FHIR `$everything` + `_since`).
- AI rationale UI (per architecture tenet #6 "Explainable").
- OIDC / SMART-on-FHIR auth (replacing the cookie + AuthCookie scheme).
- Patient + household detail screens.
- Multi-account picker (multiple biometric-bound sessions per device).
- Bind stored cookies to a biometric-only Android Keystore key (currently Keystore-encrypted but not biometric-gated at OS level).

---

## License

See `LICENSE`.
