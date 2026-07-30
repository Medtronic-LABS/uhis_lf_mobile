# Form SDK — Canonical Field Format

## Design principles

1. **Single source of truth.** `program_forms_questions.json` becomes the **field library** — one definition per field ID, shared across all programmes. No field definition is duplicated.

2. **Layout manifests reference, not repeat.** `program_forms.json` becomes a **layout manifest** — it names sections and lists ordered field IDs, but carries no field metadata. Metadata lives in the library.

3. **First-class clinical concept.** SNOMED, LOINC, ICD-10, and RxNorm codes are expressed as a structured `clinicalConcept` array, not loose parallel strings. A field can carry both its SNOMED and LOINC codes in one place.

4. **Typed programme references.** Programme scoping is expressed as an array of objects `{ id, workflowId, workflowName }`, not a flat string array.

5. **Explicit composite hints.** `compositeGroup` and `compositeRole` replace the fragile ID-based heuristics in the parser.

6. **No stringification.** Layout manifests are real JSON objects; no `formInput` string wrapping.

7. **Backwards-compatible naming.** Where a key exists today and is consumed by the SDK (`viewType`, `isMandatory`, `condition`, `optionsList`, etc.), names are preserved so the transformer has minimal work.

---

## JSON Schema — canonical field definition

```json
{
  "$schema": "https://json-schema.org/draft/2020-12",
  "$id": "uhis-lf-mobile/field-definition/v1",
  "title": "CanonicalFieldDefinition",
  "type": "object",
  "required": ["id", "label", "widgetHint", "programmes"],
  "additionalProperties": true,
  "properties": {

    "id": {
      "type": "string",
      "description": "Stable field identifier. Used as the key in AssessmentDraftRow.fieldValues. Must match `id` or `fieldName` in the legacy layout."
    },

    "label": {
      "type": "string",
      "description": "English display label shown above the widget. Corresponds to legacy `title`."
    },

    "widgetHint": {
      "type": "string",
      "description": "Rendering hint consumed by FormSchemaParser. Same values as legacy `viewType` — name normalised, values preserved for transformer compatibility.",
      "enum": [
        "CardView", "EditText", "SingleSelectionView", "Spinner",
        "DialogCheckbox", "MultiSelectSpinner", "RadioGroup", "DatePicker",
        "BP", "AgeOrDob", "AgeYMD", "CheckBox", "TextLabel",
        "InformationLabel", "Instruction", "QRView"
      ]
    },

    "programmes": {
      "type": "array",
      "description": "Programmes this field belongs to. Replaces the flat `programs` string array.",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["id"],
        "properties": {
          "id":           { "type": "string", "description": "Programme identifier, e.g. 'anc', 'pncMother'" },
          "workflowId":   { "type": ["integer", "null"], "description": "clinicalWorkflowId from the API" },
          "workflowName": { "type": ["string", "null"],  "description": "Human-readable workflow name, e.g. 'RMNCH'" }
        }
      }
    },

    "clinicalConcept": {
      "type": "array",
      "description": "Ordered list of clinical concept bindings. First SNOMED entry is used for legacy snomedCode/snomedDisplay by the transformer. A field may carry both SNOMED and LOINC codes.",
      "items": {
        "type": "object",
        "required": ["system", "code", "display"],
        "properties": {
          "system":  { "type": "string", "enum": ["SNOMED_CT", "LOINC", "ICD10", "ICD11", "RxNorm"] },
          "code":    { "type": "string" },
          "display": { "type": "string" }
        }
      }
    },

    "family": {
      "type": "string",
      "description": "Section / group name within a form. Unchanged from legacy."
    },
    "familyOrder": { "type": "integer" },
    "orderId":     { "type": "integer", "description": "Field ordering within its section." },

    "isMandatory": { "type": "boolean" },
    "isEnabled":   { "type": "boolean" },
    "readOnly":    { "type": "boolean" },
    "visibility":  { "type": "string", "enum": ["visible", "gone", "invisible"] },

    "hint":         { "type": "string" },
    "hintCulture":  { "type": "string" },
    "titleCulture": { "type": "string" },
    "errorMessage": { "type": "string" },
    "errorMessageCulture": { "type": "string" },

    "inputType":        { "type": "string", "enum": ["text", "integer", "decimal"], "description": "Logical input type for EditText fields. Transformer maps to Android InputType bitmask: text→96, integer→2, decimal→8192." },
    "unitMeasurement":  { "type": "string" },
    "minValue":         { "type": "number" },
    "maxValue":         { "type": "number" },

    "optionsList": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "name"],
        "properties": {
          "id":             {},
          "name":           { "type": "string" },
          "value":          { "type": "string" },
          "displayOrder":   { "type": "integer" },
          "cultureValue":   { "type": "string" },
          "type":           { "type": "string" },
          "clinicalConcept": {
            "type": "array",
            "description": "Clinical concept binding for this option. Transformer flattens to snomedCode/snomedDisplay.",
            "items": {
              "type": "object",
              "required": ["system", "code", "display"],
              "properties": {
                "system":  { "type": "string", "enum": ["SNOMED_CT", "LOINC", "ICD10", "ICD11", "RxNorm"] },
                "code":    { "type": "string" },
                "display": { "type": "string" }
              }
            }
          }
        }
      }
    },

    "condition": {
      "type": "array",
      "description": "Visibility conditions. Structure unchanged from legacy — consumed directly by ConditionSchema.fromJson.",
      "items": { "type": "object" }
    },

    "compositeGroup": {
      "type": ["string", "null"],
      "description": "Names the composite widget this field belongs to (e.g. 'vitalsBundle', 'anthropometry'). Replaces the ID-string heuristics in FormSchemaParser once the parser is updated (deferred)."
    },
    "compositeRole": {
      "type": ["string", "null"],
      "enum": ["trigger", "member", null],
      "description": "'trigger' = first field the parser detects; 'member' = folded into the composite. Only meaningful when compositeGroup is set."
    },

    "isSummary":       { "type": "boolean" },
    "titleSummary":    { "type": "string" },
    "localDataCache":  { "type": "string" },
    "isBooleanAnswer": { "type": "boolean" },
    "optionType":      { "type": "string" },
    "isInfo":          { "type": "string" },
    "infoTitle":       { "type": "string" }
  }
}
```

---

## JSON Schema — layout manifest

```json
{
  "$schema": "https://json-schema.org/draft/2020-12",
  "$id": "uhis-lf-mobile/layout-manifest/v1",
  "title": "LayoutManifest",
  "type": "object",
  "required": ["formType", "sections"],
  "properties": {
    "formType":           { "type": "string", "description": "Matches the legacy formType key, e.g. 'anc'." },
    "workflowName":       { "type": ["string", "null"] },
    "clinicalWorkflowId": { "type": ["integer", "null"] },
    "sections": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["sectionId", "title", "fieldRefs"],
        "properties": {
          "sectionId":  { "type": "string" },
          "title":      { "type": "string" },
          "fieldRefs":  {
            "type": "array",
            "items": { "type": "string" },
            "description": "Ordered list of field IDs from the field library."
          }
        }
      }
    }
  }
}
```

---

## Worked examples

### Example A — Shared vital (pncMother + anc): temperature

This field appears in two programmes today as a full copy in each `formLayout`. In the canonical format it is defined once in the field library; both layout manifests reference it by ID.

```json
{
  "id": "temperature",
  "label": "Temperature",
  "widgetHint": "EditText",
  "inputType": "decimal",
  "isMandatory": true,
  "isEnabled": true,
  "unitMeasurement": "°F",
  "minValue": 0,
  "hint": "[Enter number]",
  "hintCulture": "[সংখ্যা লিখুন]",
  "titleCulture": "তাপমাত্রা (ফারেনহাইট)",
  "infoTitle": "0 – If temperature could not be measured",
  "isInfo": "visible",
  "visibility": "visible",
  "family": "maternalHealthAssessment",
  "orderId": 0,
  "clinicalConcept": [
    { "system": "SNOMED_CT", "code": "386725007", "display": "Body temperature" },
    { "system": "LOINC",     "code": "8310-5",    "display": "Body temperature" }
  ],
  "programmes": [
    { "id": "pncMother", "workflowId": 5, "workflowName": "RMNCH" },
    { "id": "anc",       "workflowId": 1, "workflowName": "RMNCH" }
  ],
  "compositeGroup": "vitalsBundle",
  "compositeRole": "trigger"
}
```

Key improvements over legacy:
- `clinicalConcept` carries both SNOMED and LOINC in one field; LOINC no longer needs to be hardcoded separately in `fhir_observation.dart`
- `compositeGroup`/`compositeRole` replaces the `_vitalFieldIds` heuristic at `form_schema_parser.dart:145`
- `programmes` is a typed object array, not a string array

---

### Example B — Programme-specific clinical field (ANC): postpartum danger signs

```json
{
  "id": "postpartumDangerSigns",
  "label": "Danger Signs present",
  "titleCulture": "প্রসবের পরে কোনো জটিলতা আছে কি?",
  "widgetHint": "DialogCheckbox",
  "hint": "Danger signs",
  "hintCulture": "বিপদ চিহ্ন",
  "isMandatory": true,
  "isEnabled": true,
  "visibility": "visible",
  "family": "maternalHealthAssessment",
  "orderId": 19,
  "clinicalConcept": [
    { "system": "SNOMED_CT", "code": "267024001", "display": "Postpartum danger signs" }
  ],
  "programmes": [
    { "id": "pncMother", "workflowId": 5, "workflowName": "RMNCH" }
  ],
  "optionsList": [
    {
      "id": 1, "name": "Heavy bleeding", "value": "heavyBleeding", "displayOrder": 1,
      "clinicalConcept": [{ "system": "SNOMED_CT", "code": "131148009", "display": "Heavy bleeding" }]
    },
    {
      "id": 2, "name": "Foul-smelling discharge", "value": "foulSmellingDischarge", "displayOrder": 2,
      "clinicalConcept": [{ "system": "SNOMED_CT", "code": "271939006", "display": "Foul-smelling discharge" }]
    },
    {
      "id": 3, "name": "Severe abdominal pain", "value": "severeAbdominalPain", "displayOrder": 3,
      "clinicalConcept": [{ "system": "SNOMED_CT", "code": "55300003", "display": "Abdominal pain" }]
    },
    {
      "id": 6, "name": "Breast pain/swelling with fever", "value": "breastPainSwellingFever", "displayOrder": 6
    },
    {
      "id": 7, "name": "None", "value": "none", "displayOrder": 7,
      "clinicalConcept": [{ "system": "SNOMED_CT", "code": "260413007", "display": "None" }]
    },
    {
      "id": 8, "name": "Other", "value": "other", "displayOrder": 8,
      "clinicalConcept": [{ "system": "SNOMED_CT", "code": "74964007", "display": "Other" }]
    }
  ]
}
```

Note: option 6 (`breastPainSwellingFever`) intentionally has no `clinicalConcept` — a known gap, visible in the canonical format and catchable by a CI completeness check.

---

### Example C — Non-clinical admin field (household registration): household number

```json
{
  "id": "householdNumber",
  "label": "Household Number",
  "widgetHint": "EditText",
  "inputType": "text",
  "isMandatory": true,
  "isEnabled": true,
  "visibility": "visible",
  "family": "householdDetails",
  "orderId": 0,
  "programmes": [
    { "id": "household_registration", "workflowId": null, "workflowName": null }
  ]
}
```

No `clinicalConcept` — correct and expected for an administrative field. The absence is intentional, not a gap.

---

## Layout manifest example (replaces `formInput` string)

```json
{
  "formType": "anc",
  "workflowName": "RMNCH",
  "clinicalWorkflowId": 1,
  "sections": [
    {
      "sectionId": "maternalHealthAssessment",
      "title": "Maternal Health Assessment",
      "fieldRefs": [
        "temperature",
        "pulse",
        "breathsPerMinute",
        "spo2",
        "systolicBP",
        "weight",
        "height",
        "muac"
      ]
    },
    {
      "sectionId": "ancClinical",
      "title": "ANC Clinical",
      "fieldRefs": [
        "gestationalAge",
        "gravida",
        "parity",
        "livingChildren",
        "postpartumDangerSigns"
      ]
    }
  ]
}
```

The transformer joins the field library + this manifest to produce the `formLayout` array that `FormSchemaParser.parse()` currently reads.
