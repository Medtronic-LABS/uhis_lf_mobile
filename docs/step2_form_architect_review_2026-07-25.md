# Step 2 Form — Architect + Code Review (2026-07-25)

Fresh, independent review of the Step 2 clinical assessment form screen (`lib/features/visit/forms/unified_form_screen.dart` and its supporting notifier/config/rules/clinical files), conducted as Software Architect + Code Reviewer. This supersedes `docs/step2_form_gap_analysis.md`, most of whose findings had already been fixed by the time of this review — see that file's own follow-up thread for the verification trail.

Four independent review passes (architecture/SOLID, correctness/clinical-safety, maintainability/DRY, config/error-handling/localization) were run against the current code, with the two most severe findings directly re-verified by reading the literal source. Findings are ranked by severity below.

Files in scope:
- `lib/features/visit/forms/unified_form_screen.dart` (4,211 lines)
- `lib/features/visit/forms/unified_form_notifier.dart` (1,184 lines)
- `lib/features/visit/forms/form_config.dart` (559 lines)
- `lib/features/visit/forms/unified_section_rules.dart` (693 lines)
- `lib/features/visit/widgets/form_fields/radio_form_field.dart` (117 lines)
- `lib/core/clinical/referral_evaluator.dart` (595 lines)
- `lib/core/clinical/assessment_thresholds.dart` (144 lines)

---

## 🔴 Critical — clinical-safety bugs

### 1. ANC referral evaluator has no hypertensive-crisis path

`referral_evaluator.dart:218-224,318-321` — `AncReferralEvaluator` only escalates high BP to `emergency` when pre-eclampsia criteria (albumin/edema) are *also* present:

```dart
final highBp = (sys != null && sys >= bpHighSystolic) || (dia != null && dia >= bpHighDiastolic);
if (highBp && (albuminPresent || edemaPresent)) { emergency.add('Suspected pre-eclampsia'); }
...
if (highBp && !emergency.contains('Suspected pre-eclampsia')) { nonEmergency.add('High blood pressure'); }
```

`bpCrisisSystolic`/`bpCrisisDiastolic` (180/110) exist in `assessment_thresholds.dart` and are used by the NCD evaluator, but **never referenced in the ANC path**. Per CLAUDE.md's own documented threshold ("BP ≥ 160/110 → Band 1 urgent referral"), a pregnant patient with BP 200/125 and no recorded albumin/edema is filed as **non-emergency** — the same bucket as "low weight." PNC treats the identical 140/90 threshold as urgent unconditionally, so ANC is inconsistent with its sibling pathway on the same measurement.

**Fix:** add a crisis-BP branch to `AncReferralEvaluator.evaluate` independent of albumin/edema, mirroring the NCD crisis band.

### 2. `height` is silently wiped right before referral computation on every ANC follow-up visit

Verified directly against current source:
- `unified_section_rules.dart:606-607`: `case 'height': return visit == 1;` — hidden after visit 1.
- `unified_form_screen.dart:151`: `notifier.preloadBiometrics()` deliberately pre-seeds `height` from the last visit so it stays available for BMI/clinical checks across visits.
- `unified_form_screen.dart:502-505`, in `_onSubmit`, runs **before** `notifier.submit()`:

```dart
final hiddenFieldIds = _computeHiddenFieldIds(notifier, annotated); // includes height (hidden + non-null)
if (hiddenFieldIds.isNotEmpty) { notifier.clearFields(hiddenFieldIds); }
```

- `notifier.dart:1096` then feeds the now-null value into `AncReferralEvaluator`'s `if (height != null && height < heightLowCm)`.

Net effect: **"Low height" can never fire past visit 1**, and every follow-up ANC payload submits `height: null` even though the value was known and specifically preloaded for reuse. This is a stale-field-clearing rule (correct in intent, for fields like Parity) applied too bluntly to a field that's intentionally cross-visit persistent.

**Fix:** exclude preloaded biometric fields (or any field flagged "carry-forward") from `_computeHiddenFieldIds`, or compute referral from the pre-clear snapshot rather than post-clear state.

### 3. Hemoglobin severity badge disagrees with the referral engine on what "severe" means

Two independent review passes confirmed this from different angles: `_VitalStatusEval.hemoglobin()` (`unified_form_screen.dart:2739`, badge shown to the SK) uses `< 7.0` for severe, while the actual referral trigger (`assessment_thresholds.dart` → `referral_evaluator.dart:243`) uses `hbSevereAnaemia = 8.0`. **A patient at Hb 7.5 g/dL sees a "moderate" badge on screen while the system will actually refer them as severe** — the SK's own visual cue contradicts the decision the app makes.

Root cause: `_VitalStatusEval` hardcodes its own threshold literals instead of importing the canonical constants (BMI and glucose bands in the same class currently match by coincidence, not by reference — same latent risk if `assessment_thresholds.dart` changes and this class isn't updated in lockstep).

### 4. Two silent data-loss paths with no user-facing signal

- `notifier.dart:1169` — autosave write failure is `catchError` → `debugPrint` only, fire-and-forget, no retry/dirty-flag/banner. A DB write failure means everything typed since the last successful save is gone with zero indication.
- `notifier.dart:286-297` (`loadDraft`) — a malformed draft row is caught and dropped; the form re-renders blank as if nothing was ever entered, no banner, no retry.

Both directly violate the repo's "degrade gracefully offline" standard — this doesn't degrade, it drops clinical data silently.

---

## 🟠 High

**5. Bare `catch (_) {}`** at `notifier.dart:489` (LMP/GA rawJson fallback) — no log at all, unlike every sibling catch in the same function; violates the explicit "never a bare catch that swallows" rule and can silently break gestational-age-based field visibility/referral.

**6. Unsafe cast** `notifier.dart:1077`: `(_data.getValue('ncdSymptoms') as List?)?.cast<String>()` — throws on a non-null non-List legacy/corrupt draft value, aborting submit with a generic "save failed" snackbar and no diagnosis.

**7. NCD glucose banding gap** — FBS 6.1–6.9 mmol/L (a clinically meaningful impaired-fasting-glucose range; the constant `fbsScreeningNormal = 6.1` exists but is unused) falls through every band in `_bgBand` (`referral_evaluator.dart:131-143`) and returns green/no-concern.

---

## 🟡 Architecture (SOLID / separation of concerns)

**8. `_VitalStatusEval` (badge severity) duplicates the domain layer inside the widget file** (`unified_form_screen.dart:2604-2846`) instead of delegating to `referral_evaluator.dart`/`assessment_thresholds.dart` — this is the direct cause of finding #3 and is a textbook "business logic leaking into the widget" violation. Should move into `core/clinical/` and be provably the same computation the referral evaluators use.

**9. Supplement pairing rule (folic acid / calcium) is defined twice with contradictory roles** — `unified_section_rules.dart:68-77` treats `folicAcidTablets` as consumed-equivalent; `unified_form_screen.dart:1474-1506` treats it as provided-equivalent. Single-source-of-truth violation, actively disagreeing.

**10. `unified_form_screen.dart` is a 4,211-line god file** — ~30 classes covering rendering, validation, business-rule computation (`_computeValidationErrors`, `_computeHiddenFieldIds`), and clinical threshold evaluation all in one file. Concrete split: orchestration-only screen, `widgets/vital_status_eval.dart` (pure, trivially extractable), `widgets/section_card.dart`, `widgets/pair_cards.dart`, `widgets/form_primitives.dart`. Validation/hidden-field logic belongs on the notifier, not the widget.

**11. Notifier has no abstraction boundary** — constructor takes 5 concrete sqflite-backed DAO/repository classes directly (`notifier.dart:30-58`), so it can't be unit-tested without real or fully-duck-typed SQL fakes.

---

## 🟢 Maintainability / DRY

**12. `preloadAncChronic`/`preloadNcdChronic`/`preloadPncMotherChronic`/`preloadFpChronic`** (`notifier.dart:196-249`) — four copy-pasted methods differing only in which repo call to make. One-home violation (4 places).

**13. Pair-card parse/emit boilerplate repeated ~8 times** across `_bpPairCard`/`_glucosePairCard`/`_heightWeightPairCard`/`_supplementPairCard` (`unified_form_screen.dart:1742-2155`) — same `int.tryParse ?? double.tryParse ?? v` pattern each time.

**14. Two independent BP-triplet layouts** (`_bpPairCard` vs. `_BpReadingRow`/`_bpCell`) doing the same systolic/diastolic/pulse row differently.

**15. Ad-hoc `print()`/`debugPrint` scaffolding** embedded directly in three `build()` methods, duplicating the existing proper `UnifiedSectionRules.debugLogSections` mechanism.

---

## Suggested sequencing

Given the blast radius (shared validation/visibility/referral path across ANC/NCD/PNC), this should land as separate, independently-revertable changes:

1. **#1 and #2** (ANC crisis-BP path, height-clearing bug) — clinical-safety fixes, ship first, each needs a targeted regression test + manual walk of an ANC follow-up visit.
2. **#3 + #8** together (extract `_VitalStatusEval` to reference canonical constants) — fixes the drift and the architecture smell in one move.
3. **#4, #5, #6** (error-handling) — data-loss and swallow fixes, moderate risk, needs on-device kill-mid-save testing.
4. **#7** (glucose band gap) — needs a clinical-owner decision on what the impaired-range action should be, not just a code fix.
5. **#9–#15** — structural cleanup, lowest urgency, best done as its own refactor PR once the above are stable.
