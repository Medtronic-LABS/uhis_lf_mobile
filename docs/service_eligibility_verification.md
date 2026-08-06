# Service Eligibility — Verification Against `design/service_eligibility_logic.json`

`design/service_eligibility_logic.json` is a real API response (`POST /spice-service/static-data/form-data`)
from the Android reference app's `clinicalTools` payload — each clinical service (NCD, Eye Care,
Cataract, PW Profile, Family Planning, Pregnancy Outcome, RMNCH, Confirm Diagnosis) carries a
`conditions` array (`gender`, `minAge`/`maxAge` **in months**, `subModule`) gating which service tiles
a household member is eligible for. This doc verifies the Flutter app's equivalent logic against it,
**treating the JSON as the source of truth**.

## Android reference algorithm (confirmed against `spice_mobile`, Kotlin source)

The real gate is a Room SQL query (`MetaDataDAO.kt:126-131`), not Kotlin branching:

- `minAge` is **inclusive** (`minAge <= age`), `maxAge` is **exclusive** (`maxAge > age`) — asymmetric.
- Age is computed in **whole months from DOB**, calendar-aware (not naive years×12).
- Multiple `conditions` on one tool are **OR'd** — any single condition matching shows the tool (this
  is how RMNCH's 3 heterogeneous conditions work as one tile).
- A condition with no `gender`/age fields (Confirm Diagnosis) does not match this gate at all — Android
  routes it around the gate entirely as a static, role-based menu item.
- RMNCH stays a single tile; its label/target form swaps between ANC/PNC/"Child Health" via `subModule`.
- PW Profile / Family Planning / Pregnancy Outcome have additional disable-logic beyond the shared
  age/gender condition (LMP/delivery day-counts, a re-show cooldown) — age/gender gates whether the
  tile *exists*; separate pregnancy-state logic gates whether it's *enabled*.

## Fixed (this change)

**1. NCD gated at 15 years in the selectable card; JSON says 18 (`minAge: 216`).**
`symptom_picker_screen.dart`'s `_InlineServiceSelector._visibleCards()` fell through to a generic
`ctx.ageYears >= 15` for NCD — never updated when `pathway_rules_v1.dart`'s NCD gate was corrected to
216 months elsewhere in this same branch. Fixed: NCD now uses `ctx.isAdult` (`ageMonths >= 216`), an
already-existing `PatientContext` getter that exactly matches the JSON.

**2. Eye Care / Cataract had no 35-year gate anywhere (JSON: `minAge: 420`, both, no upper bound).**
Confirmed in three places: the selectable card (generic 15yr fallback), `pathway_rules_v1.dart`
(`DemographicGate.any` — no age check at all), and `unified_section_rules.dart`'s existing 35-year gate
turned out to be a *different, narrower* feature (hides an eye-care sub-section embedded inside an
already-active NCD form — confirmed by its own test, `ncd_eye_care_age_gate_test.dart`, to leave the
standalone `eye_care` form untouched). A 15-34-year-old could select "Eye Care"/"Cataract" as standalone
services — the largest live gap found. Fixed: new `PatientContext.isEyeCareCataractEligible`
(`ageMonths >= 420`) getter, used in both the selectable card and `pathway_rules_v1.dart`'s
`DemographicGate` for both programmes.

**3. Reproductive-age lower bound was 15 years in the card gate; JSON (and this file's own already-correct
ANC/PNC `pathway_rules_v1.dart` gate) say 14 (`minAge: 168`).**
Same class of bug as #1 — one layer (`pathway_rules_v1.dart`) had already been corrected to 168 months
for ANC/PNC; the selectable card never was. Fixed: new `PatientContext.isReproductiveAge`
(`ageMonths >= 168 && ageMonths < 661` — inclusive min, exclusive max, computed from `ageMonths`
directly rather than a derived `ageYears` comparison, since 661 months is 55 years *and 1 month*, not an
even year boundary), used for PW/delivery/ANC/PNC/FamilyPlanning in the selectable card.

**4. Family Planning's upper bound disagreed with itself across 3 numbers; JSON says 661 months (~55yr,
exclusive).**
`pathway_rules_v1.dart` used a literal `588` (49yr), inconsistent with the same file's own `168`
constant used for ANC/PNC's lower bound; the selectable card had no upper bound at all. Fixed: replaced
the `588` literal with a new shared `reproductiveMaxAgeMonths = 661` constant, applied to FP, ANC, and
PNC consistently in `pathway_rules_v1.dart` (ANC/PNC previously had no upper bound at all either).

## Explicitly not changed, and why

**RMNCH `childhoodVisit` (JSON: 0-25 months) vs. `VisitFlowScreen._isChildVisit`'s under-5-year (0-59
month) routing.** This looked like a candidate discrepancy but is a different concern, not a wrong
number: `_isChildVisit` routes to a broader "child/EPI/IMCI" flow (`_Step2Vaccination` →
`ImmunisationTimelineScreen` → `ChildAssessmentSection`, per `design/screen-map.md`) that handles
sick-child assessment (IMCI) generally for the whole under-5 population — IMCI/EPI/TB do not appear as
tools in this JSON at all, so the JSON has nothing to say about that routing decision. RMNCH's own
narrow `childhoodVisit` submodule (0-25mo) is a distinct, currently-unimplemented concept (no Flutter
code gates specifically on it) rather than an existing gate with the wrong threshold. Narrowing
`_isChildVisit` to 25 months would stop routing 26-59-month-olds to the working IMCI/vaccination flow
with no JSON-specified replacement — a functional regression, not a parity fix. **Needs a product/
clinical scoping conversation before any code change here.**

**Confirm Diagnosis** — no Flutter counterpart found. Android itself routes this around the per-patient
age/gender gate entirely (a static, role-based provider menu item, not a per-patient clinical service),
consistent with its condition having no gender/age fields at all. Likely out of scope for the SK/
community-worker app.

## Files changed

- `lib/features/visit/triage/patient_context_builder.dart` — added `isEyeCareCataractEligible` and
  `isReproductiveAge` getters alongside the existing `isAdult`.
- `lib/features/visit/triage/symptom_picker_screen.dart` — `_visibleCards()` now uses `ctx.isAdult`
  (NCD), `ctx.isEyeCareCataractEligible` (Eye Care/Cataract), and `ctx.isReproductiveAge`
  (PW/delivery/ANC/PNC/FamilyPlanning) instead of the generic `ageYears >= 15` fallback.
- `lib/features/visit/pathway/pathway_rules_v1.dart` — added `reproductiveMaxAgeMonths` (661) and
  `eyeCareCataractMinAgeMonths` (420) constants; Eye Care/Cataract gates now use the latter instead of
  `DemographicGate.any`; ANC/PNC/FamilyPlanning gates now include the shared upper bound.
- `test/features/visit/triage/patient_context_eligibility_test.dart` (new) — boundary tests for the two
  new getters.
