# Form SDK — Transformer Plan

## Goal

Introduce a `CanonicalFormTransformer` class that reads the canonical field library and layout manifests and outputs the exact JSON string that `FormSchemaParser.parse()` currently expects. The SDK's parsing, rendering, and visibility contracts are unchanged.

---

## Insertion point

`lib/uhis_form/form_data_service.dart` — `schemaForType()` method, lines 38–41.

**Today:**
```dart
// form_data_service.dart:38–41
final formInput = entry['formInput'] as String? ?? '{}';
final schema = _parser.parse(formType, formInput);
_cache[key] = schema;
return schema;
```

**With transformer (Phase 1):**
```dart
// form_data_service.dart — schemaForType(), same location
final formInput = _transformer.toLegacyFormInput(
  formType: formType,
  layoutManifest: entry,          // the layout manifest object for this formType
);
final schema = _parser.parse(formType, formInput);
_cache[key] = schema;
return schema;
```

`_parser.parse()` receives the **same `String` type** and the **same JSON structure** it expects today (`{ "formLayout": [...] }`). No changes to `FormSchemaParser`, `FieldSchema`, `FieldKind`, `ConditionSchema`, or any widget.

`_transformer` is an instance of `CanonicalFormTransformer`, injected or constructed in `FormDataService`. It holds a reference to the loaded field library (loaded once in `_ensureLoaded()`).

---

## `CanonicalFormTransformer` design

### Inputs

| Parameter | Type | Source |
|---|---|---|
| `formType` | `String` | Matched from the layout manifest |
| `layoutManifest` | `Map<String, dynamic>` | One entry from the layout manifests file |
| `fieldLibrary` | `Map<String, Map<String, dynamic>>` | Canonical field library keyed by field `id`, loaded once at startup |

### Output

`String` — a JSON string matching the legacy `formInput` format:

```json
{
  "formLayout": [
    { "viewType": "CardView", "id": "sectionId", "title": "Section Title" },
    { ...field1 in legacy shape... },
    { ...field2 in legacy shape... }
  ]
}
```

This string is passed directly to `FormSchemaParser.parse(formType, formInput)` at `form_schema_parser.dart:30`.

### Transformation rules (canonical → legacy)

| Canonical key | Legacy key | Rule |
|---|---|---|
| `widgetHint` | `viewType` | Direct copy — same values |
| `label` | `title` | Direct copy |
| `clinicalConcept[first where system=SNOMED_CT].code` | `snomedCode` | Extract first SNOMED entry's code; null if no SNOMED entry |
| `clinicalConcept[first where system=SNOMED_CT].display` | `snomedDisplay` | Extract first SNOMED entry's display; null if no SNOMED entry |
| `programmes[].id` | `programs` | Map object array to string array of IDs |
| `compositeGroup`, `compositeRole` | (dropped) | Not in legacy format — parser still uses ID heuristics (deferred) |
| `optionsList[n].clinicalConcept[first SNOMED].code` | `optionsList[n].snomedCode` | Per-option: flatten first SNOMED entry |
| `optionsList[n].clinicalConcept[first SNOMED].display` | `optionsList[n].snomedDisplay` | Per-option: flatten first SNOMED entry |
| `optionsList[n].clinicalConcept` | (dropped from output) | After flattening, remove the structured array |
| `inputType: "text"` | `inputType: 96` | Name → Android bitmask |
| `inputType: "integer"` | `inputType: 2` | Name → Android bitmask |
| `inputType: "decimal"` | `inputType: 8192` | Name → Android bitmask |
| All other keys | Same key | Pass-through unchanged |

### Section header insertion

For each section in `layoutManifest.sections[]`:
1. Insert a CardView item: `{ "viewType": "CardView", "id": sectionId, "title": sectionTitle }`
2. For each `fieldRef` in `fieldRefs[]`:
   - Look up the field in `fieldLibrary` by `fieldRef`
   - Apply the transformation rules above
   - Append the transformed field object to `formLayout`

Fields not found in `fieldLibrary` for a given `fieldRef` are skipped with a logged warning (not a hard failure) so a missing library entry doesn't crash the form.

### Output serialisation

Wrap the assembled `formLayout` array into `{ "formLayout": [...] }` and serialise with `jsonEncode`. This produces the double-encoded string that `FormSchemaParser.parse()` expects at line 31.

---

## What becomes possible without SDK changes (post Phase 2)

Once the canonical format is live, downstream code can read `clinicalConcept` directly from the field library **outside** the form SDK:

| Capability | How |
|---|---|
| FHIR Observation extraction | A `FhirObservationTransformer` reads `clinicalConcept` from the library and builds `Observation.code` directly — no more hardcoded `LoincVitalCodes` |
| Programme-aware field filtering | Query `fieldLibrary.values.where(f => f.programmes.any(p => p.id == formType))` without parsing form layouts |
| Clinical concept completeness audit | CI script enumerates fields where `clinicalConcept` is absent or has no LOINC entry |
| Cross-programme reporting | Aggregate answers from multiple form types for a shared field (e.g. temperature across ANC + PNC) using the stable `id` as the join key |

---

## Deferred SDK changes

These are NOT in scope for the transformer phase. They are listed here so they are not forgotten.

| Change | File affected | Why deferred | Trigger |
|---|---|---|---|
| Add `clinicalConcept` to `FieldSchema` | `lib/uhis_form/models/field_schema.dart` | Would require updating all `FieldSchema` construction call sites and existing tests | When FHIR extraction moves into the form SDK |
| Add `programmes` to `FieldSchema` | `lib/uhis_form/models/field_schema.dart` | No runtime consumer yet | When runtime multi-programme field filtering is needed |
| Replace composite ID heuristics with `compositeGroup`/`compositeRole` | `lib/uhis_form/parser/form_schema_parser.dart:145–195` | Parser change; requires coordinated removal of transformer's heuristic pass-through | After canonical format is stable in production |
| Remove `raw` pass-through from `FieldSchema` | `lib/uhis_form/models/field_schema.dart:79` | `raw` is the only way to access `snomedCode` at render time until `clinicalConcept` is on `FieldSchema` | After the `clinicalConcept` deferred change above |
| LOINC codes removed from `fhir_observation.dart` | `lib/core/models/fhir_observation.dart` | Must be replaced by reading `clinicalConcept[LOINC]` from the field library | After `FhirObservationTransformer` reads canonical format |

---

## File locations (new files only — no existing file modified in Phase 1)

| New file | Purpose |
|---|---|
| `lib/uhis_form/transformer/canonical_form_transformer.dart` | The transformer class |
| `assets/forms/field_library.json` | Canonical field definitions (enriched `program_forms_questions.json`) |
| `assets/forms/layout_manifests.json` | Array of layout manifest objects (one per formType) |

`form_data_service.dart` is modified only at `schemaForType()` lines 38–41 — the swap described above. No other existing file changes.
