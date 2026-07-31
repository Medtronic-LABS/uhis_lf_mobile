# Plan: Programme-smart dashboard card labels

**Feature:** Replace "No programme enrolment recorded" on dashboard patient cards with
meaningful, visit-count-aware labels ("ANC Visit 3 due", "NCD checkup", "Enrolled", etc.)
matching the v13 design.

**Status:** Research complete. Ready to implement. Not yet started.
**Branch:** `feat/dashboard-header-pixel-match` (PR #62)

---

## Problem

Dashboard `MissionQueueCard` shows **"No programme enrolment recorded"** in the reason badge.
Root cause is two-layer:

1. `RiskScoringService` (`lib/core/risk/risk_scoring_service.dart:234`) adds raw driver tag
   `'no-programme'` as a sentinel when no clinical signal fires. `RiskRationale.formattedReasons`
   converts it to the string `'No programme enrolment recorded'`.

2. `MissionDashboardService._worklistToQueueItem()` (`lib/core/mission/mission_dashboard_service.dart:551`)
   tries to strip it with `.where((r) => r != 'no-programme')` — but `entry.reasons` holds
   **formatted** strings, not raw tags. The filter is a no-op; the fallback `'Scheduled visit'` is
   never reached.

Beyond the bug, `reason` is never built from actual programme/visit data. The v13 design requires
programme-specific, visit-count-aware labels.

---

## v13 Design Spec (from `apon_sushashthya_v13.html`)

Badge geometry: `fontSize:10, fontWeight:700, padding:(2,7), borderRadius:5`

| Patient state | Badge label | Background | Text |
|---|---|---|---|
| ANC enrolled, N > 0 visits done | `ANC Visit N+1 due` | `#FDF2F8` | `#9D174D` |
| ANC enrolled, 0 visits | `Enrolled` | `#FDF2F8` | `#9D174D` |
| PNC enrolled, N > 0 visits done | `PNC Visit N+1 Due` | `#EEF0FF` | `#4C1D95` |
| PNC enrolled, 0 visits | `Enrolled` | `#EEF0FF` | `#4C1D95` |
| IMCI / EPI enrolled | `Child immunisation` | `#FFFBEB` | `#92400E` |
| NCD enrolled | `NCD checkup` | `#FFFBEB` | `#92400E` |
| TB enrolled | `TB check` | `#F0FDF4` | `#065F46` |
| No programme (eligible by band) | `New visit` | `#EEF0FF` | `#1B2B5E` |

---

## Data Flow: `member-assessment-history` → visit count → card label

```
POST /offline-service/offline-sync/member-assessment-history
  (lib/core/api/endpoints.dart: offlineSyncMemberAssessmentHistory)

Response shape: AssessmentHistoryItem[]
  (lib/core/models/assessment_history_item.dart)
  Key fields:
    .householdMemberId  → resolved to patient_id via MemberDao
    .serviceProvided    → Programme.fromTag() → Programme enum
                          (e.g. "ANC" → Programme.anc, "NCD" → Programme.ncd)
    .visitDate          → occurred_at epoch ms
    .nextFollowUpDate   → next_due_at

_syncAssessmentHistoryProgrammes() in offline_sync_service.dart (~line 1108)
  → INSERT INTO assessments  (id=encounterId, patient_id, kind=serviceProvided, occurred_at)
  → INSERT INTO patient_programmes (patient_id, programme=Programme.wireTag)
  → PATCH patients (last_visit_at, next_due_at) via patchVisitTiming()

WorklistRepository.load()
  → PatientDao.queryWorklist()           → List<Patient>
  → PatientProgrammesDao.programmesForMany(ids)   → Map<patientId, Set<Programme>>
  [NEW] AssessmentDao.visitCountsByPatients(ids, ancKinds)  → Map<patientId, int>
  [NEW] AssessmentDao.visitCountsByPatients(ids, pncKinds)  → Map<patientId, int>
  → WorklistEntry(programmes, ancVisitCount, pncVisitCount)

MissionDashboardService._worklistToQueueItem()
  [NEW] _programmeReason(entry)  → "ANC Visit 3 due" | "Enrolled" | "NCD checkup" | …
  → MissionQueueItem.reason

MissionQueueCard → MissionReasonBadge
  [UPDATE] _badgeColors(item.primaryProgramme)  → v13 palette
  → Text(item.reason)
```

---

## Implementation — 6 files

### File 1: `lib/core/db/assessment_dao.dart`
Add bulk visit-count query (new method):

```dart
/// Returns completed visit count per patient, keyed by patient_id.
/// Single SQL round-trip; used by WorklistRepository.load().
Future<Map<String, int>> visitCountsByPatients(
  List<String> patientIds,
  List<String> kinds,
) async {
  if (patientIds.isEmpty || kinds.isEmpty) return const {};
  final db = await _db;
  final pp = List.filled(patientIds.length, '?').join(',');
  final kp = List.filled(kinds.length, '?').join(',');
  final rows = await db.rawQuery(
    'SELECT patient_id, COUNT(*) AS cnt FROM assessments '
    'WHERE patient_id IN ($pp) '
    'AND UPPER(kind) IN ($kp) '
    'GROUP BY patient_id',
    [...patientIds, ...kinds.map((k) => k.toUpperCase())],
  );
  return {for (final r in rows) r['patient_id'] as String: r['cnt'] as int};
}
```

Check the existing constructor/`_db` pattern by reading the file first.

---

### File 2: `lib/core/models/worklist_entry.dart`
Add two new fields with defaults (non-breaking):

```dart
// Add to constructor as optional named params with default 0:
final int ancVisitCount;   // completed ANC visits from server-synced assessments table
final int pncVisitCount;   // completed PNC visits from server-synced assessments table
```

Add to the `copyWith` method (if it exists) as optional params.

---

### File 3: `lib/features/worklist/worklist_repository.dart`

**a.** Inject `AssessmentDao` into the constructor:
```dart
WorklistRepository({
  required PatientDao patients,
  required PatientProgrammesDao programmes,
  required AssessmentDao assessments,   // ← ADD
  ...
})
```

**b.** Inside `load()`, after the existing `programmesForMany` call:
```dart
const ancKinds = ['ANC', 'PREGNANCY', 'PREGNANT', 'EMTCT'];
const pncKinds = ['PNC', 'POSTNATAL'];

final ancCounts = await _assessmentDao.visitCountsByPatients(ids, ancKinds);
final pncCounts = await _assessmentDao.visitCountsByPatients(ids, pncKinds);
```

**c.** Pass into `_toEntry()`:
```dart
WorklistEntry _toEntry(
  Patient p,
  Set<Programme> programmes, {
  int ancVisitCount = 0,
  int pncVisitCount = 0,
}) { … }
```

Same change applies to `recomputeAllAfterSync()` if it uses `_toEntry`.

---

### File 4: `lib/core/mission/mission_dashboard_service.dart`

**a.** Fix the broken filter (~line 552):
```dart
// BEFORE (compares raw tag, never matches formatted string):
entry.reasons.where((r) => r != 'no-programme')

// AFTER:
entry.reasons.where((r) => r != 'No programme enrolment recorded')
```

**b.** Replace the `reason` assignment with `_programmeReason(entry)`:
```dart
final reason = _programmeReason(entry);

// ─── new static helper ─────────────────────────────────────────────────
static String _programmeReason(WorklistEntry entry) {
  final p = entry.programmes;
  if (p.contains(Programme.anc)) {
    return entry.ancVisitCount > 0
        ? '${MissionDashboardStrings.ancVisitLabel} ${entry.ancVisitCount + 1} due'
        : MissionDashboardStrings.enrolled;
  }
  if (p.contains(Programme.pnc)) {
    return entry.pncVisitCount > 0
        ? '${MissionDashboardStrings.pncVisitLabel} ${entry.pncVisitCount + 1} Due'
        : MissionDashboardStrings.enrolled;
  }
  if (p.contains(Programme.imci) || p.contains(Programme.epi)) {
    return MissionDashboardStrings.childImmunisation;
  }
  if (p.contains(Programme.ncd)) return MissionDashboardStrings.ncdCheckup;
  if (p.contains(Programme.tb))  return MissionDashboardStrings.tbCheck;
  return MissionDashboardStrings.newVisit;
}
```

---

### File 5: `lib/core/constants/app_strings.dart`
Add to `MissionDashboardStrings` class:

```dart
static const String enrolled          = 'Enrolled';
static const String ancVisitLabel     = 'ANC Visit';
static const String pncVisitLabel     = 'PNC Visit';
static const String childImmunisation = 'Child immunisation';
static const String ncdCheckup        = 'NCD checkup';
static const String tbCheck           = 'TB check';
static const String newVisit          = 'New visit';
```

---

### File 6: `lib/features/visit/widgets/mission_queue_card.dart`
Change `MissionReasonBadge._badgeColors()` from priority-keyed to programme-keyed:

```dart
// BEFORE:
(Color, Color) _badgeColors(MissionPriority p, LeapfrogColors tokens) { … }
// Called as: _badgeColors(item.priority, tokens)

// AFTER:
(Color, Color) _badgeColors(Programme programme) {
  switch (programme) {
    case Programme.anc:
      return (const Color(0xFFFDF2F8), const Color(0xFF9D174D));
    case Programme.pnc:
      return (const Color(0xFFEEF0FF), const Color(0xFF4C1D95));
    case Programme.imci:
    case Programme.epi:
    case Programme.ncd:
      return (const Color(0xFFFFFBEB), const Color(0xFF92400E));
    case Programme.tb:
      return (const Color(0xFFF0FDF4), const Color(0xFF065F46));
    default:
      return (const Color(0xFFEEF0FF), const Color(0xFF1B2B5E));
  }
}
// Called as: _badgeColors(item.primaryProgramme)
```

`item.primaryProgramme` already exists on `MissionQueueItem` (resolves to the highest-priority
programme in `programmes` set, falls back to `Programme.unknown`).

---

## DI wiring (`lib/main.dart`)

`AssessmentDao` is already instantiated somewhere in `main.dart` (it is used by other repositories).
Find the existing singleton and pass it to both `WorklistRepository(...)` call sites.

If `AssessmentDao` is not yet in `main.dart`, create it the same way as other DAOs
(takes `AppDatabase` reference).

---

## What to check before starting

1. Read `lib/core/db/assessment_dao.dart` fully — confirm `_db` getter name and existing method patterns.
2. Read `lib/features/worklist/worklist_repository.dart` constructor and `load()` to see exact
   current param names.
3. Read `lib/main.dart` — grep for `AssessmentDao` to confirm it is already constructed or needs
   to be added.
4. Read `lib/core/models/worklist_entry.dart` — confirm `copyWith` exists before adding params.

---

## Verification steps

1. `flutter analyze lib/` — zero new errors
2. `flutter test test/core/` — all 216 tests pass
3. On device with synced data:
   - ANC patient with 2 prior visits → badge: `ANC Visit 3 due` (pink)
   - ANC patient newly enrolled → badge: `Enrolled` (pink)
   - NCD patient → badge: `NCD checkup` (amber)
   - IMCI patient → badge: `Child immunisation` (amber)
   - No-programme patient on worklist → badge: `New visit` (navy-info)
4. Existing dashboard features (filter chips, inline search, category filter) unchanged

---

## Continuation prompt for next session

Paste this at the start of a new Claude Code session in the `uhis_lf_mobile` directory:

---

> **Context:** I'm continuing implementation of programme-smart dashboard card labels in the
> Flutter CHW app `uhis_lf_mobile` (branch `feat/dashboard-header-pixel-match`, PR #62).
>
> The plan is at `PLAN-programme-card-labels.md` in the repo root. Please read it first.
>
> **Summary of what's done:**
> - Dashboard filter race condition fixed ✓
> - All category chips always visible (greyed when empty) ✓
> - Search bar visual restored to original pill design ✓
> - Routine (upcoming) patients excluded from 8-card round-robin ✓
>
> **What to implement now (in order):**
> 1. Read `PLAN-programme-card-labels.md` for full context and exact code
> 2. Add `visitCountsByPatients()` to `lib/core/db/assessment_dao.dart`
> 3. Add `ancVisitCount` / `pncVisitCount` to `lib/core/models/worklist_entry.dart`
> 4. Wire the count queries into `lib/features/worklist/worklist_repository.dart`
> 5. Fix filter bug + add `_programmeReason()` in `lib/core/mission/mission_dashboard_service.dart`
> 6. Add string constants in `lib/core/constants/app_strings.dart`
> 7. Update badge colours in `lib/features/visit/widgets/mission_queue_card.dart`
> 8. Wire `AssessmentDao` into `lib/main.dart` if not already there
> 9. Run `flutter analyze lib/` and `flutter test test/core/` before committing
>
> Then run it on the emulator to verify visit-count labels and badge colours match the v13 design.
