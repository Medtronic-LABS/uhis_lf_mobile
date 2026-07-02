# uhis_lf_mobile — Flutter SK App

**Apon Sushashthya (আপন সুস্বাস্থ্য)** — Offline-first community health worker app for UHIS Leapfrog / Leap Well Project.
Flutter 3.x · Provider · GoRouter · SQLCipher · Dart SDK ^3.12

Parent context: `../CLAUDE.md` (leapfrog-setup) and `../../CLAUDE.md` (platform-setup).  
**Canonical product spec:** `../design/apon-sushashthya-v1.md` — read before implementing any worklist, visit flow, risk scoring, or CDSS feature.

## Visit Architecture

All visits follow a 3-step progressive disclosure model:

| Step | Screen | AI Component |
|---|---|---|
| Step 1 | Symptom check ("How are you?") | AI Scribe — voice → animated symptom cards |
| Step 2 | Vitals + full clinical form | AI Scribe — single banner fills all fields in sequence |
| Step 3 | AI Recommendation | CDSS finding cards + counselling accordion + WhatsApp draft |

## AI Worklist — Band + Modifier Risk Model

Dashboard sort order is driven by **band + modifier** (not a composite score). The worst single clinical finding sets the band; modifiers rank within the band.

| Band | Label | Status Pill | Border |
|---|---|---|---|
| 1 | Severe | NOW (pulsing) | Red — only when CCE alert or danger sign present |
| 2 | Moderate | TODAY | Amber |
| 3 | Mild | TODAY / THIS WEEK | Navy |
| 4 | Routine | ROUTINE | Grey (`#E5E7EB`) |

**Modifiers:** `a` = additional risk (comorbidity, first pregnancy, age ≥ 60, GA ≥ 36 wks) — ranks higher within band. `b` = overdue — longer overdue = higher within band, but below `a`. Sort sequence: `1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4`. Pregnant patients always rank above non-pregnant in the same band.

**Band and modifier are never shown to the SK** — they only drive sort order.

## Key Clinical Thresholds

**ANC:**
- BP ≥ 160/110 → Band 1 (urgent referral)
- BP + weight + urine protein all rising across 3 visits → Band 2 (pre-eclampsia pattern)
- BP ≥ 140/90 single reading → Band 2
- Hb < 7 g/dL → Band 1; 7.0–9.9 → Band 2; 10.0–10.9 → Band 3
- Any danger sign → Band 1 immediately (no pattern wait)
- Fasting glucose ≥ 5.1 mmol/L → GDM referral (Band 2)
- GA ≥ 36 weeks → Modifier a applied (Band 3)

**NCD:**
- One-sided weakness (stroke sign) → Band 1 regardless of BP
- BP ≥ 180/110 → Band 1; 160–179/100–109 → Band 2; 140–159/90–99 → Band 3; 130–139/85–89 → Band 4
- Fasting glucose ≥ 18 mmol/L → Band 1; 10.0–17.9 → Band 2; 7.0–9.9 → Band 3; 6.1–6.9 → Band 4
- Comorbid HTN + DM → Modifier a applied; age ≥ 60 → Modifier a applied

**Note:** Device Bluetooth integration (BP monitor, scale) is out of scope for V1 — all vitals entered manually via AI Scribe voice fill or keyboard.

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
| `scribeRealtimeTranscribe` | `/ai-scribe-service/scribe/realtime/transcribe` | WS |

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

## Real-Time ASR (Beta) — `lib/features/realtime_asr/`

Lives **inside `ScribeBanner`** (`lib/features/scribe/widgets/scribe_banner.dart`) — a small "LIVE" toggle in the banner's top-right corner, so it appears everywhere AI Scribe already does (Step 1 triage picker, Step 2 ANC/NCD/TB/IMCI assessment forms), not as a separate screen or Settings entry. It's an independent live-listening aid: transcript + on-demand symptom preview against the ai-scribe-service, with nothing fed into accept/reject or the saved note — AI Scribe's record → upload → poll → review flow remains the actual note path.

`ScribeBanner` owns its own `RealtimeAsrController` (created in `initState`, disposed with the widget) alongside the `ScribeController` it already consumes. The "LIVE" toggle and the main record tap are mutually exclusive — each disables the other while active, since both would otherwise try to capture the mic at once:

1. `RealtimeAsrController.start()` — mic permission via the same `ScribePermissionService` AI Scribe uses, then opens `WS scribeRealtimeTranscribe` via `RealtimeAsrService` (auth headers built from the shared `ApiClient` session: Bearer token, cookies, tenantId)
2. Mic captured via `record`'s `AudioRecorder.startStream(RecordConfig(encoder: pcm16bits, sampleRate: 16000))` — raw PCM16 chunks wrapped in a WAV header and sent as `{"type": "audio", ...}` frames
3. Transcript segments arrive continuously and render inline in the banner; `extractNow()` (auto every 10s, or tap "Extract Now") sends `{"type": "extract", "transcript": ...}` and renders the `{"type": "symptoms", ...}` reply (`RealtimeClinicalFields` — same 7-field shape as the batch scribe API) as a one-line summary
4. Stopping flushes, requests one final extraction, and **waits for its reply (bounded timeout) before sending `stop`** — sending `stop` immediately after `extract` would let the server cancel the in-flight extraction

**Native-only**: `IOWebSocketChannel` is required to set the `Authorization`/`Cookie`/`tenantId` handshake headers this API needs; browsers don't allow custom WS headers, so on web the toggle surfaces the "not available" error inline instead of connecting (see `realtime_asr_channel_io.dart` / `realtime_asr_channel_web.dart` conditional import, same pattern as `api_client.dart`'s web/native split).

## AI Visit Briefing — `lib/features/visit/briefing/`

Pre-visit briefing cards shown inside `SymptomPickerScreen` (the "What symptoms does the patient have?" screen). Cards are fetched asynchronously while the SK reviews symptoms; they collapse/expand on tap.

**Three cards (in order):**

| Card | Icon | Content |
|---|---|---|
| Before You Knock | `psychology_outlined` (navy) | AI headline + 3-5 clinical bullet points summarising the patient's most important concerns |
| Today's Priorities | `priority_high_rounded` (orange) | Numbered list of 3-5 specific, actionable priorities for this visit (e.g. "Check BP: last reading 155/95") |
| Suggested Discussion Points | `chat_bubble_outline` (teal) | Culturally appropriate opening line + topic sections (heart/baby/nutrition/medication/lungs/home/checkup icons) with 2-3 open-ended questions each |

**Data flow:**
1. `SymptomPickerScreen._loadPatientContext()` builds `PatientContext` from local DB
2. `_startBriefingFetch(ctx)` fires immediately after — constructs `BriefingRequest` from `PatientContext`, `VitalsRepository.recentByVisit()`, and `FollowUpRepository.openForPatientLocal()`
3. `VisitBriefingRepository.generate(req)` calls the AI visit briefing service
4. Cards update when `_briefingData` arrives; loading skeleton shown during fetch
5. **Graceful degradation**: Card 1 falls back to local rule-based context chips; Cards 2/3 show "AI unavailable" message

**Service routing:**
- Gateway path: `/ai-visit-briefing-service/briefing/generate` (routed through nginx)
- Direct local path: `/briefing/generate` (when `AI_SERVICE_URL` dart-define is set)
- `AppConfig.aiServiceBaseUrl` (`--dart-define=AI_SERVICE_URL=http://10.0.2.2:8096`) — causes `VisitBriefingRepository` to use a separate Dio instance pointed at the local service
- Local AI service: `leapfrog-setup/ai-visit-briefing-service/` (FastAPI, port 8096, Gemini `gemini-2.5-flash`)

**Key models — `lib/features/visit/briefing/briefing_models.dart`:**
- `VisitBriefingResponse` — `briefingCard`, `todaysPriorities`, `suggestedDiscussionPoints`, `transitionPrompt`
- `BriefingCardContent` — `headline: String`, `points: List<String>`
- `SuggestedDiscussionPoints` — `openingLine: String`, `sections: List<ConversationSection>`
- `ConversationSection` — `topic`, `icon` (one of: heart/baby/nutrition/medication/lungs/home/checkup), `questions`

**Strings:** `TriageStrings.briefCard1Title/briefCard2Title/briefCard3Title` in `app_strings.dart`

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
