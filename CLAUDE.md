# uhis_lf_mobile — Flutter SK App

Offline-first community health worker app for UHIS Leapfrog.
Flutter 3.x · Provider · GoRouter · SQLCipher · Dart SDK ^3.12

Parent context: `../CLAUDE.md` (leapfrog-setup) and `../../CLAUDE.md` (platform-setup).

## Tech stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.x / Dart |
| State | Provider (`provider: ^6.1`) |
| Navigation | GoRouter (`go_router: ^14.6`) |
| HTTP | Dio (`dio: ^5.7`) with cookie jar |
| Local DB | sqflite_sqlcipher (AES-256 per-device key) |
| Secure storage | flutter_secure_storage (KeyStore-backed) |
| Biometric | local_auth |
| Audio (scribe) | record (`record: ^7`) |
| Notifications | flutter_local_notifications |

## Directory layout

```
lib/
  main.dart
  app/
    router.dart          ← GoRouter definition (all routes)
  core/
    api/
      endpoints.dart     ← ALL backend paths (only approved set)
      api_client.dart
    auth/
      auth_state.dart    ← ChangeNotifier, login/logout/lock
      auth_repository.dart
    cdss/
      models/            ← CdssPatientProfile, BpReading, result types
      findrisc_calculator.dart
      framingham_calculator.dart
      cusum_calculator.dart
      ewma_calculator.dart
      slope_calculator.dart
      mini_piers_calculator.dart
      cdss_engine.dart   ← CdssEngine.evaluate() → CdssEngineOutput
    config/
      app_config.dart    ← typed accessor for --dart-define values
    constants/
      app_strings.dart   ← ALL user-facing copy (localization seam)
    db/
      app_database.dart  ← SQLCipher open + stale-DB recovery
      bp_history_dao.dart
    models/
      programme.dart     ← Programme enum (imci/anc/pnc/ncd/tb/epi/nutrition/fp/cataract/eyeCare)
  features/
    dashboard/           ← MissionDashboardScreen (/home)
    household/           ← HouseholdListScreen + HouseholdDetailScreen (/patients/*)
    login/               ← LoginScreen (/login)
    lock/                ← LockScreen (/lock) + LockBarrier widget
    onboarding/          ← OnboardingScreen (/onboarding)
    patient/             ← PatientContextScreen + VisitDetailsScreen (/patients/:id)
    pin/                 ← PinSetupScreen + PinUnlockScreen (/pin-*)
    referral/            ← ReferralListScreen + ReferralDetailScreen (/tasks/*)
    scribe/              ← ScribeController, ScribeSession, SoapFieldExtractor
    search/              ← GlobalSearchBar, member/household search repos
    sync/                ← SyncProgressScreen (/sync)
    visit/
      composer/          ← SectionRegistry, CdsRules, SectionedAssessmentScreen
      pathway/           ← PathwayEngine, PathwayRulesV1
      triage/            ← SymptomPickerScreen, TriageResultScreen, UnifiedSymptomCatalog
      forms/             ← FieldDef, FieldType, FormSection
      VisitFormScreen.dart
      VisitLandingScreen.dart
    worklist/            ← WorklistScreen + WorklistRepository
```

## Routes

| Screen | Route | Auth required |
|---|---|---|
| Splash | `/` | No |
| Login | `/login` | No |
| Lock | `/lock` | Partial (session expired) |
| Onboarding | `/onboarding` | Yes |
| Sync | `/sync` | Yes |
| PIN setup | `/pin-setup` | Yes |
| PIN unlock | `/pin-unlock` | Partial |
| Dashboard | `/home` | Yes |
| Member list | `/patients` | Yes |
| Household list | `/patients/households` | Yes |
| Household detail | `/patients/household/:id` | Yes |
| Patient context | `/patients/:id` | Yes |
| Start visit | `/patients/visit/:patientId/start` | Yes |
| Symptom triage | `/patients/visit/:visitId/triage` | Yes |
| Triage result | `/patients/visit/:visitId/triage-result` | Yes |
| Assessment form | `/patients/visit/:visitId/form` | Yes |
| Tasks / referrals | `/tasks` | Yes |
| Task detail | `/tasks/:id` | Yes |
| AI Scribe tab | `/map` | Yes |

## Auth

- Endpoint: `POST /auth-service/session` (application/x-www-form-urlencoded)
- Fields: `username` + `password` (HmacSHA512-hashed with `AppConfig.passwordHashKey`)
- Dev hash key: `spice_uat` (set via `--dart-define=PASSWORD_HASH_KEY=spice_uat`)
- Response header: `Authorization: Bearer <token>`
- Session persisted via flutter_secure_storage (KeyStore-backed); biometric unlocks the stored session
- **Never store plaintext password or hash on device**

## Approved backend endpoints (`lib/core/api/endpoints.dart`)

All paths are listed here. Do NOT add a path not in this file and not in the Postman collection.

| Constant | Path | Method |
|---|---|---|
| `login` | `/auth-service/session` | POST |
| `logout` | `/auth-service/logout` | POST |
| `staticUserData` | `/spice-service/static-data/user-data` | POST |
| `offlineSyncFetch` | `/offline-service/offline-sync/fetch-synced-data` | POST |
| `offlineSyncMemberAssessmentHistory` | `/offline-service/offline-sync/member-assessment-history` | POST |
| `offlineSyncCreate` | `/offline-service/offline-sync/create` | POST |
| `fhirObservationByEncounter(id)` | `/fhir-server/fhir/Observation?encounter=...` | GET |
| `scribeTranscribe` | `/ai-scribe-service/scribe/transcribe` | POST |
| `scribeResult(jobId)` | `/ai-scribe-service/scribe/results/{jobId}` | GET |
| `scribeNote(noteId)` | `/ai-scribe-service/scribe/notes/{noteId}` | GET |
| `scribeAccept(noteId)` | `/ai-scribe-service/scribe/notes/{noteId}/accept` | POST |
| `scribeReject(noteId)` | `/ai-scribe-service/scribe/notes/{noteId}/reject` | POST |
| `scribeUploadInit` | `/ai-scribe-service/upload/init` | POST |
| `scribeUploadChunk(id,n)` | `/ai-scribe-service/upload/{id}/chunk/{n}` | PUT |
| `scribeUploadStatus(id)` | `/ai-scribe-service/upload/{id}/status` | GET |
| `scribeUploadComplete(id)` | `/ai-scribe-service/upload/{id}/complete` | POST |

## Database — SQLCipher

- Per-device 256-bit key generated once and stored in Android EncryptedSharedPreferences
- `AppDatabase.open()` wraps `sqlcipher.openDatabase` in a try-catch; detects stale plain-SQLite via `DatabaseException.isOpenFailedError()` or `'not a database'` string → deletes file → recreates encrypted DB
- Schema version tracked via `schemaVersion` constant; migrations in `_onUpgrade`

## CDSS engine — `lib/core/cdss/`

Pure-Dart, no Flutter deps. All inputs/results are plain Dart classes.

```dart
CdssEngine.evaluate(
  profile: CdssPatientProfile,   // age, sex, BMI, BP, meds, lifestyle
  bpHistory: List<BpReading>,    // sorted oldest-first from BpHistoryDao
  maternal: MaternalProfile?,    // GA weeks, SBP, proteinuria, symptoms
) → CdssEngineOutput
```

Algorithms run when inputs are available:
- **FINDRISC** — always (partial score if waist missing); trigger ≥12
- **Framingham** — age ≥18 + BMI + SBP present; trigger ≥10% 10-yr risk
- **CUSUM / EWMA / Slope** — ≥2 BP readings; trend alerts wired into CDS banners
- **miniPIERS** — maternal profile present; trigger ≥25%, critical ≥50%

`BpHistoryDao.getForPatient(patientId)` reads `local_assessments` for prior systolic values.

## AI Scribe — `lib/features/scribe/`

Async flow:
1. `ScribeController.startRecording()` — mic permission check via `ScribePermissionService`
2. `stopAndUpload()` — if audio ≥1 MB use chunked upload (`scribeUploadInit` → chunks → `scribeUploadComplete`), else `scribeTranscribe` direct POST
3. Poll `scribeResult(jobId)` until `status == 'completed'`
4. `SoapFieldExtractor.extract(soapText)` — maps SOAP sections to assessment form field values
5. User reviews the proposal → `scribeAccept` or `scribeReject`; rationale snapshot logged on accept

## Visit composer — `lib/features/visit/composer/`

- `SectionRegistry` — maps active `Programme` set → ordered `FormSection` list with `FieldDef` entries
- `CdsRules.evaluate(fieldValues, activePathways, cdssOutput?)` → `List<CdsAlert>`
- `SectionedAssessmentScreen` — 3-step form: Triage → Assessment → Review & Submit
- Programme enum values: `imci`, `anc`, `pnc`, `ncd`, `tb`, `epi`, `nutrition`, `familyPlanning`, `cataract`, `eyeCare`, `unknown`

## Engineering standards

All code in this app must satisfy the **Engineering Design Standards** defined in `../../CLAUDE.md` and `../CLAUDE.md`. Key reminders specific to this app:

- All user-facing strings: `lib/core/constants/app_strings.dart` — no hardcoded copy in widgets
- All config (base URL, hash key, env): `lib/core/config/app_config.dart` via `--dart-define`
- Repositories throw typed exceptions; `AuthState`/screens map to localized messages
- No business logic in widgets; no raw HTTP in screens — go through repository layer
- New public behavior ships with a unit test in `test/`

## Running

```bash
# Dev (local backend)
flutter run --dart-define=BASE_URL=http://10.0.2.2 --dart-define=PASSWORD_HASH_KEY=spice_uat

# Run unit tests
flutter test

# Run all CDSS algorithm tests
flutter test test/core/cdss/

# Check analysis
flutter analyze
```

## CI / Confluence docs

`.github/workflows/confluence-docs.yml` runs on push to main and publishes 8 pages to
`mdtlabs.atlassian.net/wiki` space `UNL` (parent page `712540457`).
Script: `scripts/publish_confluence.py` — parses Dart source live (no static snapshots).
Secrets required: `CONFLUENCE_BASE_URL`, `CONFLUENCE_EMAIL`, `CONFLUENCE_API_TOKEN`.
Vars required: `CONFLUENCE_SPACE_KEY=UNL`, `CONFLUENCE_PARENT_PAGE_ID=712540457`.
