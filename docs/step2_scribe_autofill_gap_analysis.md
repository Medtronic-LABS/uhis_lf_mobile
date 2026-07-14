# Step 2 AI Scribe Auto-Fill — Gap Analysis

## Context

Step 2 (the vitals + full clinical form, `unified_form_screen.dart`) is supposed to auto-fill form fields from a live-recorded consultation via `AiScribeBanner` → `applyAiPrefill()`. Investigated why fields reportedly aren't auto-filling, tracing both the Flutter client (`uhis_lf_mobile`) and the ai-service backend (`leapfrog-ai-service`) end to end, then spot-verifying the most load-bearing findings directly (not just trusting the trace): ran the failing test, diffed the AI-requested field IDs against the real form layouts, and read the exact WebSocket message-type logic on both sides of the wire.

**Headline finding: Step 2 auto-fill is currently running on a fragile regex-based fallback parser instead of the validated, schema-aware extraction pipeline that already exists — by the client's own admission, in code, as a deliberate temporary bridge.** Everything else below compounds on top of that.

---

## 🔴 Critical — the live pipeline uses the weak fallback, not the real extraction

**1. The realtime WebSocket protocol supports a proper `form_fill` response, but the client's own code says the backend doesn't send it yet.**

Verified directly on the server (`leapfrog-ai-service/app/services/realtime_bridge.py`, `run_extraction()`): when `assessmentType` is set on the WS connection, the server DOES run the real schema-aware extraction (`assessment_extraction.run_assessment_extraction`) and DOES send `{"type": "form_fill", "data": ...}` back (`ws_type = "form_fill" if assessment_type else "symptoms"`). The client (`realtime_asr_controller.dart:368-372`) has a working `case 'form_fill':` handler that correctly parses this into a `FormPrefillResult`.

But the client's `case 'symptoms':` branch carries this comment (`realtime_asr_controller.dart:358-361`):
> "The backend does not yet support the form_fill mode — it always returns 'symptoms'. When Step 2 form-fill mode is active (schema set), convert the symptoms response into a FormPrefillResult so the banner can still pre-fill the form fields."

And the regex-fallback function itself (`_symptomsToFormFill`, line 480-481) says the same thing: *"regex parsing here bridges the gap until the server-side assessment-type extraction is deployed."*

**This is either stale documentation left over from before the backend added `assessment_extraction.py`, or a real environment/deployment lag (the mobile app talking to a deployed ai-service version that predates this pipeline) — static analysis alone can't tell which, but either way it needs resolving by testing against the actual deployed backend, not assumed fixed because the source code looks right.** If the fallback is still firing in production, Step 2 auto-fill is running on the far weaker mechanism described next, not the validated one.

**2. The regex fallback (`_symptomsToFormFill`, `realtime_asr_controller.dart:413-560+`) is fundamentally unreliable, by construction — not a bug, a structural limitation.**

It reconstructs Step 2 field values entirely from parsing the LLM's loosely-specified `clinicalNotes` free-text summary field (prompted only as *"Bullet-style concise summary"* in `inference.py`, no fixed phrasing contract) via rigid regexes:
- `weight (\d+(?:\.\d+)?)\s*kg` — misses "Weight: 65kg", "wt 65 kg", any phrasing the LLM didn't happen to use verbatim.
- `hemoglobin (\d+(?:\.\d+)?)(?:%|g/dl)?`, `pulse (\d+)`, `fundal height... cm`, `fetal movement (normal|not felt|less...)` — same fragility, one fixed phrase pattern each.
- Blood pressure/glucose are parsed from the *structured* `bloodPressure`/`bloodGlucose` fields (more reliable), but everything else depends on the free-text notes matching a hardcoded pattern.
- `chiefComplaints` → unconditionally mapped to fieldId `ncdSymptoms` regardless of the active assessment type (line 466-476) — wrong target for an ANC-only visit, and moot anyway since `ncdSymptoms` isn't a real fieldRef in any layout (see next finding).

Compare to the real pipeline (`assessment_extraction.py`, verified directly): schema-driven prompts per assessment type, an anti-hallucination gate requiring each extracted value to be transcript-anchored (`_segment_anchored`, ≥60% token overlap) before acceptance, and values that fail validation reported in `unmappedFindings` rather than silently dropped. The fallback has none of this — it either matches a rigid pattern or produces nothing, with no way to tell the SK "the model said something about your pulse but I couldn't parse it."

**This single issue plausibly explains most "fields aren't auto-filling" reports on its own** — it's not that a specific field is broken, it's that the whole mechanism currently in the loop is a best-effort regex bridge over free text, not the schema-validated extraction that was actually built for this.

---

## 🔴 Critical — the AI is asked for fields that don't exist on the form

Independently of which extraction path runs, `FormFieldSchemaBuilder` (`lib/features/scribe/form_field_schema_builder.dart`) is a **hand-maintained, hardcoded field list per programme** — it does not read `field_library.json`/`layout_manifests.json`, so it can (and has) drifted from the real form. Verified directly against `assets/forms/layout_manifests.json`:

| Requested field | Programme asked | Actually a fieldRef in... |
|---|---|---|
| `hba1c`, `compliance`, `hasSymptoms`, `ncdSymptoms`, `newWorseningSymptoms` | NCD | **nowhere — no formType has these as fieldRefs** |
| `bloodSugarFasting`, `bloodSugarRandom` | ANC | **nowhere** |
| `pulse`, `temperature` | ANC | only `pncMother`/`ncd` — never `anc` |

Consequence: even a *perfect* AI extraction for these NCD fields is applied to `CanonicalVisitData` by `applyAiPrefill` (they validate fine against `field_library.json`'s `FieldDef`, which does define them) but **never renders anywhere on the NCD/ANC screen** — and worse, `UnifiedPayloadMapper` (`unified_payload_mapper.dart:467,486-495` for the NCD fields; `:159-160,183-186,216-217` for the ANC ones) reads several of them straight into the submitted payload regardless. So these can be silently written to the clinical record without the SK ever seeing the value change on screen — a more insidious version of the "stale hidden field" class of bug fixed earlier in this project, because `_computeHiddenFieldIds` (the pre-submit stale-value guard) only scans fields that ARE real `fieldRefs` — it can't catch a field that was never a section member at all.

---

## 🔴 Critical — a real code/test contradiction on the combined-visit path

`FormFieldSchemaBuilder.assessmentTypeFor` returns `'anc,ncd'` for a patient enrolled in both ANC and NCD, but the existing test (`test/features/visit/forms/ai_prefill_guard_test.dart`, `'anc outranks ncd in combined visits'`) still expects `'anc'` alone — **confirmed currently failing** (ran it: `Expected: 'anc' / Actual: 'anc,ncd'`). The server (`assessment_extraction.py::run_assessment_extraction`) does correctly handle the comma-joined form (splits, runs both prompts independently, merges first-occurrence-wins) — so the *behavior* isn't necessarily wrong, but the test wasn't updated when the code changed, meaning this path shipped without its own regression coverage confirming end-to-end correctness.

---

## 🟠 Coverage gaps — some visit types get zero Step 2 auto-fill, by design or by omission

- **PNC (mother and/or child) — zero auto-fill, deliberately.** `assessmentTypeFor` returns `null` for any programme set containing PNC (mother-only extraction was rejected as a design choice because it would drop newborn-specific utterances). If the "fields aren't filling" reports are from PNC visits, this is expected behavior today, not a bug — but it's a real, user-visible coverage hole worth surfacing explicitly since the banner still appears and still records.
- **IMCI, TB, and every other non-ANC/NCD programme (epi, nutrition, familyPlanning, cataract, eyeCare, pw, unknown) — zero auto-fill.** `assessmentTypeFor` only ever returns `anc`, `ncd`, `anc,ncd`, or `null`. `FormFieldSchemaBuilder` has dead `_imci`/`_tb` schema-building code (never reachable, since `assessmentTypeFor` never emits those type strings) and the server has no matching prompt/schema for them anyway (`SUPPORTED_ASSESSMENT_TYPES` = `ncd, anc, pncMother, pncChild` only, from `_PROMPT_MAP`).

---

## 🟡 Structural/reliability gaps

1. **The documented batch pipeline is dead code.** CLAUDE.md and prior session context describe `ScribeController.startRecording()→stopAndUpload()→poll→SoapFieldExtractor→review`. Confirmed via grep: `startRecordingForFormPrefill` has zero call sites; the old `ScribeBanner` widget (which wires `SoapFieldExtractor`'s output) is never instantiated; every live `AiScribeBanner` site passes `tapStartsLiveAsr: true`, so a tap always goes through the realtime WS path instead. `SoapFieldExtractor` itself is unreachable from any current UI path.
2. **Two independent, non-shared regex-based text-to-field parsers now exist** — the dead `SoapFieldExtractor` and the live `_symptomsToFormFill` — duplicated effort, and the dead one is misleading to anyone reading the codebase looking for "the" extraction logic.
3. **`field_library.json` has drifted between the two repos.** The ai-service keeps its own synced copy (`schemas/field_library.json`, regenerated into `schemas/assessment_schemas.json`/`prompts/assessment_*.txt` via `scripts/generate_assessment_schemas.py`); its own CI (`tests/test_assessment_schemas.py::test_generated_artifacts_not_stale`) only checks that the generated schema matches the *committed* `field_library.json` copy — not that the committed copy still matches the live mobile source. Confirmed real differences exist (e.g. some fields' `visibility` differs between the two copies). A drifted server-side schema can silently validate against a form shape the mobile app no longer renders.
4. **Inconsistent kill-switch coverage.** Both Step 1 `AiScribeBanner` call sites gate on `if (AppConfig.scribeEnabled)`; `unified_form_screen.dart`'s Step 2 banner has no such gate at all (zero hits for `scribeEnabled` in that file). Setting `SCRIBE_ENABLED=false` would hide Step 1's banner but leave Step 2's banner — and its WS connection attempts — running.
5. **Several no-feedback silent-failure states**, none of which show the SK any error:
   - `assessmentType == null` (any unsupported programme mix) → banner looks fully functional (records, shows transcript, "Extract Now" works) but no field ever reaches `applyAiPrefill`, because `_formSchema` was never set.
   - The `ScribeController` provider missing above the banner in the widget tree → banner silently renders as `SizedBox.shrink()`.
   - Web platform → live ASR is unsupported there by design (native-only WebSocket header requirement), surfaced only as a generic error.

---

## 🟡 `applyAiPrefill()` failure modes (once a value does arrive)

For completeness — these apply regardless of which extraction path produced the value, verified against `unified_form_notifier.dart:334-435`:

| Cause | Effect |
|---|---|
| `fieldId` not in the active `FieldDef` map | rejected, reported as "unknown field" |
| Enum/option value doesn't match any id or display name | silently skipped |
| `dialogCheckbox` (list) value — **one bad entry invalidates the whole list** | none of the set applied, not just the bad entry |
| `bpLogDetails` shape validation fails (non-list, empty, malformed item) | rejected |
| SK already typed or edited the field (`manual`/`aiModified`) | correctly skipped — SK always wins |
| `FieldVisibilityRules.isFieldVisible` hides the field (e.g. AI fills `livingChildren` without the `gravida`/`parity` values needed to reveal it) | value sits invisibly in `CanonicalVisitData` until the pre-submit `clearFields` guard strips it — auto-fill "did nothing visible," though at least it doesn't leak into the payload |
| Field isn't a `fieldRef` of any section at all (see the schema-mismatch finding above) | **worse than the above** — never renders, and unlike the visibility case, is NOT caught by the pre-submit `clearFields` guard (which only scans real fieldRefs), so it can leak into the submitted payload unseen |

---

## Summary

Ranked by how much of the "fields aren't auto-filling" symptom each likely explains:

1. **Regex-fallback-instead-of-real-pipeline** (🔴 #1/#2) — most likely dominant cause; needs live-environment verification, not just a source read, to confirm which path is actually firing today.
2. **Schema/layout drift** (🔴 #3) — guarantees certain fields can never auto-fill regardless of extraction quality, for ANC and NCD specifically.
3. **Combined-visit test/behavior mismatch** (🔴 #4) — needs re-verification now that the code sends `anc,ncd`.
4. **Full-coverage gaps for PNC/IMCI/TB/other programmes** (🟠) — by design or omission, but real from the SK's perspective.
5. **Structural gaps** (🟡) — dead code, doc/schema drift, inconsistent kill-switch, silent no-feedback states — lower individual impact but compound the difficulty of diagnosing any of the above from the field.

No code changed — this document and all findings above are analysis only.
