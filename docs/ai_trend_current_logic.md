# AI Trend — Current Logic

## Context

Explanation-only writeup of how the "AI trend" feature actually works today, across the visit flow.
No code changes are proposed here — this is a map of current behavior, produced to answer "what is
the current logic of the AI trend."

**Headline finding: there are two separate, disconnected "trend" systems in this codebase.**

1. **`_VitalsTrendCard`** (Step 2 — `VisitFormScreen`/`UnifiedFormScreen`, *not* Step 3) — a simple
   rule-based card that **is live and visible to the SK today**.
2. **`CdssEngine` + CUSUM/EWMA/Slope calculators** (`lib/core/cdss/`) — a more sophisticated
   statistical-control-chart engine that **is never called from any UI or view-model in the app**.
   `CdssEngine.evaluate()` and `BpHistoryDao` have zero call sites outside their own files and unit
   tests — this entire subsystem is dead code today, not surfaced anywhere, including Step 3.

**Step 3 (`_Step3AiReco` in `visit_flow_screen.dart`) has no trend-specific widget at all.** It's
purely downstream of the NABA AI response, and the request sent to that AI (`NabaRequest`,
`naba_models.dart:103-125`) never populates its own `priorVisits` field with BP history — only a
single current-visit snapshot is sent (`currentVitals: NabaVitalSnapshot`, one point in time). So no
trend computation, client- or server-side, is even possible from Step 3 today. Whatever "AI trend"
is visible to the SK is almost certainly the Step 2 card below — its title literally reads *"AI sees
a trend across her {n} visits."*

---

## 1. `_VitalsTrendCard` (Step 2) — the live system

- **Where:** `lib/features/visit/forms/unified_form_screen.dart:1145` (widget), used at `:495-498`.
- **Shows when:**
  ```dart
  if (isAnc && _priorAncVisits.isNotEmpty) {
    items.add(_VitalsTrendCard(priorVisits: _priorAncVisits));
  }
  ```
  ANC active **and** at least 1 prior ANC visit exists — i.e. from the patient's **2nd** ANC visit
  onward.
- **Data:** `_priorAncVisits` (`List<VisitVitals>`), populated in `initState` via
  `notifier.ancVitalsHistory()` → `AssessmentRepository.ancVitalsHistory()`
  (`assessment_repository.dart:904-950`), which unions local + server-synced ANC rows (systolic,
  diastolic, weight, urine protein), sorted oldest-first. Combined with a live "Today" row read
  straight from `UnifiedFormNotifier.data` inside `build()` — updates on every keystroke, no
  prop-chain needed.
- **Renders:** a collapsible amber accordion (title = `UnifiedFormStrings.trendCardTitle(n)`) →
  a **text table** (`_buildTable`), not a chart/sparkline: one column per visit ("Visit 1"/"Visit
  2"/"Today" + "N weeks ago"), one row per metric (systolic, diastolic, weight-gain-from-baseline,
  urine-protein grade), each tagged 📈 (rising) or `·` (flat), plus a footer sentence that differs
  depending on whether a rise was detected.
- **The actual "rising"/show gate — `lib/features/visit/forms/vitals_trend.dart:184-206`:**
  ```dart
  final bpRising = (systolic?.rising ?? false) || (diastolic?.rising ?? false);
  return VitalsTrendResult(columns: columns, metrics: metrics, show: bpRising && metrics.isNotEmpty);
  // per-metric: rising: present.length >= 2 && _isRising(present)
  ```
  **This fires off just 2 data points (1 prior visit + today) — not 3.** This is the gate that
  actually matters for anything the SK sees; it is *not* the same gate discussed in section 2 below.

---

## 2. `CdssEngine.evaluate()` (`lib/core/cdss/cdss_engine.dart`) — built, but not wired up

```dart
final findrisc = FindriscCalculator.compute(profile);                 // always runs
final framingham = (profile.ageYears >= 18 && profile.bmi != null && profile.systolicBp != null)
    ? FraminghamCalculator.compute(profile) : null;
final hasTrendData = bpHistory.length >= 2;                            // the ">= 2" gate
final cusum  = hasTrendData ? CusumCalculator.compute(bpHistory) : null;
final ewma   = hasTrendData ? EwmaCalculator.compute(bpHistory) : null;
final slope  = hasTrendData ? SlopeCalculator.compute(bpHistory) : null;
final miniPiers = maternal != null ? MiniPiersCalculator.compute(maternal) : null;
```

Trigger conditions and thresholds:

| Algorithm | Trigger condition | Alert threshold |
|---|---|---|
| FINDRISC | always runs (partial score if `waistCm` absent) | `score ≥ 12` |
| Framingham | `ageYears ≥ 18 && bmi != null && systolicBp != null` | `riskPct ≥ 10` (`≥ 20` = high risk) |
| CUSUM | `bpHistory.length >= 2` | cumulative sum `s > 40` (slack `k=5`, `mu0` = first reading) |
| EWMA | `bpHistory.length >= 2` | `ewma > ucl` (`λ=0.2`, `σ=10` assumed, `ucl ≈ mu0+14.1`) |
| Slope | `bpHistory.length >= 2` | OLS `slope > 4 mmHg/visit` |
| miniPIERS | `maternal != null` (+ GA/SBP present) | `riskPct ≥ 25` (`≥ 50` = critical) |

**Confirmed: the `>= 2` gate is real and unchanged in the code.** But `CdssEngine.evaluate`,
`CusumCalculator`, `EwmaCalculator`, `SlopeCalculator`, and `BpHistoryDao` are called from nowhere in
`lib/` outside their own files and unit tests (`test/core/cdss/*_test.dart`).
`CdssEngineOutput.anyTrendAlert` (`cdss_results.dart:164-168`, ORs the three `.alert` flags) is
likewise never read anywhere. **Changing this file's gate today would change nothing the SK
sees**, since nothing renders this engine's output.

All three calculators independently re-guard the same `length < 2` condition (belt-and-suspenders
with the engine's `hasTrendData` check):
- **`cusum_calculator.dart`** — cumulative sum vs. `mu0` (first/oldest reading), slack `k = 5.0`,
  `alert = s > 40.0` ("≈4σ, σ=10" per its own doc comment).
- **`ewma_calculator.dart`** — `λ = 0.2`, assumed population `σ = 10.0`,
  `ucl = mu0 + 3σ√(λ/(2−λ)) ≈ mu0 + 14.1`, `alert = ewma > ucl`.
- **`slope_calculator.dart`** — OLS linear regression of systolic vs. visit index,
  `alert = slope > 4.0` mmHg/visit ("a slope > 4 mmHg/visit means the patient will reach 140 mmHg
  within 4 visits even if today's reading is 125 mmHg").

---

## 3. Other trend-adjacent logic (different screens, not Step 2 or Step 3)

- **`lib/core/clinical/briefing_rules/anc_briefing_rules.dart`** (`anc.bpRisingTrend`) and
  **`ncd_briefing_rules.dart`** (`ncd.trendingDown`) — single-*prior*-visit comparisons (current
  reading vs. the immediately preceding visit only, not a multi-visit statistical trend). These feed
  the separate patient-briefing surface (`briefing_findings_aggregator.dart`), not the 3-step visit
  flow.
- **`patient_context_screen.dart:1900-1936`** (`_derivePendingEntry()`) — a one-line "BP recheck
  due" pending-timeline heuristic (`sys - prevSys > 5` when `ancVisits.length >= 2`), on the Patient
  Context screen, unrelated to the visit flow. Git history shows this screen used to have real
  BP/glucose sparkline trend charts, since removed (`5894593` "refactor(patient): remove all trend
  charts", `0bfc70c` "remove trends"). **Today there is no chart-based trend UI anywhere in the
  app** — only the Step 2 text table (section 1) remains.

---

## 4. Step 3 in detail — confirming it has no trend logic of its own

- Step indexing (`visit_flow_screen.dart:7-14`): index 0 = symptom check, **index 1 = "Step 2:
  vitals + full form"** (wraps `VisitFormScreen` → `UnifiedFormScreen`, which hosts
  `_VitalsTrendCard`), **index 2 = "Step 3: AI recommendation"** (`_Step3AiReco`, rendered via
  `_buildResult`).
- Step 3 is entirely downstream of a `NabaResponse` — either the remote NABA AI service
  (`NabaRepository.generate(req)`) or a local `_ruleBasedNaba()` fallback used offline/on
  error/when disabled. Neither path references BP history, CUSUM/EWMA/slope, or the briefing-rule
  functions from section 3.
- `naba.clinicalFindings` is fetched and merged into the response object but **never rendered by any
  widget** in `_buildResult` — dead data on the client regardless of what the server puts in it.
- `naba.whatsappSummary` renders as the `_AiCounsellingCard` — free-form text (AI-generated or
  templated per-programme), no trend logic.
- `naba.dangerSigns` only ever comes from the remote AI response and feeds the referral banner text
  — nothing trend-specific is templated for it client-side.

---

## Net implication (if the issue #399 "min 3 vitals" concern is ever revisited)

The fix would need to land in **`vitals_trend.dart`** (the `present.length >= 2` check, and the
container-visibility checks in `vitals_trend.dart`/`unified_form_screen.dart:496`), since that's the
only pipeline with a live UI consumer. Changing `cdss_engine.dart`'s gate alone would have zero
visible effect, since nothing renders that engine's output today. Not proposed as a change here —
noted for whenever it's wanted.
