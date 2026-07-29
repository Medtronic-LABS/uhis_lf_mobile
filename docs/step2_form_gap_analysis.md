# Step 2 (Clinical Assessment Form) — Gap Analysis

## Context

Review of Step 2 (the vitals + full clinical form screen — `unified_form_screen.dart`) covering design, labels, and logic gaps. Three parallel research passes compared the live Flutter implementation against the design mockups (`apon_sushashthya_v13.html` + style guide), the source field-definition data (`assets/forms/field_library.json`), and the app's own localization standard. The two most severe findings (dead validation, temperature unit bug) were spot-verified directly in code.

The single most important finding: **a live clinical-safety bug**, not a polish item. Everything below is grouped by severity so the fix work can be scoped deliberately.

---

## 🔴 Critical — clinical logic bugs (recommend fixing regardless of what else is scoped)

**1. Temperature unit mismatch — referral logic is comparing °F values against °C thresholds.**
`assets/forms/field_library.json:616` labels the `temperature` field as Fahrenheit (`titleCulture: "তাপমাত্রা (ফারেনহাইট)"`, `unitMeasurement: "°F"`), and `unified_payload_mapper.dart:177/556` sends `temperatureUnit: '°F'` — so the SK genuinely enters a Fahrenheit value (e.g. 98.6 normal). But `unified_form_notifier.dart:675,692` passes that raw number straight through as `temperatureCelsius: asDouble('temperature')` into `AncReferralEvaluator`/`PncReferralEvaluator` (`lib/core/clinical/referral_evaluator.dart:189,256-258,333,385-387`), whose fever thresholds are genuinely in Celsius (`>= 38.9`, `37.8–38.9`). A normal 98.6°F reading is `>= 38.9`, so **every ANC/PNC visit currently evaluates as having a high fever**, regardless of the patient's actual temperature. This directly feeds the referral/urgency decision.
**Fix:** convert °F → °C before passing to the evaluators (`(f - 32) * 5/9`), at the point in `unified_form_notifier.dart` where `temperatureCelsius:` is populated.

**2. Numeric range validation is dead code — it never runs.**
`_numericRangeValidator(fieldId)` (`unified_form_screen.dart:1983-2016`) covers fasting/random blood sugar, hemoglobin, and temperature, and is wired via `validator:` on the `TextFormField`s — but **there is no `Form` widget, no `GlobalKey<FormState>`, and no `.validate()` call anywhere in `unified_form_screen.dart`** (confirmed by direct grep — zero hits). A `TextFormField.validator` only ever fires inside a `Form.validate()` call, so these three checks silently never execute. Combined with finding 3 below, there are currently **zero enforced numeric bounds** anywhere in Step 2 — a systolic BP of 3 or 900 is accepted and submitted.
**Fix:** wrap the field list in a `Form` + `GlobalKey<FormState>`, call `.validate()` at the existing submit gate (`_onSubmit`, alongside the current presence check), and extend range coverage to BP (systolic/diastolic) and fundal height, which have no bounds defined at all today.

**3. The JSON's real conditional-visibility engine is silently discarded.**
`field_library.json` defines ~96 per-field `condition: [{eq, targetId, visibility}]` rules (e.g. `isHtnDiagnosis == "Yes"` reveals `bpLog`/`glucoseLog`/etc.) plus a `visibility`/`compositeGroup`/`compositeRole` scheme for the obstetric-history chain (Gravida → Parity → Living Children → Age of Last Child, meant to progressively reveal). `FieldDef.fromJson` (`form_config.dart:124-148`, verified directly) parses none of these keys. In their place, `unified_section_rules.dart:292-325` hand-codes only 4 section-level rules. Practical effect: a first-time pregnant patient (Gravida=1) sees Parity/Living Children/Age-of-Last-Child questions that make no clinical sense for her; `fetalMovement` renders regardless of gestational week; dozens of Yes/No-dependent follow-up fields render unconditionally.
**Fix:** this is the largest single piece of work in the report — parse `condition`/`visibility`/`compositeGroup` in `FieldDef`, and evaluate them in `unified_section_rules.dart` (or a new field-level visibility pass) against the live form data, replacing/extending the 4-case stub.

**4. Autosave has no debounce, and interacts badly with the above.**
`updateField()` (`unified_form_notifier.dart:251-265`) persists to the encounter draft on every keystroke with no debounce. Since submit-time validation only checks *presence* (until fix #2 lands), an interrupted SK could leave a stray intermediate digit (e.g. systolic="1") in a resumable draft that would pass validation as-is. Lower priority than 1–3, but worth a debounce (e.g. 400ms `Timer`) once range validation is real, so a half-typed value can't be flagged before the SK finishes typing.

**5. CDS/CDSS feedback is submit-only, not live.** `NcdReferralEvaluator`/`AncReferralEvaluator`/`PncReferralEvaluator` only run inside `submit()` (`unified_form_notifier.dart:581`). During entry, the SK only sees passive `_VitalBadge` color chips (correctly threshold-matched) — no live banner for danger signs. This is a design/product decision more than a bug; flagged for awareness, not proposed as an in-scope fix unless requested.

---

## 🟡 Design gaps vs. the style guide / mockups

1. **Tri-state chips (Urine Protein, Fetal Movement) have no clinical-severity color coding.** The mockup colors "Present"/"Not felt" red and "Absent" green; the actual `_PillButton` (`radio_form_field.dart:84-90`) renders every selected option in the same neutral navy — losing the at-a-glance abnormal-finding cue for two danger-sign-adjacent fields.
2. **Clinical help/info text (`infoTitle`/`isInfo` in the JSON) is parsed by nobody and never rendered** — e.g. "0 = if BP could not be measured", "Probe and include stillbirths." Silently dropped for every field that has it (same root cause as Critical #3 — `FieldDef` doesn't read these keys).
3. **No progressive disclosure for the obstetric-history chain** — same root cause as Critical #3.
4. **No sequential question numbering** in the pregnancy-history section, present in the mockup ("1. LMP...", "2. Pregnancy Test..."), absent in `_FieldLabel`.
5. **BP severity badge exists for ANC's combined card but not NCD's individual BP fields** — `_VitalStatusEval.bloodPressure()` is shared/correct but only wired into `_bpPairCard`, not `_BpReadingField` (NCD path).
6. Minor: BP field captions ("Systolic"/"Diastolic") are permanent labels above the input vs. the mockup's disappearing placeholder-inside-input style.

## 🟢 Labels / localization gaps

1. **Two hardcoded strings** bypassing `app_strings.dart`: `unified_form_screen.dart:1562` (`hint: 'Pulse'`, when `UnifiedFormStrings.bpPulseLabel` already exists and is used elsewhere), and `:3460` (`'Please select at least one option'`, no constant exists at all).
2. **Two competing localization seams**: field labels/Bengali text live in `assets/forms/field_library.json`, not `app_strings.dart` — contradicts the "single seam" engineering standard, though arguably fine as externalized content data if acknowledged rather than accidental.
3. **Redundant Bengali strings** — `UnifiedFormStrings.bpCardSubLabel`/`glucosePairSubLabel` in `app_strings.dart` duplicate the same text already in `field_library.json`'s `titleCulture`. Two sources of truth for identical copy.
4. **15 of 219 fields missing Bengali `titleCulture`**, including clinically relevant ones: `fetalMovement`, `ancBloodGlucose`, `ancDangerSigns`, `lowBirthWeight`, `pncNeonateSigns`, `deathOfNewborn`, `folicAcidTablets`.
5. **IMCI/TB have no entries in `field_library.json` at all** — those programmes route through separate ad-hoc screens with their own inline literals, outside both `unified_form_screen.dart` and `app_strings.dart`.
6. Unit placement is inconsistent (subtitle line vs. input suffix, varies by field) — not wrong, just not systematic.
7. Required-field asterisk marker is copy-pasted identically in two private widgets instead of one shared widget.
8. Two dead `UnifiedFormStrings` constants (`noPathways`, `validationBannerTitle`) — unreferenced anywhere.

---

## Implementation plan (full scope — critical + design + labels)

Given the size, this should land as **3 separate PRs in sequence** (Critical → Design → Labels), same one-fix-per-branch pattern used throughout this project — not one giant diff. Each phase is independently shippable.

**Overall risk note:** this plan touches the core form-rendering and validation path shared by every visit type (ANC/NCD/PNC/pncChild/pncNeonatal) — the app's primary workflow. Phase 1.3 (conditional-visibility engine) is the highest-risk single item and should probably be its own PR even within Phase 1, given its blast radius across all programmes and the shared validation gate. Each phase should get full regression testing (analyze + full test suite + manual walk-through) before the next phase starts, rather than stacking all three untested. Per-item risk notes are inline below.

### Phase 1 — Critical logic fixes

**1.1 Temperature °F→°C conversion.** In `unified_form_notifier.dart`, at both call sites that build `temperatureCelsius:` (lines 675, 692), convert the raw form value: `(f - 32) * 5 / 9`. Add a small helper (e.g. `_fahrenheitToCelsius(double f)`) rather than inlining the formula twice.
**Risk: low blast radius, but zero tolerance for error.** It's one formula in two call sites, but getting the direction or arithmetic wrong wouldn't fail loudly — it would just keep silently mis-flagging fever, the exact bug being fixed. Must verify against known reference points (37°C ⇄ 98.6°F, 38.9°C ⇄ 102°F) in a test, not just eyeballed. Also note: this only fixes *future* visits — any already-submitted encounters that were wrongly flagged (or wrongly NOT flagged, if a genuinely high fever in °F somehow read as normal in the broken comparison) are not retroactively corrected; that's a data-cleanup question, out of scope here.

**1.2 Wire up real numeric range validation.**
- Extend `FieldDef`/`FieldDef.fromJson` (`form_config.dart:87-148`) to parse `minValue`/`maxValue`/`errorMessage` from the JSON (already present for some fields, e.g. `gravida.minValue`, `temperature.minValue`).
- `systolic`/`diastolic`/`fundalHeight` have **no bounds in the source JSON either** — author clinically-sane bounds directly in `form_config.dart` or a small constants file alongside the existing `assessment_thresholds.dart` (e.g. systolic 60–260, diastolic 30–150, fundal height 10–45cm), consistent with the JSON convention that **0 is a valid sentinel for "could not be measured"** (see `systolic.infoTitle: "0 –If BP could not be measured"`) — any bounds check must special-case 0 as allowed, not reject it as an implausible low reading.
- Add a `Form` + `GlobalKey<FormState>` wrapping the field list in `unified_form_screen.dart`, and call `formKey.currentState!.validate()` inside `_onSubmit` (`unified_form_screen.dart:346-364`) alongside the existing presence check — this activates the 3 already-wired-but-dead validators (`_numericRangeValidator`, lines 1983-2016) for free, plus the new BP/fundal-height coverage.
**Risk: medium — hand-authored bounds could block a real emergency.** These bounds are a clinical judgment call, not sourced from the JSON — if set too tight, a genuine hypertensive-crisis reading (e.g. systolic 250) could get rejected at exactly the moment it matters most, which is worse than no validation at all. Bounds must be chosen conservatively wide and reviewed by someone clinical before shipping. Separately, wrapping the existing field list in a `Form` for the first time is new territory for this screen — needs a full click-through of Step 2 (not just the changed fields) to confirm nothing about focus order, autofill, or the AI Scribe fill-in path breaks under the new `Form` ancestor.

**1.3 Conditional-visibility engine — replace the discarded logic.**
Verified JSON schema: a *driver* field carries a `condition` array — e.g. `pncNeonateSigns` (field_library.json:259-264) has `{eq: "Other", targetId: "otherPncNeonateSigns", visibility: "visible"}`, meaning "when `pncNeonateSigns`'s value equals `'Other'`, set `otherPncNeonateSigns`'s visibility to visible" (its own base `visibility` is `"gone"`, i.e. hidden by default).
- Extend `FieldDef.fromJson` to parse `condition` (list of `{eq, targetId, visibility}`) and the field's own base `visibility` string, plus `infoTitle`/`isInfo` (needed for Phase 2 too — same JSON objects, parse once).
- Build a `Map<String, List<_FieldRule>>` keyed by `targetId` once when the field library loads (e.g. in `form_config.dart` alongside where `FieldDef`s are loaded), so each field can look up "who controls my visibility."
- Add `bool isFieldVisible(FieldDef field, Map<String, dynamic> values)`: look up rules for `field.id`; if a rule's driver field's current value equals `rule.eq`, return `rule.visibility == 'visible'`; if no rule matches, fall back to `field.visibility != 'gone'`.
- Wire this into the field-rendering loop in `unified_form_screen.dart` (skip fields where `isFieldVisible` is false) and into `_computeValidationErrors` (`unified_form_screen.dart:382-399`) so a hidden-but-mandatory field never blocks submission.
- **Obstetric-history chain (Gravida→Parity→Living Children→Age of Last Child) is a separate mechanism** — `compositeGroup`/`compositeRole` tags (`trigger`/`member`) exist in the JSON but the actual reveal threshold (e.g. "Parity only shown once Gravida ≥ 2") is **not** encoded in the JSON — it only lives in the mockup's `handleGravidaChange()` JS (`apon_sushashthya_v13.html`). This needs a small hand-authored rule (3-4 fields, similar in size to the existing 4 hand-coded section rules in `unified_section_rules.dart`) — read the exact thresholds from that JS function before implementing so the Flutter behavior matches the design intent exactly.
**Risk: highest in this plan.** This is the most structurally invasive change here — it touches the field-rendering loop and the shared validation gate used by every programme (ANC/NCD/PNC/pncChild/pncNeonatal), not just the fields sampled during this audit. Only a handful of the ~96 `condition` rules were actually inspected; a misread rule could newly hide a field that should stay visible (silently dropping data capture for real patients) or newly show/require one that shouldn't apply. The validation-gate change is shared code — a bug there could either wrongly block all Step 2 submissions (regression that stops every SK cold) or wrongly let a truly-required field through unchecked. This needs the most thorough manual QA of anything in the plan — walk all 5 programme paths, not just ANC, before merging. Recommend this lands as its own PR, separate even from 1.1/1.2, so a revert is cheap and isolated if something's off.

**1.4 Debounce autosave.** In `unified_form_notifier.dart`'s `updateField()`/`_saveDraft()` path (lines 251-265), add a ~400ms `Timer` that resets on every keystroke and only persists once it fires, instead of saving synchronously on every character.
**Risk: low today, latent otherwise.** A debounce window means the in-memory value and the persisted draft briefly diverge; if the app is killed mid-window, the draft would hold a stale/partial value. This is low-risk *right now* because the same-day draft-resume feature is currently disabled (`_resumeFeatureEnabled = false`, from earlier work). Worth re-checking this interaction if/when draft-resume is re-enabled.

### Phase 2 — Design gaps

**2.1 Render `infoTitle`/`isInfo` help text.** Now that Phase 1.3 parses these into `FieldDef`, add a small muted-text widget under any field that has `isInfo == 'visible'`, showing `infoTitle` (reuse the existing hint/subtitle text style already in `_FieldShell`).
**Risk: low.** Purely additive text — worst case is a layout/overflow issue on a long `infoTitle` string on a small screen, easy to catch visually.

**2.2 Severity color-coding for tri-state chips.** Extend `_PillButton` (`radio_form_field.dart:84-90`) to accept an optional per-option color, driven by a small lookup keyed by field id + option value (e.g. `urinaryAlbumin: {'Present': red, 'Trace': amber, 'Absent': green}`, `fetalMovement: {'Not felt': red, ...}`) — the JSON doesn't carry a color hint, so this table is hand-authored to match the mockup's specific colors (`apon_sushashthya_v13.html:2989-3018`).
**Risk: low-medium.** The color table is keyed by exact option-value strings — a typo or mismatch against the actual `optionsList` values in the JSON would silently fall back to no color (fails quiet, not loud), so this needs to be checked against the live options for each field, not just copied from reading the mockup.

**2.3 Sequential question numbering** for the pregnancy-history section only (matching the mockup) — add an index prefix in the section-building loop where `family == 'pregnancyHistory'` fields are rendered, not a global change to `_FieldLabel`.
**Risk: low.** Cosmetic, scoped to one section/family.

**2.4 NCD BP status badge.** Wire the existing, already-correct `_VitalStatusEval.bloodPressure()` into `_BpReadingField` (`unified_form_screen.dart:3138-3287`, the NCD path) the same way `_bpPairCard` (ANC path, lines 1485-1503) already does — reuse, don't reimplement.
**Risk: low, with one check needed.** Reusing tested logic, but the app's own docs describe different BP band thresholds for NCD (180/110, 160-179/100-109, etc.) vs. ANC (160/110, 140/90) — confirm `_VitalStatusEval.bloodPressure()`'s thresholds are the ANC ones before assuming they're also correct for NCD; if not, this needs an NCD-specific variant rather than a straight reuse.

**2.5 BP caption style** (low priority/cosmetic): change "Systolic"/"Diastolic"/"Pulse" from a permanent caption (`_bpCell`, lines 3258-3286) to placeholder-inside-input, matching the mockup and the rest of the file's input style.
**Risk: low.** Cosmetic only.

### Phase 3 — Labels / localization cleanup

**3.1** Fix the 2 hardcoded strings: `unified_form_screen.dart:1562` → use existing `UnifiedFormStrings.bpPulseLabel`; `:3460` → add a new `UnifiedFormStrings.selectAtLeastOneOption` constant and use it.
**Risk: negligible.** Same string value, just routed through the constant.

**3.2** Remove redundant Bengali constants (`UnifiedFormStrings.bpCardSubLabel`, `glucosePairSubLabel`, `bloodGlucoseEntrySubLabel`) — source directly from `FieldDef.labelCulture` (already populated from `field_library.json`'s `titleCulture`) at their call sites instead of a second hardcoded copy in `app_strings.dart`.
**Risk: low, but verify before deleting.** Must diff the `app_strings.dart` value against the JSON's `titleCulture` character-for-character before removing — if they've silently drifted apart (one updated, the other not), deleting the "wrong" one changes visible copy. Confirm equality first, don't assume it from the audit's sampling.

**3.3** Backfill Bengali `titleCulture` for the 15 fields currently missing it (`fetalMovement`, `ancBloodGlucose`, `ancDangerSigns`, `lowBirthWeight`, `pncNeonateSigns`, `otherPncNeonateSigns`, `deathOfNewborn`, `folicAcidTablets`, + 7 more) directly in `assets/forms/field_library.json`. **These need clinically-appropriate Bengali phrasing** and should get a native/clinical review pass before shipping, not treated as final on automated authoring alone.
**Risk: medium, but it's a content risk, not a code risk.** Wrong or awkward Bengali phrasing on danger-sign fields (`ancDangerSigns`, `deathOfNewborn`) is worse than the current blank state if it confuses a CHW in the field — this is the one item in the whole plan that should not ship without native-speaker/clinical review.

**3.4** Remove 2 dead `UnifiedFormStrings` constants: `noPathways`, `validationBannerTitle`.
**Risk: negligible.** Confirmed unreferenced; a final grep before deletion is enough.

**3.5** Factor the duplicated required-field asterisk (`TextSpan(' *', ...)` copy-pasted in `_FieldLabel` and `_InlineListHeader`) into one shared widget/helper.
**Risk: negligible.** Pure refactor of identical code into one place.

**Explicitly not in this plan:** the IMCI/TB field-library gap (labels finding #5) — those programmes having no `field_library.json` entries at all is a much larger structural gap (a whole missing data source, not a copy fix) that deserves its own separate scoping conversation, not a line item here.

---

## Verification

- `dart analyze` on every changed file per phase.
- `flutter test` full suite after each phase — confirm baseline holds (403 passed / 18 pre-existing failures), no new regressions.
- **New targeted tests** (Phase 1, given the clinical-safety stakes):
  - Temperature: a 98.6°F entry must NOT trigger the ANC/PNC high-fever referral path (regression test for the exact bug found).
  - Conditional visibility: `otherPncNeonateSigns` hidden by default, visible only when `pncNeonateSigns == 'Other'`; a hidden mandatory field must not block submit.
  - Numeric bounds: systolic/diastolic/fundal-height reject out-of-range values but accept `0` as the "not measured" sentinel.
- **Manual on-device check** (per phase):
  - Phase 1: start an ANC visit, enter a normal temperature, confirm no false fever referral at Step 3; enter Gravida=1, confirm Parity/Living Children/Age-of-Last-Child stay hidden; try to submit a wildly out-of-range BP, confirm it's blocked.
  - Phase 2: confirm Urine Protein "Present" and Fetal Movement "Not felt" render red; confirm info text appears under Parity/Systolic; confirm NCD BP entry now shows a status badge.
  - Phase 3: spot-check the corrected hardcoded strings and a couple of newly-backfilled Bengali labels render correctly.
