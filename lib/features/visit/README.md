# Visit Feature — Developer Reference

## Overview

The visit feature is the core clinical workflow for the SK (community health worker). It implements a
3-step flow: symptom selection → triage review → multi-programme assessment form.

```
SymptomPickerScreen  →  TriageResultScreen  →  VisitFormScreen
   (Step 1)                 (Step 2)           → SectionedAssessmentScreen
                                                    (Step 3)
```

All three screens share `VisitStepHeader`, a progress-bar app bar that shows the current step.

---

## Step-by-step flow

### Step 1 — SymptomPickerScreen (`triage/symptom_picker_screen.dart`)

The SK selects symptoms from a clustered list. Symptoms are defined in
`UnifiedSymptomCatalog` and grouped by `SymptomCluster`.

Key filtering:
- `requiresFemale: true` symptoms are hidden for male patients (e.g. vaginal bleeding, reduced fetal
  movement).
- `maxAgeMonths` symptoms are hidden when the patient exceeds the age cap (e.g. neonatal findings).

`TriageViewModel` maintains selected symptoms and drives `PathwayEngine.activate()` on every toggle.
The pathway list updates live as the SK picks symptoms, giving instant visual feedback.

On "Confirm" the screen navigates to Step 2, passing `List<ActivatedPathway>` via router `extra`.

Route: `/patients/visit/:visitId/triage-result`

### Step 2 — TriageResultScreen (`triage/triage_result_screen.dart`)

A pure read-only widget (no I/O, no ChangeNotifier) that:
1. Shows an urgency card: **Urgent** (red) for IMCI danger signs, **Warning** (amber) for other
   pathways, **Info** (blue) for routine visits.
2. Renders 2-3 measurement instruction cards tailored to the primary programme.
3. Shows a "Programme identified" banner listing all activated programmes.
4. CTA button navigates to Step 3.

Urgency is derived from `_primaryPathway.triggerSymptoms` — if any of
`{chest_indrawing, convulsions, stridor, unconscious}` are present in an IMCI pathway, the card is
red.

### Step 3 — VisitFormScreen + SectionedAssessmentScreen

`VisitFormScreen` (`visit_form_screen.dart`) receives `activatedPathways` (programme name strings)
from Step 2, reconstructs them as `ActivatedPathway` objects, and mounts
`SectionedAssessmentScreen`.

`SectionedAssessmentScreen` (`composer/sectioned_assessment_screen.dart`) renders a scrollable form
grouped by programme ("NCD checks", "ANC checks", etc.). CDS alerts and TB section injection run
live on every field change via `SectionedAssessmentViewModel`.

---

## Core components

### PathwayEngine (`pathway/pathway_engine.dart`)

Pure function: `PathwayEngine.activate(symptoms, context) → List<ActivatedPathway>`

Evaluates `PathwayRulesV1` against the symptom set and patient demographics. Rules are AND-gated
on:
- `combinations` — ALL symptoms in at least one combination set must be present.
- `anyOf` — at least one symptom from this set must also be present (optional, enhancing specificity).
- `DemographicGate` — `minAgeMonths`, `maxAgeMonths`, `sex`, `requiresPregnant`, `requiresPostpartum`.

Rules also fire from `historyTriggers` — known condition codes on `PatientContext` (e.g. `DIABETES`
activates NCD-DM regardless of selected symptoms).

**Important age gates (pathway_rules_v1.dart):**

| Programme | Rule | minAgeMonths | Note |
|---|---|---|---|
| IMCI | Various | — | maxAgeMonths: 60 (under-5 only) |
| NCD-HTN | bp_stage1 etc. | 216 (18 yr) | Adults only |
| NCD-DM | polyuria+polydipsia | 216 (18 yr) | Fixed in Phase 4.5 — was `any` which caused false activation for toddlers |
| ANC | pregnant + dizziness | — | requiresPregnant: true |
| PNC | postpartum | — | requiresPostpartum: true |

### SectionRegistry (`composer/section_registry.dart`)

Static list of all `FormSection` definitions across 7 programmes. Sections are programme-tagged
and priority-ordered. `SectionRegistry.forProgrammes(Set<Programme>)` returns only the sections
relevant to the given programme set.

**All 7 programme families and their sections:**

| Programme | Sections | Priority |
|---|---|---|
| IMCI | vitals, danger-signs, symptom-detail, iccm-classify | 10, 12, 30, 40 |
| TB | tb-screen-detail | 25 |
| ANC | anc-vitals, anc-specific | 12, 45 |
| NCD | ncd-htn, ncd-dm | 42, 43 |
| EPI | epi-review | 55 |
| NUTRITION | nutrition-detail | 35 |
| PNC | pnc-mother, pnc-neonatal, pnc-child | 46, 47, 48 |

**Shared fields** — when two sections both define a field (e.g. `bloodPressureSystolic` in both
`anc-vitals` and `ncd-htn`), the section with the **lower priority number** wins ownership.
`sharedFieldIds` on the section declares which fields may also appear in other sections.
`FormCompositor` builds a `fieldOwnership` map from this to prevent duplicate data collection.

### FormCompositor (`composer/form_compositor.dart`)

`FormCompositor.compose(List<ActivatedPathway>) → ComposedForm`

1. Calls `SectionRegistry.forProgrammes()` with the activated programme set.
2. Removes sections whose `minPathwayPriority` is above the pathway priority.
3. Deduplicates by `sectionId`.
4. Sorts ascending by `section.priority`.
5. Resolves `fieldOwnership` — lower-priority section wins on conflict.

`ComposedForm` exposes `sections` (ordered) and `fieldOwnership` (Map<fieldId, sectionId>).

### CDS Rules (`composer/cds_rules.dart`)

`CdsRules.evaluate(fieldValues, activeProgammes) → List<CdsAlert>`

Fires clinical decision support alerts based on field values. The key alert `bp_stage1`:
- Triggers at systolic ≥ 140 or diastolic ≥ 90.
- If `Programme.ncd` is **not** in `activeProgammes`: `action = CdsAction.addPathway, addPathway = Programme.ncd`.
- If NCD is already active: `action = CdsAction.continueAssessment, addPathway = null`.

This ensures the SK is prompted to activate the NCD pathway when BP crosses stage-1 threshold during
an ANC visit.

---

## Routing

All visit routes are nested under `/patients/`:

```
/patients/visit/:visitId/triage-result   → TriageResultScreen
/patients/visit/:visitId/form            → VisitFormScreen → SectionedAssessmentScreen
```

`TriageResultScreen` receives pathways via `state.extra['pathwayObjects']` (List<ActivatedPathway>).
`VisitFormScreen` receives programme name strings via `state.extra['activatedPathways']`
(List<String>) which it reconstructs into ActivatedPathway objects at priority=10.

---

## Submission

`UnifiedSubmissionOrchestrator.submit(draft)` fans out **one `LocalAssessmentEntity` row per
activated programme**. All rows share the same `encounterId` and each gets a unique `legId` (UUID).
Rows are inserted as `AssessmentSyncStatus.pending` and synced to the server on next connection.

The server endpoint is `POST /patientvisit/create`. A known 500 from `fhir-mapper` (provenance NPE)
does not block the SK — the offline queue holds rows and retries automatically.

---

## String constants

All user-facing strings live in `lib/core/constants/app_strings.dart`. Field labels are exposed via
`AppStrings.fieldLabel(fieldId)` and section titles via `AppStrings.sectionTitle(sectionId)`.

When adding a new field to `SectionRegistry`, also add:
1. A `static const String field<Name>` constant in `AppStrings` (or the relevant nested class).
2. A case in `AppStrings.fieldLabel()`.

When adding a new section, also add a case in `AppStrings.sectionTitle()`.

---

## Tests

```
test/features/visit/
├── gate3_flagship_test.dart          # ANC+NCD end-to-end: pathway → form → CDS → submission
├── composer/
│   └── section_registry_breadth_test.dart  # EPI, NUTRITION, PNC section coverage
├── pathway/
│   └── pathway_engine_test.dart       # Rule activation across all programmes
└── triage/
    └── triage_view_model_test.dart    # Pre-ticks, AI merge, scribe integration
```

Run all: `flutter test test/features/visit/`

---

## Common mistakes

| Mistake | Fix |
|---|---|
| NCD-DM fires for a child | `PathwayRulesV1` NCD-DM rule must have `minAgeMonths: 216`. Was `DemographicGate.any` — fixed in Phase 4.5. |
| New field not showing label | Add `fieldLabel()` case in `app_strings.dart`. |
| New section duplicated in composed form | Check `sharedFieldIds` — both sections must declare the shared field set, lower priority wins. |
| BP owned by wrong section | Lower `priority` number wins ownership. `anc-vitals` is priority 12; `ncd-htn` is 42. ANC wins. |
| `patientvisit/create` returns 500 | Known server-side fhir-mapper NPE on `provenance`. App queues offline; not a Flutter bug. |
