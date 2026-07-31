# Step 2 — Child Health (EPI visit): Unwanted Sync + Wrong Wire Contract

## Context

Two bugs reported after on-device testing of Step 2 (vaccination timeline + optional Child Health
form, now shown by default for every under-5 visit): (1) even when the SK doesn't touch anything,
tapping through still fires an API call/sync; (2) the Child Health form doesn't actually submit.

Investigation had two parts: tracing the actual save/sync code path in the Flutter app, and
correlating our Child Health form against the Android reference form definition
(`rmnch_childhood_visit.json`). The field-level gaps found there pointed at a wire-contract
mismatch as the likely cause of bug #2, so that hypothesis was then checked directly against the
**live production Android app's Kotlin source**
(`/Users/amresh/labs/UHIS/uhis/uhis-platform/spice-2.0-android/Spice-SL/`) — not just its JSON form
definition, and not just our own Dart code's comments about it, which turned out to be subtly wrong
on one point (the `cbs` sibling, finding #3 below). Only the `CHILDHOOD_VISIT` path was checked
against Android source — that app has no Immunization/EPI flow to compare against.

Status: **Implemented.** All 8 fix-plan items below are done; see the note at the end of the Fix
plan section for the one item (`childIllnessType` option ids) that remains a known, unfixed
limitation as planned, and the follow-ups still open (Bangla translation for the new save-error
string, a live capture of `member-assessment-history` to confirm the pull-side `pncChild` flatten
question).

---

## 🔴 Bug 1 — unconditional save + sync, even when nothing changed

`ImmunisationTimelineScreen`'s "Submit"/"Done" button handler
(`lib/features/visit/immunisation/immunisation_timeline_screen.dart:591-671`) builds a `details`
map from `_childAssessmentData` with `if (... != null)` guards, so `details` can end up `{}` — but
then calls `assessmentRepo.saveAssessment(...)` and `syncPendingAssessments()`
**unconditionally**, every time, regardless of whether `details` is empty. Vaccine status updates
themselves are unaffected — those already go through the separate, correctly-gated
`_UpdateStatusSheet` save path. This is specifically the EPI/Child-Health save firing even when the
SK filled in nothing.

**Fix:** only call `saveAssessment`/`syncPendingAssessments()` when `details.isNotEmpty`; skip
entirely otherwise. `onComplete`/`pop` still always fires — advancing the visit doesn't depend on
whether there was anything to save.

## 🔴 Bug 2 — wrong assessment type and wire contract, silently swallowed

Confirmed directly against Android's Kotlin source (`RMNCH.kt`, `AssessmentRMNCHFragment.kt`,
`AssessmentRepository.kt`, `AssessmentViewModel.kt`, `OfflineSyncRepository.kt`,
`FormGenerator.kt`) — four compounding issues:

**1. Wrong `assessmentType`.** The handler hardcodes `assessmentType: 'EPI'`. Android's real submit
path (`RMNCH.getMenuName()` → `"CHILDHOOD_VISIT"`, persisted via `AssessmentRepository.kt:69`'s
`menu.uppercase()`) confirms `local_assessment_dao.dart`'s already-implemented `'CHILDHOOD_VISIT'`
case (`_wrapDetailsForType`/`_wireType`, lines 338, 346, 487-489) is the right one — Android wraps
the payload as `{"pncChild": {...fields...}}` (`AssessmentViewModel.kt:820-824`, plain
`Gson().toJson(map)`, no custom DTO). `'EPI'` passes through flat/unwrapped instead. Confirmed via
`grep`: no other code reads/filters by `assessmentType == 'EPI'`, so changing it is safe with no
other blast radius.

**2. `cbs` should NOT be added — this corrects our own existing Dart code, not just the new fix.**
`local_assessment_dao.dart:487-489`'s existing `_wrapDetailsForType` unconditionally adds an empty
`'cbs': {}` sibling for `CHILDHOOD_VISIT` ("CBS sibling required by Android," per its own comment).
Android's real code proves that comment wrong for this specific flow:
`OfflineSyncRepository.kt:181-205` only *moves* a `cbs` key into `pncChild.cbs` **if one was
already present**; nothing in `AssessmentRMNCHFragment.kt` or the child-visit form ever populates
`assessmentMap["cbs"]` — that key is only ever set by the separate, unrelated CBS
registration/NCD/ICCM flows. **Real production Android traffic for a childhood visit never
includes a `cbs` key at all** — just `{"pncChild": {...}}`. This matches the exact same
omit-when-absent pattern already correctly handled for ICCM elsewhere in this codebase
(`unified_payload_mapper.dart:1067-1068`: *"CBS follow-up fields are added by Android's
updateCbsForRMNCH when CBS form data is present; Flutter has no CBS form section yet — omit for
now"*). `PNC_NEONATE`'s own `cbs` handling (same file, line 485) was **not** part of this check
(out of scope — only `CHILDHOOD_VISIT` was verified against Android source) and should stay
untouched.

**3. Wrong field keys and value encoding.** Cross-referencing `rmnch_childhood_visit.json` AND the
actual Kotlin serialization path (`AssessmentDefinedParams.kt` field ids, `FormGenerator.kt:1538-
1544` for option-id storage, `FormGenerator.kt:571-573` for weight's `Double` parsing) against
`child_assessment_section.dart`/the submit handler's `details` map:

| Dart key sent today | Android's real wire key | Value encoding |
|---|---|---|
| `weightKg` | `weight` | Already numeric — OK |
| `isBreastfeeding` | `childBreastFeeding` | Dart `bool` → Android string `"yes"`/`"no"` |
| `additionalFoodLast24h` | `additionalFood24Hrs` | same bool→string fix |
| `vaccinesReceived` | `receivedVaccine` | same bool→string fix |
| `dewormingTaken` | `dewormingMedicine` | same bool→string fix |
| `complications` | `childIllnessType` | list of option ids (see gap below) |
| `referralMade` | `childReferral` | same bool→string fix |
| `referralPlace` | `childReferralFacilityType` | **id**, not display label (e.g. `hwc`, not "Health & Family Welfare Center") |
| `congenitalDefect`, `anyIllness` | (unchanged) | same bool→string fix |

The referral-facility id/label fix should reuse `epi_schedule_engine.dart`'s
`FacilityOption`/`referralFacilityOptions` (same 6 facilities, already carries the id) instead of
`ChildAssessmentStrings.referralPlaces` (plain strings, no ids) — one source of truth instead of a
second hardcoded list.

**4. Errors are silently swallowed.** The `saveAssessment()` call is wrapped in
`try { ... } on Object catch (e) { debugPrint(...); }`, and `onComplete(...)` — which advances the
visit — runs **unconditionally after**, whether the save succeeded or threw. So even a local DB
failure looks like a successful submit to the SK. Network-sync failures
(`syncPendingAssessments()`) are already correctly fire-and-forget via `unawaited(...)` — that part
is fine, offline-first, retried later. It's specifically the *local* save failure that should not
be silent.

## 🟡 Additional gaps found in the form correlation (real, lower priority)

- **Missing mandatory field.** Android has an always-visible, mandatory question with no Flutter
  equivalent at all: "What was the child fed in the last 24 hours?" (`childFeedLast24Hrs`,
  multi-select: mother's breast milk, cow/goat milk, formula milk, semolina, rice powder, family
  food, other).
- **Missing skip logic.** Android only shows "Has referral been made?" when `anyIllness == "yes"`
  (a `condition` block in the JSON); Flutter's Q14 renders unconditionally regardless of the
  illness answer.
- **Missing validation.** Android enforces a `weight` range of 0-30; Flutter's weight field only
  formats decimals, no range check.
- **Not investigated further (left alone, not a fix target):** two Android fields
  (`hrsBreastFed`, `monthAdditionalFeedGiven`) are hidden by default with no visible trigger
  condition in the JSON — implementing conditional logic for a trigger that can't be verified from
  this file would be a guess, not a fix.

---

## Senior Android Architect review (post-draft, before approval)

A second verification pass specifically targeted the two things a domain expert would ask about
that the first pass didn't cover, plus a scan for anything the fix might disturb elsewhere. Findings
below; the plan above is updated in place where they change something.

**✅ Cleared — no childhood-visit-specific status logic exists.** Checked
`AssessmentStatusGenerator.kt:evaluateStatus()` (lines 149-273) directly: it has explicit branches
for `PW`, `ANC`, `PNC`, `PREGNANCY_OUTCOME`, `FP`, `NCD`, `CATARACT`, `EYE_CARE` — **no branch for
`ChildHoodVisit`/`pncChild` at all**; it falls through to `else -> null`. `getReferralStatus()`
(lines 108-121) is generic (`Referred`/`OnTreatment`/else-`Recovered`) with no childhood-visit
override either. So the plan's reliance on the existing generic `saveAssessment(isReferred:,
referredReasons:)` → `_buildCustomStatus()` path (unchanged, no new logic needed) is correct — there
is no hidden malnutrition/growth-based status rule to replicate. This was worth checking and worth
writing down, but requires no plan change.

**⚠️ `childIllnessType`'s option ids are not a "flag and move on" gap — they're structurally
unfixable from this codebase.** Traced the full chain: `AssessmentRMNCHFragment.kt:622-624` →
`viewModel.getSymptomListByType()` → Room table `SignsAndSymptomsEntity` → populated *only* by
`MetaRepository.kt:355-367`'s live call to a backend `getFormMetadata` API. There is no local
asset, string-resource, or DB-seed file anywhere in the Android repo with these ids — confirmed by
an exhaustive `childIllnessType` grep across the whole codebase (3 hits, all either the constant
name or the two references inside the one JSON file already read). **This means our current 5
hardcoded `complications` labels almost certainly have the exact same id-vs-label wire mismatch
already proven for the referral facility field — free-text display strings going out where the
backend expects server-issued ids — and no amount of further static-code reading will resolve it.**
Recommend either (a) a live/staging capture of the real `getFormMetadata` response, or (b) direct
backend API documentation, before this field can be corrected. Flag it as an explicit **known
limitation of this fix**, not a silently-dropped nice-to-have — the fix plan should ship with this
called out, and `childIllnessType` should be treated as still-broken-the-same-way post-fix, not
resolved.

**⚠️ New copy needs a real Bangla translation, not an English-only placeholder.** Checked
`assets/translations/strings.json`: the existing sibling questions this form shares a section with
(`q6Label`, `q14Label`, `q15Label`, etc.) all have populated `bn` entries. Item 5's new
`childFeedLast24Hrs` question/options would be the only Q6-equivalent field in this section without
one if shipped with just the English fallback used in the plan's "best-effort labels inferred from
Android's option ids." Given this session's own earlier discovery that a stale/missing JSON
translation entry can silently diverge from the English intent (see the "Given"→"Completed" bug
from the EPI work), this should be authored properly — not left as a TODO — before this field ships
to Bangla-locale users.

**✅ Cleared — no other caller of `_wrapDetailsForType` to worry about.** `grep`-confirmed exactly
one call site (`local_assessment_dao.dart:236`, private method) — the `cbs`-omission fix in item 4
has no other blast radius inside this codebase.

**✅ Cleared — no visit-number field to add.** Checked `rmnch_childhood_visit.json` for a
`childVisitNumber`/`visitNo`-equivalent field: none exists in the form itself, unlike ANC/PNC which
declare explicit sequential visit-number fields. So `_extractVisitNumber`'s existing
`CHILDHOOD_VISIT` branch (which already falls back to `null` when neither `visitNo` nor
`childVisitNumber` is present in the details map) needs no new field wired in — a childhood visit is
not sequence-tracked the way ANC/PNC are.

**Residual, not independently verifiable from this codebase:** everything above is confirmed
against the **Android client's** real behavior. None of it proves what the **backend** actually
requires or tolerates — e.g. the `cbs`-omission fix is justified by "Android has sent payloads
without this key in real production traffic for this assessment type," which is strong evidence the
backend already accepts that shape, but it is inference from client behavior, not a read of backend
validation code (not available in this session). Recommend a staging-environment smoke test of the
`{"pncChild": {...}}`-with-no-`cbs` payload before treating this as done, not just "Android does it
this way so it must be fine."

## Pull (read) side — not previously considered, real findings

Everything above only verified the **push/write** path. A direct question ("have we considered the
pull format too?") surfaced that the read side was never checked — and this session already has one
precedent for push/pull shapes silently diverging (the EPI/`CHILD_IMMUNIZATION` history-pull bug
fixed earlier). Checked directly:

**✅ Strong positive signal: the existing read/display code already expects Android-native field
names.** `patient_context_screen.dart`'s `_TimelineEventSheet` (the bottom sheet that expands a
patient's care-thread timeline event into clinical detail) already has, under a
`// ── IMCI / childhood ──` comment (lines 4192-4199):
`addIfPresent('weight', ...)`, `addIfPresent('childIllnessType', ...)`,
`addIfPresent('receivedVaccine', ...)`, `addIfPresent('childBreastFeeding', ...)`,
`addIfPresent('dewormingMedicine', ...)`, `addIfPresent('childReferral', ...)`,
`addIfPresent('childReferralFacilityType', ...)` — **the exact Android field ids this plan is
switching the write path to**, not the current Dart-named keys (`weightKg`, `isBreastfeeding`,
etc.). This means the read side has probably been silently blank for these fields all along (the
old Dart keys never matched what this display code looks for), and the write-side fix in this plan
should *also* fix that display, not just the submission.

**⚠️ Real, unresolved gap: `_normalizeRaw()` doesn't flatten a `pncChild` wrapper.**
`_normalizeRaw()` (`patient_context_screen.dart:1608`) flattens `observations` and
`assessmentDetails` generically (Step 1), and has an explicit *additional* step for
`familyPlanning`/`family_planning` specifically because that programme's fields sit one level
deeper than the generic flattening reaches (Step 1b, comment: *"programme wrappers sit one level
inside 'assessmentDetails'"*). There is **no equivalent step for `pncChild`**. If the backend's
`member-assessment-history` *read* response nests these fields under `pncChild` the same way the
*write* payload does (`{"pncChild": {"weight": ..., "childBreastFeeding": ...}}`), `raw['weight']`
would resolve to `null` and the "IMCI / childhood" fields would stay blank even after this plan's
write-side fix — needing the exact same kind of extra flatten step already added for
`familyPlanning`. **This cannot be resolved from static code alone** — it depends on the real shape
of a `member-assessment-history` response for an actual submitted childhood visit, which hasn't
been captured in this session (unlike `CHILD_IMMUNIZATION`, where a live capture is exactly what
caught the original push/pull mismatch). Recommend the same move: watch `[PayloadDebug]`/logcat
during a live `member-assessment-history` fetch for a patient with a submitted childhood visit
before assuming either shape.

**⚠️ Secondary, lower-severity finding: `Programme.fromString('CHILDHOOD_VISIT')` returns
`Programme.pnc`**, not a distinct bucket (`programme.dart:83`, grouped with `PNC`/`PNC_MOTHER`/
`PNC_CHILD`/`PNC_NEONATE` — consistent with the Android app's own "RMNCH" family grouping, so likely
intentional, not a bug). Practical effect: after this fix, a Child Health assessment shows up in
the patient's care-thread timeline as a **PNC** entry, not an EPI one — and the PNC summary card
(`patient_context_screen.dart:1781-1789`) surfaces the *latest* PNC-bucket record's stats
(`pncVisitNumber`, `modeOfDelivery`, `anyComplicationsDuringDelivery`, `numberOfLivingChildren`) —
none of which exist on a childhood-visit payload. If a childhood visit becomes the most recent
PNC-bucket record for a patient, that summary card would render with all its stat rows empty (not
wrong data — the `if (x != null)` guards just omit each missing stat — but a card that looks blank
where a PNC-mother visit would normally show something). Not a crash, not silently-wrong data, but
worth a deliberate product decision rather than an accident: is grouping childhood visits under the
"PNC" thread actually desired, or should this get its own thread/card?

**Verdict: plan is sound and ready to implement, with four additions before it's "complete":**
(1) explicitly document `childIllnessType` as a known-unfixed gap in the shipped change (don't let it
quietly look resolved because the rest of the form now round-trips correctly), (2) get a real
Bangla translation for the new mandatory field rather than shipping an English-only placeholder,
(3) capture a real `member-assessment-history` response for a submitted childhood visit and add a
`pncChild`-flatten step to `_normalizeRaw()` if it turns out nested (mirroring the existing
`familyPlanning` precedent), and (4) confirm whether bucketing childhood visits under the "PNC"
care-thread is the intended product behavior.
Everything else — assessment type, `cbs` omission, field-key/value remapping, missing skip logic,
weight validation, error-swallowing — is verified against actual behavior (Android source code
and/or direct grep of this codebase), not assumption, and I found no other caller or field this
touches that the plan missed.

---

## Fix plan

1. **Gate the save on actual content** (Bug 1) — `immunisation_timeline_screen.dart`'s submit
   handler: only call `saveAssessment`/`syncPendingAssessments()` when `details.isNotEmpty`.
2. **Fix the wire contract** (Bug 2 core) — same handler: `assessmentType` → `'CHILDHOOD_VISIT'`;
   rebuild `details` with Android's field ids; encode booleans as `'yes'`/`'no'`; send the facility
   id, not the label.
3. **Reuse the facility id/label list** — `child_assessment_section.dart`: replace
   `ChildAssessmentStrings.referralPlaces` with `EpiScheduleEngine.referralFacilityOptions`/
   `FacilityOption`; dropdown shows `.label`, `ChildAssessmentData.referralPlace` stores `.id`.
4. **Stop injecting an empty `cbs` sibling** — `local_assessment_dao.dart`'s
   `_wrapDetailsForType`: for `CHILDHOOD_VISIT`/`CHILD_MENU`, return `{'pncChild': details}` (no
   `cbs` key) unless `details` already contains a real `'cbs'` entry, mirroring the existing
   `pncChild` re-entrant guard immediately above it. `PNC_NEONATE` untouched.
5. **Add the missing mandatory field** — `ChildAssessmentData`: new `List<String> feedLast24h`
   field (mirrors the existing `complications` chip-picker pattern); new `ChildAssessmentStrings`
   getters for the label + 7 option id→label pairs (best-effort labels inferred from Android's
   option ids — flag for confirmation against Android's actual string resources if available);
   always-visible required question; wired into the submit handler under
   Android's `childFeedLast24Hrs` key as a `List<String>` of ids.
6. **Add the missing skip logic** — wrap Q14 (`referralMade`) in `if (d.anyIllness == true) ...`,
   matching Q13's existing conditional pattern; clear `referralMade`/`referralPlace` when
   `anyIllness` becomes false/null (mirroring how `complications` already gets cleared there).
7. **Add weight range validation** — `_WeightField`: surface an `errorText` when the parsed value
   is outside Android's `0-30` range, computed in `_ChildAssessmentSectionState` and passed down.
8. **Stop swallowing save errors** — submit handler: on a `saveAssessment` failure, show a brief
   error (existing `ScaffoldMessenger` pattern) and do **not** call `onComplete`/pop; let the SK
   retry. Network-sync failures stay exactly as they are today (already non-blocking).

### Files

- `lib/features/visit/immunisation/immunisation_timeline_screen.dart` — items 1, 2, 8.
- `lib/features/visit/triage/child_assessment_section.dart` — items 3, 5, 6, 7.
- `lib/core/db/local_assessment_dao.dart` — item 4.
- `lib/core/constants/app_strings.dart` — new `ChildAssessmentStrings` getters for item 5; remove
  the now-unused `referralPlaces` list (superseded by item 3's reuse).

### Verification

1. `flutter analyze` + `flutter test` — zero regressions vs. current baseline.
2. Manual, on-device: open Step 2 for an under-5 visit, tap "Done" without touching anything —
   confirm (via the existing `[PayloadDebug]`/`ConsoleLog` output, already generic for any
   `assessmentType`) that **no** `offline-sync/create` call fires. Then fill in the Child Health
   form (including a referral) and submit — confirm the payload shows `assessmentType:
   CHILDHOOD_VISIT`, wrapped as exactly `{"pncChild": {...}}` with **no `cbs` key** (matching
   verified real Android traffic), Android's exact field ids, `"yes"`/`"no"` values, and the
   facility id (not label). Confirm the new "fed in last 24 hours" question appears and is
   required; confirm the referral question only appears after answering "Yes" to
   illness/complications; confirm an out-of-range weight shows an error.

### Implementation notes (post-execution)

- Item 5's new question got a **real** Bangla translation, not a placeholder: the Android form
  asset (`rmnch_childhood_visit.json`) already ships authored `titleCulture`/`cultureValue` Bangla
  text and real wire-level option ids (`mothersBreastMilk`, `cowgoatMilk`, `formulaMilk`,
  `semolina`, `ricePowder`, `familyFood`, `other`) for this exact field — used directly instead of
  guessing, resolving the Senior Architect review's translation concern.
- `childIllnessType` option ids are shipped as our existing display-label strings (unchanged) —
  per the review, these are **known-unfixed**: Android sources them from a live `getFormMetadata`
  backend call with no local fallback anywhere in its codebase, so this remains broken the same way
  post-fix, not resolved.
- One new string (`EpiStrings.childAssessmentSaveError`, the item 8 save-failure SnackBar) and one
  validation message (`ChildAssessmentStrings.q7RangeError`, item 7) shipped **English-only** —
  no authentic Android-sourced Bangla text was available for either (unlike item 5), and inventing
  one risked being actively wrong. Flagged here rather than silently shipped as "done."
- Pull-side gap (`_normalizeRaw()` missing a `pncChild` flatten step) and the PNC-bucketing product
  question are **still open** — both require a live `member-assessment-history` capture / product
  decision that this session couldn't produce; not part of this fix.
- Tests added: `test/core/db/local_assessment_dao_childhood_visit_test.dart` (wire contract/`cbs`
  omission) and `test/features/visit/triage/child_assessment_section_test.dart` (weight range,
  Q12→Q14/Q15 clearing, Q14 visibility gate, new question wiring). Full `flutter test` diffed
  test-by-test against the pre-change baseline: zero regressions, 4 previously-failing tests now
  pass (2 are this fix's own tests correctly flipping from red to green; 2 are `app_database.dart`'s
  already-pending `onUpgrade` rename fix, unrelated to this doc but sitting in the same working tree).
