# Data Sync Architecture — Gap Analysis

## Context

Architecture-wide review of the offline data-sync system — three parallel research passes covered
the push path, the pull path, and triggers/connectivity/conflict handling, followed by an independent
senior-architect review pass that verified every critical finding against the real code and
stress-tested each proposed fix. The review confirmed all 13 originally-found gaps hold up with no
overstatement, surfaced one genuine flaw in a proposed fix (a nested-transaction deadlock, #5), two
sequencing dependencies (#1 before #6, #3 before relying on #5), and a set of gaps in the analysis
itself (observability, testing, rollout) — all incorporated below. A 14th finding surfaced during
follow-up discussion of the `local_assessments`/`assessments` table split, and a proposed idea
(deleting local data once confirmed synced) was evaluated and explicitly rejected.

## Architecture at a glance

- **Push** (local → server): two independent, largely duplicated implementations —
  `OfflinePushService.pushAll()` (households + members + assessments + follow-ups) and
  `AssessmentRepository._batchSync()` (assessments + follow-ups + new members only). Both POST
  `offline-sync/create` then poll `offline-sync/status`.
- **Pull** (server → local): `OfflineSyncService` — `coldSync`/`warmSync`/`reloginSync`, POSTs
  `offline-sync/fetch-synced-data` (+ a second call, `member-assessment-history`), then merges into
  SQLCipher via per-table DAO upserts.
- **Triggers:** 15 distinct call sites (login, PIN/biometric unlock, pull-to-refresh, manual "Offline
  Sync" screen, connectivity-restore, visit/form submits, logout flush) — no periodic/background job.
- **Connectivity:** `connectivity_plus` OS radio-state listener only — no real reachability probe.
- **Local data retention:** a successful sync never deletes local rows — `updateFhirId`/`updateSyncStatus`
  only flip status columns on the same row. Local storage is the durable copy; the server round-trip
  only stamps confirmation onto it.

## 🔴 Critical

**1. Household/member rows the server reports `'Failed'` for become permanently stuck — no retry path, and they silently vanish from the pending count.**
`household_dao.dart`/`member_dao.dart`'s `getUnsynced()`/`getUnsyncedCount()` only ever query
`_pendingStatuses = ['NotSynced', 'NetworkError', 'Pending']` — `'Failed'` is never included, and
unlike assessments there is no `includeFailed`/`ManualSync` override anywhere in these two DAOs. Once
the status poll classifies a household/member `'Failed'`, no push mode ever re-sends it, and it drops
out of the "pending" count shown on the Offline Sync screen. Compounds with #2: any assessment for a
member under a `'Failed'` household/member never resolves its dependency gate either, so it's also
stuck forever.
**Fix:** add an `includeFailed` parameter to `HouseholdDao`/`MemberDao`'s unsynced-query methods
(mirroring `LocalAssessmentDao.getUnsyncedForPush(includeFailed:)`), pass `true` for
`ManualSync`/`InitialSync` push modes the same way assessments already do, and surface a distinct
"Failed — tap to retry" section on the Offline Sync screen. This fix mirrors an existing pattern that
already has an unaddressed weakness of its own (assessments' `includeFailed` retries a genuinely
server-rejected row forever with no backoff/attempt counter) — worth a follow-up retry-count column
eventually, not a blocker for this fix.

**2. A blocked assessment (its member/household hasn't synced yet) is retried forever with zero escalation or visibility, and the pending-count badge doesn't reflect this gating.**
`local_assessment_dao.dart`'s `getUnsyncedForPush()` correctly holds back an assessment whose
member/household has no `fhir_id` yet (`blocked`, not `ready`) — but there's no timeout/escalation if
the dependency never resolves (see #1), and `getUnsyncedCount()` (a flat status-only count, no join)
doesn't reflect this gating, so a permanently-blocked assessment still counts as ordinary "pending."
**Fix:** make `getUnsyncedCount()` run the same join `getUnsyncedForPush()` already does and return a
split count (`ready` vs `blocked`), and surface the `blocked` reason in the Offline Sync screen's
status text instead of a flat number.

**3. Push and pull run with an asymmetric, not just absent, concurrency guard.**
`AssessmentRepository.syncPendingAssessments()` checks `OfflinePushService.isPushInFlight` — but
`OfflinePushService.pushAll()` has no reference at all to `AssessmentRepository._isSyncing`, and
`OfflineSyncService._runSync` (pull) checks only its own `_running`, referencing neither push flag. A
form-submit push and a pull-to-refresh can run concurrently, each writing to overlapping tables
(member/patient upserts vs. assessment upserts) with no coordination beyond SQLite's per-statement
safety.
**Fix:** ship a cross-check first (each of the three flags explicitly checks the other two) as an
immediate fix — then scope a `SyncCoordinator` singleton (single flag, all three acquire/release
against it, self-clearing after a timeout mirroring `resetStuckInProgress`'s 15-minute pattern) as a
required follow-up, since three independent in-memory booleans with no age-gate is an implicit
contract that will eventually regress.

**4. The push status poll can leave an assessment `InProgress` forever within a session (confirmed root cause of issue #422).**
`OfflinePushService._pollAndApply`/`AssessmentRepository._pollOfflineSyncStatus` cap at 4 attempts
(~32-40s), loop past an empty `entityList`, an unrecognized entity `type` (no `default:` case —
silently dropped), or a persistently-`'InProgress'` status, without distinguishing "still processing"
from "will never resolve." On exhaustion the row is left `InProgress` with no automatic path out
except the 15-minute `resetStuckInProgress` age-gate, which only runs at the start of the next sync.
**Fix:** add an explicit `default:` branch that logs unrecognized types; schedule one automatic
re-poll after exhaustion instead of requiring a manual reopen; log a first-attempt empty `entityList`
so a broken requestId is distinguishable from a slow one.

**5. `_persistBundle` (the pull merge) has no transaction/atomicity — a partial failure mid-pass leaves cross-table data inconsistent, worst during a fresh-login `wipeBeforeSync: true` coldSync.**
No `db.transaction(...)` wraps the households → members → patients → programmes → follow-ups →
immunisations → assessments → referrals → pregnancy/treatment sequence — each DAO call commits
independently. A coldSync that already wiped the DB and fails partway leaves genuinely incomplete
data, and the UI's "Continue Offline" option lets the SK proceed with it silently.
**Fix — do not build the naive version:** wrapping `_persistBundle` in one outer transaction has a
**confirmed deadlock**: `PatientProgrammesDao.replaceFor()` — called once per patient, unconditionally
— opens its own nested top-level `_db.db.transaction()`. sqflite's transaction lock is non-reentrant
per `Database`; the naive fix hangs the app on the first patient of the first coldSync after it ships.
Required precondition: grep every DAO for `_db.db.transaction(` and rewrite each hit to accept/reuse a
passed executor first. Recommended actual path: **transaction-per-entity-type** (a separate
transaction each for households, members, patients, etc.) rather than one giant transaction — gets
most of the real-world safety benefit with far less churn and zero deadlock risk. Requires an
integration test against a **populated** bundle (not empty) to exercise `replaceFor`, and a
staged/guarded rollout given the blast radius (fresh login).

**14. Corrected during implementation — originally described as "temporary disappearance," the actual code has no such filter; the real (narrower) risk is a possible duplicate row, not a missing one.**
The original finding assumed `patient_context_screen.dart` excludes `local_assessments` rows once
`sync_status == success`, based on a comment stating the record is "already in `AssessmentDao` after
sync." Verified while implementing the fix: **no such filter exists anywhere in the file** (confirmed
via grep — no `sync_status`/`success` check gates the union at all). The comment was stale/aspirational,
not a description of the real code, and has been corrected in place.
What the code actually does: `_localAssessmentsFor()` unions *every* local draft (any status) with
every `AssessmentDao` row, unfiltered. The `assessments` getter then reconciles a draft and its
eventual synced counterpart into one display row by same-programme + a 48-hour proximity window
(`_visitMergeWindow`), not by sync status. So a draft never disappears — but if its synced counterpart
lands more than 48 hours later (plausible given #4's stalled-poll risk, or ordinary backend
processing lag), the pairing window is missed and the visit shows as **two rows** instead of one,
rather than as zero.
**Fix:** not implemented — the natural fix (match by `local_assessments.fhir_id`, stamped from the
push-poll's assessment `fhirId`, against `AssessmentDao`'s row `id`, which is the server's
`encounterId`) requires confirming those two identifiers are actually the same value end-to-end,
which isn't verifiable from static code alone without a live sync round-trip to inspect. Flagging as
a real but lower-severity, unconfirmed-fix finding rather than shipping a speculative change.

## Considered and rejected

**Delete `local_assessments` rows once confirmed synced.** Evaluated, not recommended. The
duplicate-display problem is already largely handled by the existing programme+time-window pairing
in the `assessments` getter (see #14) — deleting the source row doesn't improve that, it just removes
the fallback. `assessments` stores a reduced server-history summary, not the full original submission
`local_assessments.assessment_details` preserves — deleting the local row permanently downgrades that
visit's historical detail with no way back. It would also condition an irreversible action on a
mechanism this analysis found to have real reliability gaps (#4's stalled polls) — a bad pairing. No
referential-integrity blocker exists, but that alone doesn't justify it. If storage growth is a
genuine future concern, prefer archival with a long retention window over delete-on-first-confirmation,
and get evidence it's a real problem first.

## 🟡 Medium

**6. No conflict-resolution policy for concurrent edits across devices — plain last-write-wins/server-wins via `ConflictAlgorithm.replace` almost everywhere.**
Every DAO except household/member uses `INSERT OR REPLACE` with no timestamp/version comparison.
**Fix:** skip merging incoming pull data into a row that currently has unsynced local work
(`pending`/`inProgress`/`networkError`), letting the next push resolve it instead of silently
overwriting. Must explicitly exclude `'Failed'`-status rows from this skip-set, and must not ship
before #1 — otherwise a `'Failed'` row (no push path per #1) would also stop receiving pull updates,
freezing it in both directions. Doesn't solve the harder case (both sides already synced at different
times) — that needs a product decision, not a code fix.

**7. Session-expiry (401) handling is inconsistent across the 6+ sync trigger sites — only the login screen gives an intelligible message.**
Only `sync_progress_screen.dart` translates a 401 into a friendly message before the (globally-firing)
forced redirect lands. Every other site shows a raw technical string or nothing.
**Fix:** extract the login screen's 401-detection logic into a shared utility, use it at every other
trigger site's error surface, and have the connectivity-retry loop stop auto-retrying once it detects
a session-expired condition specifically.

**8. Two independent, largely copy-pasted push implementations — same endpoint, same polling shape, already drifted (8s vs 10s poll delay).**
Any polling fix has to be applied twice, correctly, or it silently regresses in whichever is missed.
**Fix:** extract the shared "POST create then poll status" logic into one class/function, or have
`AssessmentRepository` delegate its assessment-only case to `OfflinePushService`.

**9. The assessment-history endpoint is always a full village-scope pull, every single sync — the incremental `since` parameter exists but is never passed.**
**Fix:** track a `SyncMetaDao` entry for "last successful assessment-history sync" and pass it as
`since`. Low-risk, plumbing already exists end to end.

**10. Dormant duplicate-risk in the direct `patients[]` ingestion path — no fhir_id/reference_id reconciliation the way household/member merges have.**
Currently harmless (this backend ships members as the canonical patient list), but structurally the
same shape as issue #489 the moment the `patients` array is populated.
**Fix:** add a `PatientDao.insertOrUpdateFromBE()` mirroring `MemberDao`'s pattern.

## 🟢 Minor / informational

**11. Progress UI shows two dead steps, and `totalSteps` is already stale relative to the enum.** Either
emit the unused steps from `_runSync`, or remove them and correct `totalSteps`.

**12. No true background/scheduled sync exists**, despite a doc comment framing the connectivity
listener as mirroring WorkManager. Product decision before scoping as work, not a bug to just fix.

**13. Connectivity detection is OS radio-state only, not real reachability.** A captive portal reports
"online" and falls into an uncapped 30-second retry loop. Cross-references #3: a false "online" signal
is a plausible real-world trigger for #3's race, not just an isolated battery-drain annoyance — treat
#13 as raising #3's real-world likelihood.
**Fix:** add a cheap real reachability check before declaring "online."

## What the analysis was missing (added per architect review)

- **Observability/telemetry is absent everywhere.** #1 and #4 fail silently — no structured event
  fires when a row lands `Failed`, when `resetStuckInProgress` reclaims rows, or when a poll exhausts
  retries. Recommend a structured event for each.
- **No testing strategy specified for any fix**, especially #5 given its confirmed deadlock risk —
  needs an integration test against a populated bundle.
- **No rollout/staging plan for #5** — the riskiest fix touches the highest-risk path (fresh login).
- **No migration/backfill note for #1/#2** — confirm existing stuck `'Failed'` rows on production
  devices get picked up automatically once `includeFailed` ships.

## Recommended build order

1. **#9** — trivially low-risk, plumbing already exists.
2. **#1** — high value, low risk, mirrors a proven pattern. Ship with the "Failed — retry" UI, before #6.
3. **#3's cross-check** — smallest diff, prerequisite for trusting any #5 testing.
4. **#6** — only after #1, with the explicit `'Failed'`-row carve-out.

**Not recommended without further work:** #5 as originally specified (nested-transaction deadlock —
requires the DAO audit and the entity-type-scoped approach instead), the delete-local-after-sync idea
(rejected outright, see above), and #14's fix (needs a live sync round-trip to confirm
`local_assessments.fhir_id` and `AssessmentDao`'s row `id` are actually the same identifier before
matching on it).
