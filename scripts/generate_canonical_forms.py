#!/usr/bin/env python3
"""
Generate assets/forms/field_library.json and assets/forms/layout_manifests.json
from the two legacy source files:

  - leapfrog-setup/program_forms_questions.json  (field definitions, 213 items)
  - assets/forms/program_forms.json              (layouts, 13 formTypes)

Run from the uhis_lf_mobile root:
  python3 scripts/generate_canonical_forms.py
"""

import json
import os
import sys

QUESTIONS_PATH = os.path.join(
    os.path.dirname(__file__),
    "../../program_forms_questions.json",
)
LAYOUTS_PATH = os.path.join(
    os.path.dirname(__file__), "../assets/forms/program_forms.json"
)
OUT_LIBRARY = os.path.join(
    os.path.dirname(__file__), "../assets/forms/field_library.json"
)
OUT_MANIFESTS = os.path.join(
    os.path.dirname(__file__), "../assets/forms/layout_manifests.json"
)

# Android InputType bitmask → canonical string name
INPUT_TYPE_MAP = {
    2: "integer",
    3: "integer",
    8192: "decimal",
}

# LOINC codes for clinical fields.
# Maps field id → (loinc_code, loinc_display)
LOINC_CODES = {
    "temperature":         ("8310-5",  "Body temperature"),
    "pulse":               ("8867-4",  "Heart rate"),
    "breathsPerMinute":    ("9279-1",  "Respiratory rate"),
    "respiratoryRate":     ("9279-1",  "Respiratory rate"),
    "spo2":                ("59408-5", "Oxygen saturation in Arterial blood by Pulse oximetry"),
    "SpO2":                ("59408-5", "Oxygen saturation in Arterial blood by Pulse oximetry"),
    "systolic":            ("8480-6",  "Systolic blood pressure"),
    "diastolic":           ("8462-4",  "Diastolic blood pressure"),
    "bloodPressure":       ("8480-6",  "Systolic blood pressure"),
    "height":              ("8302-2",  "Body height"),
    "heightInFeet":        ("8302-2",  "Body height"),
    "patientHeight":       ("8302-2",  "Body height"),
    "weight":              ("29463-7", "Body weight"),
    "patientWeight":       ("29463-7", "Body weight"),
    "ancWeight":           ("29463-7", "Body weight"),
    "bmi":                 ("39156-5", "Body mass index (BMI) [Ratio]"),
    "bloodSugar":          ("2339-0",  "Glucose [Mass/volume] in Blood"),
    "bloodSugarFasting":   ("2339-0",  "Glucose [Mass/volume] in Blood"),
    "bloodSugarRandom":    ("2339-0",  "Glucose [Mass/volume] in Blood"),
    "muac":                ("56072-2", "Mid upper arm circumference"),
}

# compositeGroup assignment per field id.
# compositeRole "trigger" = first field in composite, "member" = rest.
COMPOSITE_GROUP = {
    "temperature":      ("vitalsBundle",      "trigger"),
    "pulse":            ("vitalsBundle",      "member"),
    "breathsPerMinute": ("vitalsBundle",      "member"),
    "respiratoryRate":  ("vitalsBundle",      "member"),
    "spo2":             ("vitalsBundle",      "member"),
    "SpO2":             ("vitalsBundle",      "member"),
    "height":           ("anthropometry",     "trigger"),
    "heightInFeet":     ("anthropometry",     "trigger"),
    "patientHeight":    ("anthropometry",     "trigger"),
    "weight":           ("anthropometry",     "member"),
    "patientWeight":    ("anthropometry",     "member"),
    "ancWeight":        ("anthropometry",     "member"),
    "gravida":          ("obstetricHistory",  "trigger"),
    "parity":           ("obstetricHistory",  "member"),
    "livingChildren":   ("obstetricHistory",  "member"),
    "ageOfLastChild":   ("obstetricHistory",  "member"),
}

# Supply pair suffixes: consumed-side is trigger, provided-side is member.
_SUPPLY_CONSUMED_SUFFIXES = ["Consumed", "consumed", "LastMonth"]
_SUPPLY_PROVIDED_SUFFIXES = ["Provided", "provided", "Today"]


def _supply_composite_role(field_id):
    """Return (compositeGroup, compositeRole) for supply pair fields, or None.

    For consumed-side fields the group is fieldId + "_pair".
    For provided-side fields the group is derived by stripping the provided
    suffix and appending "_pair" so it matches its consumed partner.
    """
    for suffix in _SUPPLY_CONSUMED_SUFFIXES:
        if suffix in field_id:
            return (f"{field_id}_pair", "trigger")
    for suffix in _SUPPLY_PROVIDED_SUFFIXES:
        if suffix in field_id:
            # Build group name mirroring the consumed partner.
            consumed_id = field_id.replace(suffix, "Consumed")
            # Normalise: strip trailing "Consumed" and re-add
            group = f"{consumed_id}_pair"
            return (group, "member")
    return None


def _canonical_input_type(raw):
    """Convert Android InputType bitmask to canonical name."""
    if raw is None:
        return None
    try:
        iv = int(raw)
    except (ValueError, TypeError):
        return "text"
    return INPUT_TYPE_MAP.get(iv, "text")


def _snomed_to_clinical_concept(code, display):
    if code is None:
        return None
    return [{"system": "SNOMED_CT", "code": str(code), "display": display or ""}]


def _transform_options(options_list):
    """Convert optionsList items: flatten snomedCode/snomedDisplay to clinicalConcept."""
    if not options_list:
        return options_list
    out = []
    for opt in options_list:
        o = dict(opt)
        snomed_code = o.pop("snomedCode", None)
        snomed_display = o.pop("snomedDisplay", None)
        if snomed_code is not None:
            o["clinicalConcept"] = _snomed_to_clinical_concept(snomed_code, snomed_display)
        out.append(o)
    return out


def build_field_library(questions, workflow_map):
    """
    Convert program_forms_questions.json items to canonical FieldDefinition objects.
    Returns a dict keyed by field id.
    """
    library = {}
    for item in questions:
        field_id = item.get("id")
        if not field_id:
            print(f"WARNING: field without id, skipping: {item.get('title','?')}", file=sys.stderr)
            continue

        canonical = {}

        # Required canonical keys
        canonical["id"] = field_id
        canonical["label"] = item.get("title", "")
        canonical["widgetHint"] = item.get("viewType", "EditText")

        # fieldName — preserve as pass-through so parser's _fieldId() logic works
        if "fieldName" in item and item["fieldName"] != field_id:
            canonical["fieldName"] = item["fieldName"]

        # Optional scalar fields — pass through directly
        for key in (
            "family", "familyOrder", "orderId", "isMandatory", "isEnabled",
            "readOnly", "visibility", "hint", "hintCulture", "titleCulture",
            "errorMessage", "errorMessageCulture", "unitMeasurement",
            "minValue", "maxValue", "isSummary", "titleSummary",
            "localDataCache", "isBooleanAnswer", "optionType",
            "isInfo", "infoTitle", "isNeededDefault", "isNotDefault",
            "applyDecimalFilter",
        ):
            if key in item and item[key] is not None:
                canonical[key] = item[key]

        # inputType: bitmask → name string
        if "inputType" in item:
            canonical["inputType"] = _canonical_input_type(item["inputType"])

        # clinicalConcept: lift snomedCode/snomedDisplay to structured array,
        # then append LOINC entry if this field has a known LOINC code.
        snomed_code = item.get("snomedCode")
        snomed_display = item.get("snomedDisplay")
        cc = _snomed_to_clinical_concept(snomed_code, snomed_display) or []
        loinc_entry = LOINC_CODES.get(field_id)
        if loinc_entry:
            cc.append({
                "system": "LOINC",
                "code": loinc_entry[0],
                "display": loinc_entry[1],
            })
        if cc:
            canonical["clinicalConcept"] = cc

        # compositeGroup / compositeRole: static hint based on field id
        if field_id in COMPOSITE_GROUP:
            group, role = COMPOSITE_GROUP[field_id]
            canonical["compositeGroup"] = group
            canonical["compositeRole"] = role
        else:
            supply_pair = _supply_composite_role(field_id)
            if supply_pair is not None:
                group, role = supply_pair
                if group is not None:
                    canonical["compositeGroup"] = group
                canonical["compositeRole"] = role

        # programmes: string[] → typed object[] using workflow_map for metadata
        raw_progs = item.get("programs") or []
        if raw_progs:
            prog_objects = []
            for pid in raw_progs:
                meta = workflow_map.get(pid, {})
                prog_obj = {"id": pid}
                if meta.get("workflowId") is not None:
                    prog_obj["workflowId"] = meta["workflowId"]
                if meta.get("workflowName"):
                    prog_obj["workflowName"] = meta["workflowName"]
                prog_objects.append(prog_obj)
            canonical["programmes"] = prog_objects
        else:
            canonical["programmes"] = []

        # optionsList: flatten snomedCode/snomedDisplay per option
        options_list = item.get("optionsList") or item.get("options")
        if options_list:
            canonical["optionsList"] = _transform_options(options_list)

        # condition: pass through unchanged
        if "condition" in item:
            canonical["condition"] = item["condition"]

        library[field_id] = canonical

    return library


def build_layout_manifests(forms):
    """
    Convert program_forms.json formData entries to layout manifests.
    Returns (manifests_list, workflow_map).
    workflow_map: programme_id → {workflowId, workflowName}
    """
    manifests = []
    workflow_map = {}

    for form_entry in forms:
        form_type = form_entry.get("formType", "")
        workflow_name = form_entry.get("workflowName")
        workflow_id = form_entry.get("clinicalWorkflowId")

        # Record in workflow_map for field-level programme enrichment
        workflow_map[form_type] = {
            "workflowId": workflow_id,
            "workflowName": workflow_name,
        }

        form_input_str = form_entry.get("formInput", "{}")
        inner = json.loads(form_input_str)
        layout = inner.get("formLayout", [])

        sections = []
        current_section = None

        for item in layout:
            view_type = item.get("viewType", "")
            if view_type == "CardView":
                if current_section is not None:
                    sections.append(current_section)
                current_section = {
                    "sectionId": item.get("id", ""),
                    "title": item.get("title", ""),
                    "fieldRefs": [],
                }
            else:
                if current_section is None:
                    # Fields before first CardView — use form type as implicit section
                    current_section = {
                        "sectionId": form_type,
                        "title": form_type,
                        "fieldRefs": [],
                    }
                field_id = item.get("id", "")
                if field_id:
                    field_name = item.get("fieldName")
                    overrides = {}
                    if field_name and field_name != field_id:
                        overrides["fieldName"] = field_name
                    # Capture per-layout metadata that may diverge from questions file
                    if "inputType" in item:
                        overrides["inputType"] = item["inputType"]
                    if "isMandatory" in item:
                        overrides["isMandatory"] = item["isMandatory"]
                    if overrides:
                        overrides["id"] = field_id
                        current_section["fieldRefs"].append(overrides)
                    else:
                        current_section["fieldRefs"].append(field_id)

        if current_section is not None:
            sections.append(current_section)

        manifest = {
            "formType": form_type,
        }
        if workflow_name is not None:
            manifest["workflowName"] = workflow_name
        if workflow_id is not None:
            manifest["clinicalWorkflowId"] = workflow_id
        manifest["sections"] = sections

        manifests.append(manifest)

    return manifests, workflow_map


def main():
    with open(QUESTIONS_PATH, encoding="utf-8") as f:
        questions = json.load(f)

    with open(LAYOUTS_PATH, encoding="utf-8") as f:
        raw = json.load(f)
    entity = raw.get("entity", raw)
    forms = entity.get("formData", [])

    # First pass: build layout manifests and extract workflow metadata
    manifests, workflow_map = build_layout_manifests(forms)

    # Second pass: build field library with workflow metadata
    library = build_field_library(questions, workflow_map)

    # Write outputs
    with open(OUT_LIBRARY, "w", encoding="utf-8") as f:
        json.dump(library, f, indent=2, ensure_ascii=False)
    print(f"Wrote {len(library)} field definitions to {OUT_LIBRARY}")

    with open(OUT_MANIFESTS, "w", encoding="utf-8") as f:
        json.dump(manifests, f, indent=2, ensure_ascii=False)
    total_fields = sum(
        len(sec["fieldRefs"]) for m in manifests for sec in m["sections"]
    )
    print(f"Wrote {len(manifests)} manifests ({total_fields} total fieldRefs) to {OUT_MANIFESTS}")


if __name__ == "__main__":
    main()
