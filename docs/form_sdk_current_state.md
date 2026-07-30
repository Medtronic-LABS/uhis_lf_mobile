# Form SDK — Current State

## 1. Current JSON field shapes

All examples are taken verbatim from `leapfrog-setup/program_forms_questions.json`.

### Example A — CardView (section header, no clinical concept)

```json
{
  "familyOrder": 0,
  "id": "pncNeonatal",
  "orderId": 1,
  "title": "PNC Visit - Neonate",
  "viewType": "CardView",
  "programs": ["pncNeonatal"],
  "snomedCode": null,
  "snomedDisplay": null
}
```

### Example B — DialogCheckbox with SNOMED on field and on options

```json
{
  "family": "maternalHealthAssessment",
  "hint": "Danger signs",
  "id": "postpartumDangerSigns",
  "isEnabled": true,
  "isMandatory": true,
  "orderId": 19,
  "title": "Danger Signs present",
  "viewType": "DialogCheckbox",
  "visibility": "visible",
  "programs": ["pncMother"],
  "snomedCode": "267024001",
  "snomedDisplay": "Postpartum danger signs",
  "optionsList": [
    { "id": 1, "name": "Heavy bleeding",              "value": "heavyBleeding",              "snomedCode": "131148009", "snomedDisplay": "Heavy bleeding" },
    { "id": 2, "name": "Foul-smelling discharge",     "value": "foulSmellingDischarge",      "snomedCode": "271939006", "snomedDisplay": "Foul-smelling discharge" },
    { "id": 3, "name": "Severe abdominal pain",       "value": "severeAbdominalPain",        "snomedCode": "55300003",  "snomedDisplay": "Abdominal pain" },
    { "id": 4, "name": "Severe headache/vision/conv", "value": "severeHeadacheVisionConvulsions", "snomedCode": "25064002", "snomedDisplay": "Headache" },
    { "id": 5, "name": "Perineal wound discharge",    "value": "perinealWoundDischarge",     "snomedCode": "76844004",  "snomedDisplay": "Wound discharge" },
    { "id": 6, "name": "Breast pain/swelling with fever", "value": "breastPainSwellingFever", "snomedCode": null,       "snomedDisplay": null },
    { "id": 7, "name": "None",                        "value": "none",                       "snomedCode": "260413007", "snomedDisplay": "None" },
    { "id": 8, "name": "Other",                       "value": "other",                      "snomedCode": "74964007",  "snomedDisplay": "Other" }
  ]
}
```

Note: option 6 (`breastPainSwellingFever`) has `null` codes — inconsistent coverage within a single field.

### Example C — EditText vital shared across two programmes

```json
{
  "applyDecimalFilter": true,
  "family": "maternalHealthAssessment",
  "hint": "[Enter number]",
  "id": "temperature",
  "inputType": 8192,
  "isEnabled": true,
  "isMandatory": true,
  "minValue": 0,
  "orderId": 0,
  "title": "Temperature",
  "unitMeasurement": "°F",
  "viewType": "EditText",
  "visibility": "visible",
  "programs": ["pncMother", "anc"],
  "snomedCode": "386725007",
  "snomedDisplay": "Body temperature"
}
```

---

## 2. How the SDK parses JSON into Dart objects

### Parsing chain (file:line)

| Step | File | Line | What happens |
|---|---|---|---|
| **Load** | `form_data_service.dart` | 62 | `rootBundle.loadString('assets/forms/program_forms.json')` — bundles asset |
| **Decode outer** | `form_data_service.dart` | 63 | `jsonDecode(jsonString) as Map<String, dynamic>` |
| **Unwrap** | `form_data_service.dart` | 64–68 | Extracts `entity.formData` (or `formData` directly) as `List<Map>` |
| **Dispatch** | `form_data_service.dart` | 40 | `_parser.parse(formType, formInput)` where `formInput` is a **raw JSON string** embedded inside each entry |
| **Double-decode** | `form_schema_parser.dart` | 31 | `jsonDecode(formInputJson)` — second parse to get the `formLayout` list |
| **Section detection** | `form_schema_parser.dart` | 50–61 | `CardView` items create `SectionSchema` objects |
| **Field dispatch** | `form_schema_parser.dart` | 72 | `_parseItem(rawLayout, i, formType)` — returns `(FieldSchema?, consumed)` |
| **Field build** | `form_schema_parser.dart` | 309–327 | `_buildField()` constructs `FieldSchema`; `snomedCode`/`snomedDisplay` land only in `raw` (line 325) |

The key Dart class is `FieldSchema` (`lib/uhis_form/models/field_schema.dart`):

```dart
class FieldSchema {
  final String fieldId;
  final String label;
  final FieldKind kind;
  final bool required;
  final String? unit;
  final double? min;
  final double? max;
  final String? hint;
  final List<FieldOption> options;
  final List<ConditionSchema> conditions;
  final List<String> subFieldIds;   // for composites
  final Map<String, dynamic> raw;   // full original JSON item — the only place snomedCode lives at runtime
}
```

There is no explicit `fromJson` factory on `FieldSchema`; construction happens inside `FormSchemaParser._buildField()` at `form_schema_parser.dart:309`.

---

## 3. Programme association today

**At form level** (`assets/forms/program_forms.json`):
- Each form entry carries a `formType` string (e.g. `"anc"`) plus `workflowName` and `clinicalWorkflowId`.
- This scopes the entire `formInput` payload to a single programme.

**At field level** (`leapfrog-setup/program_forms_questions.json`):
- Each field carries a `programs` array of strings (e.g. `["pncMother", "anc"]`).
- This allows the same field definition to be declared shared, but the SDK **never reads this file**.

**Consequence:** the two files are disconnected. The `programs[]` array on a field definition is authoring intent only — it is not enforced, queryable, or validated at runtime. If a field appears in two programmes' `formInput` layouts, it is physically duplicated there.

---

## 4. Clinical coding today

| Coding standard | Where it appears | Key names | Status |
|---|---|---|---|
| SNOMED-CT | `program_forms_questions.json` fields and options | `snomedCode`, `snomedDisplay` | Present on 172 of 213 fields (81%); loose strings |
| LOINC | `lib/core/models/fhir_observation.dart` — `LoincVitalCodes` class | hardcoded constants | Hardcoded in Dart, disconnected from form JSON |
| ICD-10 / ICD-11 | Not found in form configs | — | Absent |
| FHIR concept | Not found | — | Absent |

`snomedCode`/`snomedDisplay` are present in the **questions file** but flow only into `FieldSchema.raw` when the SDK parses. No code in `FormSchemaParser` or `FieldSchema` reads or surfaces them as typed fields (`form_schema_parser.dart:325` stores the full JSON item into `raw`).

LOINC codes for vitals live in `lib/core/models/fhir_observation.dart` in a class named `LoincVitalCodes`, fully disconnected from the form field definitions.

---

## 5. Downstream consumption points

| Consumption point | File | Line | Notes |
|---|---|---|---|
| JSON load & unwrap | `form_data_service.dart` | 60–68 | Entry point for all form schema loading |
| Parser double-decode | `form_schema_parser.dart` | 31 | `jsonDecode` on the stringified `formInput` |
| `viewType` → `FieldKind` dispatch | `form_schema_parser.dart` | 101–141 | Exhaustive switch; unknown types fall through to `textInput` |
| Composite look-ahead (vitals/anthropometry/supply/obstetric) | `form_schema_parser.dart` | 154–195 | ID-based heuristics; see §6 |
| `isMandatory`, `unit`, `min`, `max`, `hint` parse | `form_schema_parser.dart` | 318–326 | Direct key access from JSON map |
| Option list parse | `form_schema_parser.dart` | 348–360 | `optionsList` or `options` key |
| Condition parse | `form_schema_parser.dart` | 362–371 | `condition[]` array |
| Widget dispatch | `lib/uhis_form/widgets/field_renderer.dart` | 58 | Exhaustive `switch` on `FieldKind` |
| Visibility evaluation | `lib/uhis_form/controller/condition_evaluator.dart` | 20 | Reads `FormSchema` output; unaffected by source JSON shape |
| Draft persistence | `lib/uhis_form/controller/dynamic_form_controller.dart` | 140, 172–191 | Flattens composite field values into `AssessmentDraftRow.fieldValues` map |
| FHIR extraction | `lib/core/models/fhir_observation.dart` | `LoincVitalCodes` | Hardcoded; does NOT read form field metadata |

---

## 6. Concrete pain points

1. **`snomedCode` never reaches `FieldSchema`** — The clinical code exists in `program_forms_questions.json` but the SDK reads `program_forms.json`; even there the code only lands in the opaque `raw` map (`field_schema.dart:79`). FHIR extraction cannot access it without parsing `raw` by magic string key.

2. **LOINC codes hardcoded in Dart** — `fhir_observation.dart`'s `LoincVitalCodes` class is completely separate from field metadata. If a field's SNOMED code changes, the LOINC mapping is unaffected. There is no single record of "field X maps to these clinical codes."

3. **Double-stringified `formInput`** — `program_forms.json` embeds each form's field list as a JSON string inside a JSON object (`form_data_service.dart:39`, `form_schema_parser.dart:31`). This requires two `jsonDecode` calls, prevents linting or schema validation of the inner JSON, and makes manual editing error-prone.

4. **Fragile composite detection by field ID strings** — `form_schema_parser.dart:145–195` hard-codes sets of field IDs (`_vitalFieldIds`, `_heightFieldIds`, `_weightFieldIds`) and suffix strings (`_supplyConsumedSuffixes`). Renaming any field ID silently breaks composite grouping. The title-based danger-signs heuristic at line 253–259 is equally fragile.

5. **Field duplication across programmes** — `temperature` appears in both the `pncMother` and `anc` `formLayout` arrays as a full copy of its JSON definition. Any change (e.g. adding a SNOMED code, adjusting `minValue`) must be applied to every copy.

6. **`programs[]` not queryable at runtime** — The multi-programme scoping in `program_forms_questions.json` is authoring metadata only. The SDK cannot ask "which programmes does this field appear in?" at runtime because it never loads that file.

7. **Inconsistent SNOMED coverage within fields** — Some `optionsList` entries carry `null` codes (e.g. `breastPainSwellingFever` in `postpartumDangerSigns`). There is no schema enforcement or CI check to flag missing codes.
