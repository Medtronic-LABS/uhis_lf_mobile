# Visit Feature — Developer Reference

## Overview

The visit feature is the core clinical workflow for the SK (community health worker). It is a
single-route, 3-step flow hosted entirely inside `VisitFlowScreen` (`visit_flow_screen.dart`) —
the SK never navigates away from `/patients/visit/:visitId/flow` while the visit is in progress;
step transitions are internal state changes (`_VisitFlowState._step`), not route pushes.

```
_Step1Symptoms          →  _Step2ProgrammesThenForm       →  _Step3AiReco
(SymptomPickerScreen)      or _Step2Vaccination (young child) (AI recommendation)
   Step 1                  (VisitFormScreen)                     Step 3
                              Step 2
```

All steps share `VisitFlowHeader`, a progress-bar app bar that shows the current step.

---

## Step-by-step flow

### Step 1 — SymptomPickerScreen (`triage/symptom_picker_screen.dart`)

The SK selects symptoms from a clustered list (`UnifiedSymptomCatalog`, grouped by
`SymptomCluster`), and reviews/edits the **Eligible Services** grid (`_InlineServiceSelector`) —
the SK-facing surface for which programmes are active this visit.

`TriageViewModel` maintains selected symptoms and drives `PathwayEngine.activate()` on every
toggle, producing rule-based `ActivatedPathway`s live. `ProgrammeGridSync` merges three sources
into the grid: rule-engine activations, `UnifiedSymptomCatalog` per-symptom programme tags
(finer-grained than the rule engine), and the patient's enrolled programmes (`PatientContext`,
gated by current pregnancy/postpartum state).

**`ServiceSelectionResolver` (`triage/service_selection_resolver.dart`) is the single,
authoritative choke point for finalizing that selection**, run in `_doAdvance()` right before the
SK leaves Step 1:
- Canonical clinical-priority ordering (`canonicalPriority`) — the final set is always
  priority-sorted, so "primary programme" and section ordering downstream are deterministic.
- Business-rule gating: PW-once-only (silent drop), ANC blocked postpartum or within the
  risk-based revisit interval (dialog, SK stays on Step 1 with the correction applied), PW
  auto-added alongside a first-time ANC selection.
- Pilot-scope exclusion (`excludedFromSelection`) — filters programmes whose form isn't ready yet
  (currently `nutrition`, no formType exists; `tb`, form content not yet aligned) regardless of how
  they entered the set. `epi` is deliberately **not** filtered here — it's handled entirely by the
  `_isChildVisit` → `_Step2Vaccination` route, which never reaches this pipeline.

**Step 2 does not re-derive or re-gate this set** — it renders whatever `ServiceSelectionResolver`
produced. If you're adding a new business rule about which programmes can be selected, it belongs
in `ServiceSelectionResolver`, not in Step 2.

### Step 2 — `_Step2ProgrammesThenForm` / `_Step2Vaccination` → `VisitFormScreen`

Young-child (`PatientContext.isYoungChild`, < 25 months — RMNCH `childhoodVisit`) / EPI visits route
to `_Step2Vaccination` (immunisation timeline, `immunisation/immunisation_timeline_screen.dart`) —
structurally separate from the generic form pipeline below.

All other visits render `VisitFormScreen` (`visit_form_screen.dart`), which:
1. Resolves programme names → formType keys via `FormTypeResolver.resolve()`
   (`forms/form_type_resolver.dart` — e.g. `pnc` → `pncMother`, `imci` → `pncChild`).
2. Builds a `UnifiedFormNotifier` (`forms/unified_form_notifier.dart`) with those formTypes.
3. Renders `UnifiedFormScreen` (`forms/unified_form_screen.dart`), which composes sections via
   `UnifiedSectionRules.activeSections()` (`forms/unified_section_rules.dart`) reading
   `assets/forms/layout_manifests.json` — enrolled formTypes render first, then remaining active
   ones; field ownership/de-duplication is resolved by a `claimedFieldIds` set (first section to
   include a field claims it).

CDS/referral evaluation runs per-formType in `UnifiedFormNotifier._computeReferral()`, gated by
`if (activeFormTypes.contains('<formtype>'))` — see `NcdReferralEvaluator`, `AncReferralEvaluator`,
`PncReferralEvaluator` in `../../core/clinical/referral_evaluator.dart`. There is currently no
cross-programme "field value → activate another programme mid-form" mechanism (e.g. a high BP on
an ANC-only visit does not add the NCD section) — referral evaluators can only fire for a formType
that's already active.

### Step 3 — `_Step3AiReco`

Calls `NabaRepository.generate()` with the visit context assembled from prior steps, renders the
structured care plan (danger signs, findings, next actions, counselling, referral). The response
is a *proposal* — accepting it is what writes FHIR resources and logs the rationale snapshot.

---

## Core components

### PathwayEngine (`pathway/pathway_engine.dart`)

Pure function: `PathwayEngine.activate(symptoms, context) → List<ActivatedPathway>`, sorted
ascending by priority (lower = higher urgency) and deduped by programme.

Evaluates `PathwayRulesV1.all` against the symptom set and patient demographics/history
(`DemographicGate`, `anyOf`, `combinations`, `historyTriggers`), plus two synthetic additions
outside the rule table: an EPI-due pathway (`Programme.imci`, priority 100 — "EPI uses IMCI
programme type") and an elevated-BP NCD pathway. `PathwayRulesV1.forProgramme()` is the only other
public entry point on the rule table.

**Important age gates (pathway_rules_v1.dart):**

| Programme | Rule | minAgeMonths | Note |
|---|---|---|---|
| IMCI | Various | 2 (`neonateMaxAgeMonths`) | maxAgeMonths: 24 (`imciMaxAgeMonths`) — not the same as `PatientContext.isYoungChild`'s 25-month Step-2-routing gate above; different source ("Bangladesh UHIS Phase 1 spec" vs. RMNCH `childhoodVisit`), one month apart, reviewed and left as two distinct constants |
| NCD-HTN | bp_stage1 etc. | 216 (18 yr) | Adults only |
| NCD-DM | polyuria+polydipsia | 216 (18 yr) | Was `any` which caused false activation for toddlers |
| ANC | pregnant + dizziness | — | requiresPregnant: true |
| PNC | postpartum | — | requiresPostpartum: true |

### Eligibility & Service Selection (`triage/patient_context_builder.dart`, `triage/symptom_picker_screen.dart`, `triage/programme_grid_sync.dart`, `triage/service_selection_resolver.dart`)

What decides which service cards show on Step 1, which are locked, and how programmes get
auto-selected without the SK tapping anything.

**Source of truth**: `design/service_eligibility_logic.json`, a real API response
(`POST /spice-service/static-data/form-data`) from the Android reference app's `clinicalTools`
payload. Each clinical service (NCD, Eye Care, Cataract, PW Profile, Family Planning, Pregnancy
Outcome, RMNCH, Confirm Diagnosis) carries a `conditions` array (`gender`, `minAge`/`maxAge` in
months, `subModule`) gating eligibility. The real gate on the Android side is a Room SQL query
(`MetaDataDAO.kt:126-131`), not Kotlin branching, with rules this Flutter implementation mirrors:
- `minAge` is **inclusive** (`minAge <= age`), `maxAge` is **exclusive** (`maxAge > age`) — asymmetric.
- Age is computed in **whole months from DOB**, calendar-aware (not naive years×12).
- Multiple `conditions` on one tool are **OR'd** — any single condition matching shows the tool
  (this is how RMNCH's 3 heterogeneous conditions work as one Android tile).
- A condition with no `gender`/age fields (Confirm Diagnosis) doesn't match this gate at all —
  Android routes it around the gate entirely as a static, role-based menu item. **No Flutter
  counterpart exists** — likely out of scope for the SK/community-worker app.
- On Android, RMNCH stays a single tile whose label/target form swaps between ANC/PNC/"Child
  Health" via `subModule`; this Flutter app instead has separate ANC/PNC/Child Health cards, each
  with its own gate below.

**Patient-context age/gender thresholds** (`PatientContext` getters):

| Getter | Condition | Age in months |
|---|---|---|
| `isNeonate` | age < 2 months | 0–1 |
| `isInfant` | age < 12 months | 0–11 |
| `isYoungChild` | age < 25 months (RMNCH `childhoodVisit`) | 0–24 |
| `isReproductiveAge` | 14y ≤ age < 55y | 168–660 |
| `isAdult` | age ≥ 18y | ≥216 |
| `isEyeCareCataractEligible` | age ≥ 35y, any sex | ≥420 |
| `isPostpartum` | delivery within last 42 days | — |
| `isPregnant` | (pregnancyFacts ∨ activeProgrammes⊇{anc,pw} ∨ raw-JSON flag) ∧ ¬hasDelivered | — |

`isYoungChild` is deliberately **not** the same constant as `PathwayThresholds.imciMaxAgeMonths`
(24, in `pathway_rules_v1.dart`, see the pathway age-gates table above) — one gates whether the
Child Health/Vaccination *cards and Step-2 routing* apply (RMNCH `childhoodVisit`), the other
gates whether IMCI/ICCM is *suggested* as a pathway from symptoms ("Bangladesh UHIS Phase 1
spec"). They're one month apart by coincidence, not by a shared source — don't unify them.

**Step 1 card — visibility gate** (`_InlineServiceSelector._visibleCards`,
`symptom_picker_screen.dart` ~line 2267):

| Card | Programme | Shown when |
|---|---|---|
| PW / Pregnancy | — | female ∧ reproductive age |
| Pregnancy Outcome | — | female ∧ reproductive age |
| ANC | anc | female ∧ reproductive age ∧ not young-child |
| PNC | pnc | female ∧ reproductive age ∧ not young-child |
| Family Planning | familyPlanning | female ∧ reproductive age ∧ not young-child |
| NCD | ncd | `isAdult` (≥18y) |
| Eye Care | eyeCare | `isEyeCareCataractEligible` (≥35y) |
| Cataract | cataract | `isEyeCareCataractEligible` (≥35y) |
| Child Health (IMCI) | imci | `isYoungChild` |
| Vaccination | — | `isYoungChild` |
| **TB** | tb | **no card exists — by design, unreachable** |
| EPI | epi | no dedicated card; added silently at Continue if due |

Any adult-only card is blanket-hidden for a young-child patient before its specific rule runs.
The reproductive-age lower bound (14y/168mo) is far above `isYoungChild`'s 25-month ceiling, so
there's no overlap band needing a separate check. Ages roughly 3–14 are a known eligibility gap —
no card is shown at all (`hasAnyEligibleProgramme` in `core/clinical/service_eligibility.dart`
detects this to show a "no programmes available" toast instead of an empty grid).

**Step 1 card — lock gate** (`_isLocked`, `symptom_picker_screen.dart` ~line 2311):

| Card | Locked when | Never locked? |
|---|---|---|
| PW | delivery-visit mode ∨ postpartum ∨ open pregnancy episode exists | |
| ANC | PW not toggled on ∨ delivery mode ∨ within revisit interval (15d, or 1d if last visit high-risk) | |
| Pregnancy Outcome | not (pregnant ∧ not postpartum) ∨ no open pregnancy episode | |
| PNC | not postpartum | |
| Family Planning | currently pregnant (not postpartum) | |
| NCD | | ✅ never locked |
| Eye Care | | ✅ never locked |
| Cataract | | ✅ never locked |
| IMCI / Child Health | | ✅ hard-coded never locked |
| Vaccination | separate `vaccinationLocked` flag | |

**Auto-selection — three independent mechanisms**:

| # | Mechanism | Fires when | Adds | Can be suppressed by |
|---|---|---|---|---|
| a | `ProgrammeGridSync.additionsFromPathways` | every symptom-selection change | any pathway-engine-activated or symptom-catalog-tagged programme not yet selected | SK dismissal this visit (`dismissedBySk`); ANC never resurrected if revisit-too-soon; PW never resurrected if an episode is already open |
| b | `ProgrammeGridSync.applicableEnrolledSeed` | once, at patient load | historical/enrolled programmes filtered by current pregnant/postpartum state (ANC/PW only if pregnant; PNC only if postpartum; FP hidden while pregnant) | tb/nutrition never seeded (pilot-scope); ANC stripped again if revisit-too-soon; PW stripped again if episode open |
| c | `ServiceSelectionResolver.finalize` | once, at "Continue" tap | forces PNC on a delivery visit; auto-adds PW alongside a surviving ANC selection | pilot-scope exclusion (tb/nutrition, silent); PW-registration-blocked; postpartum/revisit blocks stop ANC (and therefore its PW auto-add) first |

**`ServiceSelectionResolver.finalize()` — rule order**:

| Step | Rule | Outcome if triggered |
|---|---|---|
| 1 | Delivery visit | force-add PNC |
| 2 | Pilot-scope exclusion | silently drop `tb`, `nutrition` (epi is exempt) |
| 3 | PW already registered | drop PW; if selection now empty → `silentlyEmptied`, stop |
| 4 | ANC + postpartum | drop ANC → `ancBlockedPostpartum`, stop |
| 5 | ANC + revisit too soon | drop ANC → `ancBlockedRevisit`, stop |
| 6 | ANC survives, PW not already registered | auto-add PW |
| 7 | — | sort survivors: imci(10) → pw(15) → anc(20) → pnc(25) → tb(30) → nutrition(35) → ncd(40) → familyPlanning(45) → cataract(46) → eyeCare(47) → epi(100) |

**Pathway vs. selectable service — the two layers**:

| Layer | What it is | Where it lives | User-visible effect |
|---|---|---|---|
| **Pathway** | A rule-engine *suggestion* — programme + priority + rationale, derived from symptoms/history via `PathwayRulesV1` | `pathway_engine.dart` / `pathway_rules_v1.dart` | Drives the ✦ sparkle badge and rationale text; not itself submittable |
| **Selected service** | Membership in `_selectedProgrammes` | `symptom_picker_screen.dart` | What's actually tappable, toggleable, and submitted |

The bridge is mechanism **a** above: every activated pathway gets pushed into the selected set
(unless dismissed or blocked), so a pathway suggestion auto-ticks a card — but the SK can always
untick it, and a locked card is never resurrected even if a pathway would otherwise re-add it.

### PregnancyCohortRules (`../../core/risk/pregnancy_cohort_rules.dart`)

Pure, live-derived pregnancy-episode state (`isActivePregnancy`, `isPostnatal`,
`daysSinceLmp`/`daysSinceDelivery`) computed from `PregnancySnapshotRow` against `now` — ported
from Android Spice's `PregnancyCohortRules`. Used by `ServiceSelectionResolver`'s callers to decide
the ANC/PW gating inputs; not a persisted status field on either side of the port.

### FormTypeResolver / UnifiedSectionRules (`forms/`)

Replace the old `SectionRegistry`/`FormCompositor` — form composition is now data-driven from
`assets/forms/layout_manifests.json` rather than a static Dart registry. See "Step 2" above.

---

## Routing

Single route for the whole flow:

```
/patients/visit/:visitId/flow   → VisitFlowScreen (all 3 steps, internal state)
```

`VisitFlowScreen` is constructed from `router.dart` with the patient/visit identifiers via route
`extra`; there is no `initialStep`/`seedProgrammes` — the flow always starts at Step 1 and derives
its programme set from `ServiceSelectionResolver`, not a caller-supplied seed.

---

## Submission

`UnifiedFormNotifier.submit()` fans out one `LocalAssessmentEntity` row per active programme,
sharing the same `encounterId`. Rows are inserted as pending and synced to the server on next
connection.

---

## String constants

All user-facing strings live in `lib/core/constants/app_strings.dart`, grouped by feature class
(e.g. `TriageStrings`, `VisitFormStrings`, `ComposerStrings`). No hardcoded copy in widgets — add a
new getter to the relevant class instead.

---

## Tests

```
test/features/visit/
├── visit_flow_screen_test.dart      # Step 3 header/body (runs via debugInitialStep — Steps 1-2
│                                       need the full Provider tree of DAOs)
├── forms/                           # FormTypeResolver, UnifiedSectionRules, payload mapper
├── pathway/                         # PathwayEngine rule activation, AI pathway client
└── triage/                          # TriageViewModel, ServiceSelectionResolver,
                                        ProgrammeGridSync, symptom catalogue,
                                        patient_context_eligibility_test.dart (age-gate boundaries)
```

Run all: `flutter test test/features/visit/`

---

## Common mistakes

| Mistake | Fix |
|---|---|
| NCD-DM fires for a child | `PathwayRulesV1` NCD-DM rule must have `minAgeMonths: 216`. |
| A business rule about which programmes can be selected lives in Step 2 | It belongs in `ServiceSelectionResolver` (Step 1) — Step 2 only renders. |
| New formType renders blank | Check it has an entry in `assets/forms/layout_manifests.json`, and isn't in `ServiceSelectionResolver.excludedFromSelection`. |
| New field not showing label | Add a case in the relevant `AppStrings` class. |
| `patientvisit/create` / offline-sync errors | App queues offline and retries; check `OfflineSyncService`, not this feature, first. |
| Changed `isYoungChild` and a pathway-suggestion test broke | Check `pathway_rules_v1.dart`'s `imciMaxAgeMonths` — it's a separate, differently-sourced constant, not the same gate. |
