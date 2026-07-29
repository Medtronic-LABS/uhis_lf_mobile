# Form SDK — Migration Plan

## Overview

Five sequential phases. The first two phases carry zero SDK risk. The remaining phases are additive and can be abandoned at any phase boundary with a single-line revert.

---

## Phase sequencing

### Phase 0 — Document (complete)

Produce the four design docs. No code or JSON changes.

**Deliverables:** `form_sdk_current_state.md`, `form_canonical_schema.md`, `form_sdk_transformer_plan.md`, `form_sdk_migration_plan.md`

---

### Phase 1 — Transformer (zero SDK risk)

**What changes:**
- New file: `lib/uhis_form/transformer/canonical_form_transformer.dart`
- New asset: `assets/forms/field_library.json` (Phase 2 delivers the enriched version; for Phase 1 this can be a copy of `program_forms_questions.json` translated to the canonical format for a single formType as a proof of concept)
- New asset: `assets/forms/layout_manifests.json` (one manifest entry per formType)
- `form_data_service.dart` lines 38–41: swap `entry['formInput']` for `_transformer.toLegacyFormInput(...)`

**What does NOT change:**
- `FormSchemaParser` — untouched
- `FieldSchema`, `FieldKind`, `ConditionSchema` — untouched
- All widgets — untouched
- `program_forms.json` (legacy) — still present as fallback

**Validation gate:**  
CI diff script must pass before merging (see Validation section below).

---

### Phase 2 — Canonical JSON alongside legacy

**What changes:**
- `assets/forms/field_library.json` — fully populated for all 13 formTypes; `snomedCode`/`snomedDisplay` upgraded to `clinicalConcept` arrays; `programs` upgraded to typed `programmes` objects; `compositeGroup`/`compositeRole` added to composite fields
- `assets/forms/layout_manifests.json` — all 13 formTypes have complete `sections` + `fieldRefs`
- `program_forms.json` still present — transformer is the active source but legacy is still valid fallback

**What does NOT change:** SDK files unchanged.

**Validation gate:** CI diff must pass for all 13 formTypes.

---

### Phase 3 — Cutover

**What changes:**
- `FormDataService._ensureLoaded()` no longer loads `program_forms.json` — loads only `field_library.json` + `layout_manifests.json`
- Legacy `formInput` strings in `program_forms.json` can be stripped or the file deprecated

**Validation gate:** CI diff script passes (comparing transformer output against a snapshot of legacy parser output taken before Phase 3).

---

### Phase 4 — Legacy deprecated

**What changes:**
- `program_forms.json` with `formInput` strings removed from `assets/` (or deleted entirely)
- `CanonicalFormTransformer` remains; it is now the only code path

---

### Phase 5 — SDK internal refactor (separate effort, not in scope)

Implement the deferred SDK changes listed in `form_sdk_transformer_plan.md`:
- Add `clinicalConcept` to `FieldSchema`
- Add `programmes` to `FieldSchema`
- Replace composite ID heuristics with `compositeGroup`/`compositeRole`
- Remove `raw` pass-through
- Replace hardcoded `LoincVitalCodes` in `fhir_observation.dart` with canonical LOINC lookups

---

## Consumption point risk matrix

Every downstream consumer of the form SDK is listed. "Covered" means the transformer outputs exactly what the consumer currently expects.

| Consumption point | File | Line | Risk | Covered by transformer? |
|---|---|---|---|---|
| JSON load & unwrap | `form_data_service.dart` | 60–68 | Transformer replaces `formInput` string source | ✅ |
| Parser double-decode | `form_schema_parser.dart` | 31 | Transformer still outputs a `String` | ✅ |
| `viewType` switch | `form_schema_parser.dart` | 101–125 | `widgetHint` maps 1:1 to legacy `viewType` values | ✅ |
| `isMandatory` / `unit` / `min` / `max` / `hint` parse | `form_schema_parser.dart` | 318–326 | Key names unchanged; pass-through | ✅ |
| Option list parse (`optionsList`/`options`) | `form_schema_parser.dart` | 348–360 | Transformer flattens `clinicalConcept` back to `snomedCode`/`snomedDisplay` on options | ✅ |
| Condition array parse | `form_schema_parser.dart` | 362–371 | `condition[]` structure unchanged; pass-through | ✅ |
| Composite ID heuristics | `form_schema_parser.dart` | 145–195 | Parser still uses ID string heuristics; `compositeGroup` exists in canonical but NOT read by parser yet | ⚠️ Gap — deferred |
| `snomedCode` in `FieldSchema.raw` | `field_schema.dart` | 79 | Transformer outputs `snomedCode`/`snomedDisplay` so they appear in `raw` | ✅ |
| Widget dispatch | `lib/uhis_form/widgets/field_renderer.dart` | 58 | `FieldKind` from parser output — unaffected | ✅ |
| Visibility evaluation | `lib/uhis_form/controller/condition_evaluator.dart` | 20 | Reads `FormSchema` output — not affected by source JSON | ✅ |
| Draft persistence | `lib/uhis_form/controller/dynamic_form_controller.dart` | 140, 172–191 | Uses `FieldSchema.fieldId` and `subFieldIds` — unaffected | ✅ |
| LOINC vital extraction | `lib/core/models/fhir_observation.dart` — `LoincVitalCodes` | — | Hardcoded Dart; canonical LOINC codes exist in field library but not yet consumed | ⚠️ Gap — Phase 5 |

**Summary:** 11 consumption points. 9 fully covered by transformer. 2 gaps — both noted as deferred and neither affects the form rendering or submission flow:
1. Composite heuristics still apply (no regression; heuristics still work for current field IDs)
2. LOINC extraction remains hardcoded (no regression; hardcoded values are still correct)

---

## Rollback strategy

Each phase has a single-line rollback:

| Phase | Rollback action |
|---|---|
| Phase 1 | Revert `form_data_service.dart` lines 38–41 to `entry['formInput'] as String?` |
| Phase 2 | No code change needed; transformer still works; field_library.json and layout_manifests.json can be updated |
| Phase 3 | Restore `_ensureLoaded()` to load `program_forms.json`; restore `formInput` parsing |
| Phase 4 | Restore `program_forms.json` from git history |

No `FormSchemaParser`, `FieldSchema`, or widget code changes exist at any phase — there is nothing to revert in the SDK.

---

## CI validation script

Run on every change to `field_library.json`, `layout_manifests.json`, or `program_forms.json`.

**Algorithm (pseudocode):**

```
FAIL = false

for each formType in layout_manifests:

  // Legacy path
  legacy_formInput = program_forms.json[formType].formInput
  legacy_schema    = FormSchemaParser.parse(formType, legacy_formInput)

  // Canonical path
  canonical_formInput = CanonicalFormTransformer.toLegacyFormInput(
    formType, fieldLibrary, layoutManifests[formType]
  )
  canonical_schema = FormSchemaParser.parse(formType, canonical_formInput)

  // Assertions
  if legacy_schema.allFields.map(f => f.fieldId) != canonical_schema.allFields.map(f => f.fieldId):
    print "FAIL [field IDs] formType=" + formType
    print "  legacy:    " + legacy_schema.allFields.map(f => f.fieldId)
    print "  canonical: " + canonical_schema.allFields.map(f => f.fieldId)
    FAIL = true

  if legacy_schema.sections.map(s => s.title) != canonical_schema.sections.map(s => s.title):
    print "FAIL [section titles] formType=" + formType
    FAIL = true

  if legacy_schema.allFields.map(f => f.kind) != canonical_schema.allFields.map(f => f.kind):
    print "FAIL [field kinds] formType=" + formType
    for each pair (l, c) where l.kind != c.kind:
      print "  " + l.fieldId + ": " + l.kind + " vs " + c.kind
    FAIL = true

  if legacy_schema.allFields.map(f => f.required) != canonical_schema.allFields.map(f => f.required):
    print "FAIL [required flags] formType=" + formType
    FAIL = true

if FAIL: exit(1)
else:    print "All " + N + " formTypes match. ✓"
```

**Implementation note:** This script should be written as a Dart test file at `test/form_sdk/canonical_transformer_parity_test.dart` so it runs in `flutter test` as part of the standard CI suite. It does not require a device or emulator — it only exercises Dart in-process logic.

---

## Open questions to resolve before Phase 1

1. **`fieldName` vs `id`** — Some legacy fields use `fieldName` as their stable identifier while others use `id` (`form_schema_parser.dart:331–334`). The canonical format uses `id`. The transformer must map from `id` to `fieldName` (or always output both keys) so the parser's `_fieldId()` helper continues to work.

2. **LOINC codes for vitals** — The canonical `clinicalConcept` for vitals should carry both SNOMED and LOINC. The LOINC codes for the standard vitals should be sourced from `fhir_observation.dart`'s `LoincVitalCodes` class before that class is eventually retired in Phase 5.

3. **Option `id` types** — Legacy option IDs are sometimes integers (`true`/`false` for boolean fields) and sometimes strings. The canonical schema allows `id: {}` (any type). The transformer must preserve the original type when flattening options.
