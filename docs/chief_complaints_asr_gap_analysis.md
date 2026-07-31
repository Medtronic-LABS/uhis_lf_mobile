# Live-ASR `chiefComplaints` → Step 1 Chip Matching — Gap Analysis

## Context

The live-ASR path (ai-scribe-service's general clinical extraction, `run_inference`/`_parse_clinical` in `leapfrog-ai-service/app/services/inference.py`) returns a free-text `chiefComplaints` array. Flutter's `ChiefComplaintMatcher` (`lib/features/realtime_asr/chief_complaint_matcher.dart`) keyword-matches each phrase against a fixed 33-code vocab to auto-select Step 1 triage chips. This doc records where that pipeline drops or mis-maps symptoms, verified against the actual code (not assumed) and against a live sample response.

Two things were checked directly, not guessed:
- `symptoms/symptoms.txt` (ai-service canonical list) vs. `ChiefComplaintMatcher._keywordsByCode`'s key set — confirmed **identical**, 33 codes each way, no vocab drift between the two repos.
- The matcher's actual substring-match algorithm, run programmatically against a sample response (below) — not eyeballed.

---

## Step 1 ASR symptom vocab (33 codes, shared by both repos)

| Category | Codes |
|---|---|
| **General** (12) | fever, abdominal_pain, headache, blurred_vision, convulsions, vomiting, painful_urination, breathlessness, dizziness, fatigue, weakness, weight_loss |
| **Maternal** (11) | heavy_bleeding, vaginal_bleeding, foul_smelling_vaginal_discharge, swelling_face_hands, edema, breast_pain, breast_swelling, perineal_wound_discharge, leaking_fluid_vagina, painful_uterine_contractions, reduced_fetal_movement |
| **NCD** (10) | epigastric_pain, chest_pain, one_sided_weakness, swelling_both_feet, palpitations, swelling_one_leg, excessive_thirst, foot_numbness, foot_pain, foot_wound |

Note: this is a strict subset of the app's full triage vocab (`ai_scribe_triage_vocab.dart`) — pediatric/IMCI codes (`cough`, `fast_breathing`, `diarrhea`, etc.) are handled by a separate manual triage flow and are not part of this general-extraction canonical list at all.

---

## 🔴 Critical — bare-word LLM drift causes silent chip drops

**Root cause:** `ChiefComplaintMatcher.match()` (`chief_complaint_matcher.dart:81-93`) checks `normalized.contains(keyword)` — the *complaint string* must contain the *full keyword phrase* as a substring. Every keyword phrase for the affected codes is 2+ words. When the LLM emits a bare one-word complaint instead of the full canonical phrase, the containment check fails for every candidate code, and the symptom is silently dropped — no chip, no error, nothing surfaced to the SK.

Verified live against this sample `chiefComplaints` response:

```json
["vaginal bleeding","abdominal pain","leaking fluid","headache","swelling",
 "convulsions","fever","baby not moving","dizziness","high bp","blurred vision",
 "chest pain","one sided weakness","palpitations","shortness of breath","diabetes",
 "excessive thirst","foot numbness","wound","weakness","weight loss"]
```

| Phrase | Matched code(s) | Status |
|---|---|---|
| "swelling" | *(none)* | ❌ no match — 4 canonical swelling codes all need a longer phrase (`swelling_face_hands`, `swelling_both_feet`, `swelling_one_leg`, `breast_swelling`) |
| "wound" | *(none)* | ❌ no match — `foot_wound`/`perineal_wound_discharge` both need a longer phrase |
| "high bp" | *(none)* | ❌ no match — **no code exists for BP as a symptom in this vocab at all** (see next section) |
| all other 18 phrases | matched correctly | ✅ |

**3 of 21 phrases (14%) silently dropped in this single sample.** "swelling" and "wound" are the two highest-risk drops: both are substrings of *multiple* canonical phrases spanning different clinical programmes (ANC pre-eclampsia vs. NCD peripheral vs. PNC postpartum), so even a keyword-list fix needs to pick the right target deliberately, not guess one.

**Fix (Python side):** normalize bare-word drift to the full canonical phrase in `_parse_clinical()` before the payload leaves the ai-service — this was drafted in a companion plan (see "Related work" below) but that plan currently has a blocking implementation bug (`set()` on a joined string instead of the parsed list) that makes the fix a no-op as written; it needs correcting before landing.

---

## 🔴 Critical — "high bp" has no representable code anywhere in this pipeline

Unlike the swelling/wound cases, this isn't a phrasing problem — there is no code path that can ever produce a BP chip from live-ASR `chiefComplaints`, regardless of what phrase the LLM emits:

- `symptoms/symptoms.txt` (the ai-service's canonical extraction vocab): **no BP-related entry**, confirmed by dumping the full 33-item file.
- `ChiefComplaintMatcher._keywordsByCode`: **no BP-related key at all**, confirmed by diffing its key set against `symptoms.txt` (identical sets — nothing extra on either side).
- `high_bp_known` **does** exist, but only in the Flutter app's separate, broader triage vocab (`ai_scribe_triage_vocab.dart`, `unified_symptom_catalog.dart`) used for manual chip selection and pathway routing (`pathway_rules_v1.dart`) — a different vocabulary from the one live-ASR extraction feeds into.

**Fix would require both sides**, not Python alone: add `high_bp_known` (or equivalent) to `symptoms/symptoms.txt` so the LLM has a target to extract into, AND add a corresponding keyword entry to `ChiefComplaintMatcher._keywordsByCode` in Flutter — a companion Python-only plan cannot close this gap by itself.

---

## 🟡 Mis-extraction — `chiefComplaints` contains a non-symptom

**"diabetes"** appears in the sample response's `chiefComplaints` array, duplicating `comorbidities: ["hypertension", "diabetes"]`. The system prompt (`inference.py` `INFERENCE_PROMPT`) is explicit that `chiefComplaints` are patient-reported *symptoms*, and diabetes is a comorbidity, not a symptom — it's correctly placed in `comorbidities` too, so this is a straight duplication/category violation by the LLM, not a phrasing issue. The matcher correctly finds no code for it (expected — there's no "diabetes" symptom chip), but the underlying extraction violates the prompt's own field-separation contract.

---

## 🟡 Format violations outside `chiefComplaints` (same root cause class)

Found while reviewing the same sample response — flagged since they're the same "the LLM isn't following its own closed-vocabulary contract" pattern:

- `"comorbidities": ["hypertension", "diabetes"]` — prompt's fixed enum requires title-case full names (`"Hypertension"`, `"Diabetes Mellitus"`), not lowercase abbreviations. As emitted, these likely fail to match whatever downstream comorbidity picklist expects exact enum strings.
- `"complications": ["elevated_bp", "blurred_vision"]` — both violate the prompt's closed list (`Diabetic Retinopathy, ..., Foot Ulcers / Diabetic Foot, ..., Other: <text>`). `elevated_bp` is a raw snake_case token, not a value the prompt ever specifies (should be natural language or `"Other: <text>"`); `blurred_vision` shouldn't be a *complication* at all — the prompt explicitly says acute patient-reported symptoms belong in `chiefComplaints` (where it also, correctly, appears).

---

## Related work

A companion plan (`app/services/inference.py`, Python-only) was drafted to fix the swelling/wound/high-bp drift via a hardcoded alias dict inside `_parse_clinical()`. Review of that plan found:
1. A blocking bug — `set(_canonical_symptoms())` sets over individual characters (the function returns a joined string, not a list), making every membership check false and the fix a no-op as written.
2. The "high bp" row is based on a false premise (`high_bp_known` is not in `symptoms.txt` — see above) and can't work as a Python-only change.
3. The proposed "swelling"→"swelling face hands" and "wound"→"foot wound" aliases pick one specific canonical target unconditionally, despite both bare words being genuine substrings of multiple clinically-distinct canonical phrases across different programmes — risking a wrong clinical signal (e.g. a PNC patient's perineal wound or leg swelling recorded as a diabetic-foot or pre-eclampsia finding) rather than the safer `"Other: <text>"` fallback the same plan correctly applies to ambiguous terms like "diabetes".

None of the above has been implemented — this document and the plan review are analysis only.
