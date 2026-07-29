# Step 2 Symptom Strip — Feature Spec

## Problem

The SK selects symptoms in Step 1 (`SymptomPickerScreen`) and then advances to Step 2 (`UnifiedFormScreen`) to fill vitals and clinical fields. The only reference to Step 1 symptoms in Step 2 is inside collapsible `_ProgrammeDivider` widgets, which are collapsed by default and scattered across the form. The SK has no at-a-glance reminder of what was reported while filling the assessment.

## Solution

A compact, horizontally-scrollable symptom strip at the very top of Step 2, above the AI Scribe banner. It shows all reported symptoms as read-only chips, colour-coded by source.

## Data Sources

| Source | Type | Colour |
|---|---|---|
| Live ASR (AI Scribe LIVE mode) | `chiefComplaints: List<String>` — plain English phrases from the scribe service | Amber |
| Manual chip tap | Vocab code → `TriageStrings.symptomLabel()` | Amber |
| Batch AI Scribe (pre-tick) | Vocab code → `TriageStrings.symptomLabel()` | Purple |

**Priority:** `chiefComplaints` when non-empty (live ASR path); otherwise vocab-code labels.  
**Guard:** strip is invisible when no symptoms were selected.

---

## Implementation

### A. Thread `chiefComplaints` through the callback chain

The live ASR path currently converts `RealtimeClinicalFields.chiefComplaints` to vocab codes via `ChiefComplaintMatcher.match()` and discards the raw phrases. Five files need changes to preserve and forward them.

**1. `lib/features/visit/triage/triage_view_model.dart`**

```dart
List<String> _scribeChiefComplaints = const [];
List<String> get scribeChiefComplaints => _scribeChiefComplaints;

void setChiefComplaints(List<String> phrases) {
  _scribeChiefComplaints = phrases;
}
```

**2. `lib/features/visit/triage/symptom_picker_screen.dart`**

In `onLiveFields` callback, before `ChiefComplaintMatcher.match()`:
```dart
vm.setChiefComplaints(fields.chiefComplaints);
```

In `_doAdvance()`, add fifth argument to `onSymptomsConfirmed`:
```dart
widget.onSymptomsConfirmed?.call(
  vm.selectedSymptoms,
  vm.sicknessDuration,
  vm.customSymptomText,
  vm.scribePreTickedCodes,
  vm.scribeChiefComplaints,   // new
);
```

Update the callback typedef to add the fifth positional parameter.

**3. `lib/features/visit/visit_flow_screen.dart`**

- `_Step1Symptoms`: update callback re-declaration.
- `_VisitFlowState`: add `List<String> _confirmedChiefComplaints = const []`; store in handler; pass to `_Step2ProgrammesThenForm`.

**4. `lib/features/visit/visit_form_screen.dart`**

Add `final List<String> confirmedChiefComplaints;`; pass into `UnifiedFormScreen` in `_buildSectionedScreen()`.

**5. `lib/features/visit/forms/unified_form_screen.dart`**

Add `final List<String> confirmedChiefComplaints;` to widget.

---

### B. Render the strip in `unified_form_screen.dart`

New private widget `_SelectedSymptomsStrip`:
- Takes `chiefComplaints`, `symptoms` (vocab codes), `aiPicked`
- Prefers `chiefComplaints` for labels; falls back to `TriageStrings.symptomLabel(code)`
- Reuses existing `_TriageChip` (amber / purple variants already implemented)
- Horizontally scrollable `Row` inside `SingleChildScrollView`
- Section header: `TriageStrings.symptomSummaryLabel`

Insert before `AiScribeBanner` in `_UnifiedFormScreenState.build()`:
```dart
Column(
  children: [
    _SelectedSymptomsStrip(
      chiefComplaints: widget.confirmedChiefComplaints,
      symptoms: widget.confirmedSymptoms,
      aiPicked: widget.aiPickedSymptoms,
    ),
    Padding(..., child: AiScribeBanner(...)),  // unchanged
    Expanded(...),                              // unchanged
  ],
)
```

---

### C. Add string constant

`lib/core/constants/app_strings.dart` — inside `TriageStrings`:
```dart
static const String symptomSummaryLabel = 'Reported symptoms';
```

---

## Unchanged

- `_ProgrammeDivider` collapsible chips — remain as-is (per-programme drill-down, different purpose)
- Batch ASR path — vocab codes already flow through `confirmedSymptoms`; no model changes needed
- `ChiefComplaintMatcher` — no change (upstream conversion is preserved)

---

## Verification

1. `flutter run --dart-define=BASE_URL=http://10.0.2.2 --dart-define=PASSWORD_HASH_KEY=spice_uat`
2. ANC/NCD patient → start visit
3. Live ASR: LIVE toggle → speak symptoms → Step 2 strip shows plain-English phrases
4. Manual chips: tap chips → Step 2 strip shows amber labels
5. Batch scribe: record → accept → Step 2 strip shows purple chips for AI-ticked codes
6. Zero symptoms → strip absent
7. `flutter analyze` — zero issues
