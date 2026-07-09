# Band + Modifier Risk Scoring Logic

**Source:** PRD §2.8 — approved by clinical lead  
**GitHub:** https://github.com/Medtronic-LABS/uhis_lf_mobile/issues/60  
**Owner:** `RiskScoringService` → persisted to `patients.risk_band / risk_modifier`  
**Consumer:** `MissionDashboardService.computeTieredQueue()` → sort order on Mission Dashboard

---

## 1. Model Overview

The worst **single** clinical finding determines the patient's band (1–4). No composite score is
calculated. Letter modifiers (a, b) rank patients within a band.

### Band definitions

| Band | Severity | Typical action |
|------|----------|---------------|
| 1 | Critical / immediate | Urgent referral; status = **"Now"** |
| 2 | High risk | Refer within 48 hrs |
| 3 | Moderate risk | Routine referral or counselling |
| 4 | Low / preventive | Lifestyle counselling |

### Sort order

```
1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4
```

Within any position, **pregnant patients always rank before non-pregnant patients**.

### Modifier definitions

| Modifier | Meaning |
|----------|---------|
| `a` | Additional risk — comorbidity, first pregnancy, ≥ 36 weeks GA, or age ≥ 60 |
| `b` | Overdue — missed scheduled visit; longer overdue = higher within band |
| none | No modifier applies |

### What the SK sees vs. what drives sort

| Dimension | Visible to SK? | Drives sort order? |
|-----------|---------------|-------------------|
| Band number | **No** | **Yes** — primary key |
| Modifier letter | **No** | **Yes** — secondary key |
| Status pill ("Now", "Overdue", …) | Yes | No — display only |
| Reason badge ("Missed ANC", …) | Yes | No — display only |

---

## 2. ANC Risk Factor Table (§2.8.1)

| Band | Risk Factor | Threshold | `ClinicalVitals` field | Evaluator |
|------|------------|-----------|----------------------|-----------|
| **1** | Active danger sign (any) | Any present | `hasDangerSign` | `RiskScoringService._ancBand()` |
| **1** | Severe anaemia | Hb < 7.0 g/dL | `hemoglobin < 7.0` | same |
| **1** | High BP | Systolic ≥ 160 AND diastolic ≥ 110 mmHg | `systolicBp >= 160 && diastolicBp >= 110` | same |
| **2** | Pre-eclampsia pattern | BP + weight + urine all rising across 3 visits | `LocalAssessmentDao.lastThreeAncVitals()` → `_hasPreeclampsiaPattern()` | `RiskScoringService._preeclampsiaCheck()` |
| **2** | BP ≥ 140/90 (single) | Systolic ≥ 140 AND diastolic ≥ 90 | `systolicBp >= 140 && diastolicBp >= 90` | `RiskScoringService._ancBand()` |
| **2** | Abnormal urine | Protein / glucose / infection present | `hasAbnormalUrine` | same |
| **2** | GDM risk | Fasting glucose ≥ 5.1 mmol/L | `fastingGlucoseMmolL >= 5.1` | same |
| **2** | Moderate anaemia | Hb 7.0–9.9 g/dL | `hemoglobin >= 7.0 && hemoglobin < 10.0` | same |
| **3** | Mild anaemia | Hb 10.0–10.9 g/dL | `hemoglobin >= 10.0 && hemoglobin < 11.0` | same |
| **3** | Near-term pregnancy | GA ≥ 36 weeks | `gestationalAgeWeeks >= 36` | same |

### ANC Modifier rules

| Modifier | Trigger | `ClinicalVitals` / context field |
|----------|---------|----------------------------------|
| `a` | First pregnancy (primigravida) | `parity == 0` |
| `a` | GA ≥ 36 weeks | `gestationalAgeWeeks >= 36` |
| `a` | Comorbidity (e.g., diabetes) | `hasDiabetes` |
| `b` | Missed ANC visit | `daysOverdue > 0` (from worklist `nextDueAt`) |

When both `a` and `b` apply, `a` takes precedence.

---

## 3. NCD Risk Factor Table (§2.8.2)

| Band | Risk Factor | Threshold | `ClinicalVitals` field | Evaluator |
|------|------------|-----------|----------------------|-----------|
| **1** | Stroke signs | One-sided weakness | `hasStrokeSign` | `RiskScoringService._ncdBand()` |
| **1** | Shortness of breath + high BP | Both present (SOB + systolic ≥ 140) | `hasSobWithHighBp` | same |
| **1** | Hypertensive crisis | BP ≥ 180/110 | `systolicBp >= 180 && diastolicBp >= 110` | same |
| **1** | Severe hyperglycaemia | Fasting glucose ≥ 18.0 mmol/L | `fastingGlucoseMmolL >= 18.0` | same |
| **2** | High BP | Systolic 160–179 OR diastolic 100–109 | `systolicBp in [160,180) \|\| diastolicBp in [100,110)` | same |
| **2** | High glucose | Fasting glucose 10.0–17.9 mmol/L | `fastingGlucoseMmolL in [10.0,18.0)` | same |
| **3** | Elevated BP | Systolic 140–159 OR diastolic 90–99 | `systolicBp in [140,160) \|\| diastolicBp in [90,100)` | same |
| **3** | Elevated glucose | Fasting glucose 7.0–9.9 mmol/L | `fastingGlucoseMmolL in [7.0,10.0)` | same |
| **4** | Pre-hypertension | BP 130–139 / 85–89 | `systolicBp in [130,140) \|\| diastolicBp in [85,90)` | same |
| **4** | Pre-diabetes | Fasting glucose 6.1–6.9 mmol/L | `fastingGlucoseMmolL in [6.1,7.0)` | same |

### NCD Modifier rules

| Modifier | Trigger | Field |
|----------|---------|-------|
| `a` | Comorbid hypertension + diabetes | `hasHypertension && hasDiabetes` |
| `a` | Elderly NCD patient | `age >= 60` |
| `b` | Missed NCD follow-up | `daysOverdue > 0` |

---

## 4. Worst-Finding Semantics

`RiskScoringService` evaluates **all** applicable rules and keeps the **lowest band number** (most
urgent). Multiple findings do not add — the single worst one determines the band.

```dart
Band _worstBand(Iterable<Band> candidates) =>
    candidates.fold(Band.band4, (best, b) => b.index < best.index ? b : best);
```

---

## 5. Cross-Programme Rules

### 5.1 Multi-programme patients

A patient enrolled in both ANC and NCD is classified once, using the worst band across both
programme evaluations.

### 5.2 Cross-programme modifier combination (CD-1)

When a patient has modifiers from multiple programmes:
- **Best modifier wins** — `a` beats `b`.
- **Tiebreaker when modifiers are equal** — ANC programme ranks above NCD.

Example: ANC modifier `a` (primigravida) + NCD modifier `b` (overdue) → final modifier = `a`.

### 5.3 Referral SLA breach (CD-2)

A referral whose SLA is breached is treated as **Band 1**, regardless of clinical band.

- Driver tag emitted: `'referral-sla-breach'`
- Evaluated in `MissionDashboardService._classify()` (not in `RiskScoringService`)
- `entry.band` is overridden to `Band.band1` when this condition fires

---

## 6. Pre-eclampsia Trend Rule (ANC Band 2)

Band 2 is assigned when **all three** of the following are rising across the last 3 ANC visits:

1. Systolic BP
2. Body weight (kg)
3. Urine protein present

### Implementation

New DAO method:
```dart
// lib/core/db/local_assessment_dao.dart
Future<List<ClinicalVitals>> lastThreeAncVitals(String patientId)
```
Returns the three most recent ANC rows for the patient, **oldest-first**, each decoded to a
`ClinicalVitals` with `systolicBp`, `weightKg`, and `hasAbnormalUrine` populated.

Detection in `RiskScoringService`:
```dart
bool _hasPreeclampsiaPattern(List<ClinicalVitals> visits) {
  if (visits.length < 3) return false;
  return _isRising(visits.map((v) => v.systolicBp?.toDouble()))
      && _isRising(visits.map((v) => v.weightKg))
      && visits.every((v) => v.hasAbnormalUrine);
}

bool _isRising(Iterable<double?> values) {
  final vs = values.whereType<double>().toList();
  if (vs.length < 3) return false;
  return vs[1] > vs[0] && vs[2] > vs[1];
}
```

---

## 7. Status-Pill Mapping (what the SK sees)

| Band | DashboardTier | Status pill label | Left-border colour |
|------|--------------|-------------------|--------------------|
| 1 | `critical` | **"Now"** — always, regardless of `dueAt` | Red |
| 2 | `overdue` | "Overdue" | Amber |
| 3 | `dueToday` / `thisWeek` | "Due today" / "This week" | Navy |
| 4 | `upcoming` | "Upcoming" | Light grey |

Scheduling (`dueAt`) determines the status label for Bands 2–4 but does **not** influence sort
order. Sort order is determined purely by band → modifier → ANC-programme priority → pregnant-first
→ name.

---

## 8. Comparator Specification

```dart
// Primary sort key in computeTieredQueue()
result.sort((a, b) {
  final bandCmp = a.band.index.compareTo(b.band.index); // ASC — Band 1 first
  if (bandCmp != 0) return bandCmp;
  return MissionQueueItem.compareInBand(a, b);
});

// Within-band comparator on MissionQueueItem
static int compareInBand(MissionQueueItem a, MissionQueueItem b) {
  // 1. Modifier: a(0) < b(1) < none(2)
  final modCmp = a.modifier.sortRank.compareTo(b.modifier.sortRank);
  if (modCmp != 0) return modCmp;
  // 2. ANC programme priority when modifier ties
  final ancCmp = _ancRank(b).compareTo(_ancRank(a));
  if (ancCmp != 0) return ancCmp;
  // 3. Pregnant before non-pregnant
  final pregCmp = (b.isPregnant ? 0 : 1).compareTo(a.isPregnant ? 0 : 1);
  if (pregCmp != 0) return pregCmp;
  // 4. Stable tiebreaker
  return a.patientName.compareTo(b.patientName);
}
```

---

## 9. Open Items / Known Limitations

| # | Item | Status |
|---|------|--------|
| G11 | CQL integration — `cqlResults` wired into `MissionInputData` but not yet consulted by classification | Future iteration |
| — | FHIR Observations (Hb LOINC 718-7, BP 85354-9, glucose 2339-0) are online-only — not cached locally | Accepted limitation for v1 |
| — | "Shortness of breath" is extracted from the danger-signs string list, not a dedicated form field — may miss non-standard phrasing | Track as tech debt |
| — | Pre-eclampsia trend requires exactly 3 prior ANC visits with all three values populated — patients with fewer visits get date-based Band 2 only if other conditions fire | Documented constraint |
| — | `compareByDueAtAsc` on `MissionQueueItem` is currently unused but retained for the deep-link patient list (`/patients?tier=`) | Delete in a follow-up ticket |
