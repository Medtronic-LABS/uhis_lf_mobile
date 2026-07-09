# Band + Modifier Risk Scoring Logic

**Source:** PRD §2.8 — approved by clinical lead  
**GitHub:** https://github.com/Medtronic-LABS/uhis_lf_mobile/issues/60  
**Owner:** `RiskScoringService` (`lib/core/risk/risk_scoring_service.dart`)  
**Persistence:** `patients.band_wire_tag`, `patients.modifier_wire_tag`, `patients.risk_score`  
**Consumer:** `MissionDashboardService.computeTieredQueue()` — sort order on Mission Dashboard

---

## 1. Model Overview

The worst **single** clinical finding determines the patient's band (1–4). No composite score is
calculated. Letter modifiers (a, b) rank patients within a band.

### Band definitions

| Band | Severity | Typical action |
|------|----------|---------------|
| 1 | Critical / immediate | Urgent referral; status pill = **"Now"** |
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
| `b` | Overdue — missed scheduled visit |
| none | No modifier applies |

When both `a` and `b` trigger, `a` takes precedence.

### What the SK sees vs. what drives sort

| Dimension | Visible to SK? | Drives sort order? |
|-----------|---------------|-------------------|
| Band number | **No** | **Yes** — primary key |
| Modifier letter | **No** | **Yes** — secondary key |
| Status pill ("Now", "Overdue", …) | Yes | No — display only |
| Reason badge ("Missed ANC", …) | Yes | No — display only |

---

## 2. ANC Risk Factor Table (§2.8.1)

Evaluated in `RiskScoringService.score()` when `programmes.contains(Programme.anc)` and `vitals != null`.

| Band | Risk Factor | Threshold | `ClinicalVitals` field |
|------|------------|-----------|----------------------|
| **1** | Active danger sign | Any present | `hasDangerSign` |
| **1** | Severe anaemia | Hb < 7.0 g/dL | `hemoglobin < 7.0` |
| **1** | Severe hypertension | Systolic ≥ 160 **OR** diastolic ≥ 110 mmHg | `systolicBp >= 160 \|\| diastolicBp >= 110` |
| **2** | Pre-eclampsia pattern | BP + weight + urine protein all rising across last 3 ANC visits | `hasEclampsia` (set by `_ancTrendSnapshotsForMany` + `_hasEclampsiaTrend`) |
| **2** | Elevated BP (single) | Systolic ≥ 140 **OR** diastolic ≥ 90 (below Band 1 threshold) | range check on `systolicBp` / `diastolicBp` |
| **2** | Abnormal urine | Protein / albumin / sugar present | `hasAbnormalUrine` |
| **2** | GDM risk | Fasting glucose ≥ 5.1 mmol/L | `fastingGlucoseMmolL >= 5.1` |
| **2** | Moderate anaemia | Hb 7.0–9.9 g/dL | `hemoglobin` range |
| **3** | Mild anaemia | Hb 10.0–10.9 g/dL | `hemoglobin` range |
| **3** | Near-term pregnancy | GA ≥ 36 weeks | `gestationalAgeWeeks >= 36` |

### ANC Modifier rules

| Modifier | Trigger | Field |
|----------|---------|-------|
| `a` | First pregnancy (primigravida) | `parity == 0` |
| `a` | GA ≥ 36 weeks | `gestationalAgeWeeks >= 36` |
| `a` | Comorbidity (diabetes) | `hasDiabetes` |
| `b` | Missed ANC visit > 28 days | `PatientFacts.daysSinceLastVisit > 28` |

---

## 3. NCD Risk Factor Table (§2.8.2)

Evaluated in `RiskScoringService.score()` when `programmes.contains(Programme.ncd)`.

| Band | Risk Factor | Threshold | `ClinicalVitals` field |
|------|------------|-----------|----------------------|
| **1** | Stroke sign | One-sided weakness | `hasStrokeSign` |
| **1** | SOB + high BP | Both present (SOB AND systolic ≥ 140) | `hasSobWithHighBp` |
| **1** | Hypertensive crisis | Systolic ≥ 180 **OR** diastolic ≥ 110 mmHg | range check |
| **1** | Diabetic crisis | Fasting glucose ≥ 18.0 mmol/L | `fastingGlucoseMmolL >= 18.0` |
| **2** | Stage 2 hypertension | Systolic 160–179 **OR** diastolic 100–109 | range check |
| **2** | Poorly controlled DM | Fasting glucose 10.0–17.9 mmol/L | range check |
| **3** | Stage 1 hypertension | Systolic 140–159 **OR** diastolic 90–99 | range check |
| **3** | Elevated glucose | Fasting glucose 7.0–9.9 mmol/L | range check |
| **4** | Pre-hypertension | Systolic 130–139 **OR** diastolic 85–89 | range check |
| **4** | Pre-diabetes | Fasting glucose 6.1–6.9 mmol/L | range check |

### NCD Modifier rules

| Modifier | Trigger | Field |
|----------|---------|-------|
| `a` | Comorbid HTN + DM | `hasHypertension && hasDiabetes` |
| `a` | Elderly NCD patient | `ageYears >= 60` |
| `b` | Missed NCD follow-up > 42 days | `PatientFacts.daysSinceLastVisit > 42` |

---

## 4. Worst-Finding Semantics

`RiskScoringService` evaluates **all** applicable rules and keeps the **lowest band number** (most
urgent). Multiple findings do not add — only the worst one determines the band.

```dart
void considerBand(Band candidate, String driver) {
  drivers.add(driver);
  if (worst == null || candidate.index < worst!.index) worst = candidate;
}
```

---

## 5. Cross-Programme Rules

### 5.1 Multi-programme patients

A patient enrolled in both ANC and NCD is evaluated for both programme rule-sets in a single
`score()` call. The worst band across both evaluations is used.

### 5.2 Cross-programme modifier combination (CD-1)

When a patient has modifier triggers from multiple programmes, a single `triggerA` / `triggerB`
boolean accumulates across all programme evaluations. Resolution:

- `triggerA` → modifier `a`
- `triggerB` (no `triggerA`) → modifier `b`
- neither → modifier `none`

**`a` always beats `b`** — both firing produces `a`.

Within-band tiebreaker when modifier is equal: ANC programme ranks above NCD (`compareInBand` step 2).

### 5.3 Referral SLA breach (CD-2)

A patient whose active referral has a breached SLA is treated as **Band 1** regardless of clinical band.

- Driver tag emitted: `'referral-sla-breach'`
- Evaluated in `MissionDashboardService._classify()`, not in `RiskScoringService`
- `effectiveBand` overridden to `Band.band1` in `computeTieredQueue()` when driver fires
- Source: `MissionInputData.slaBreachedReferralPatientIds` (populated by `MissionDashboardRepository` from `referralAssessments` where `level == SlaPriority.critical`)

---

## 6. Pre-eclampsia Trend Rule (ANC Band 2) ✅ Implemented

Band 2 (`anc-eclampsia`) is assigned when **all three** of the following are non-decreasing
visit-to-visit AND strictly higher at visit 3 than visit 1, across the patient's last 3 ANC visits:

1. Systolic BP
2. Body weight (kg) — optional: if entirely absent, rule still fires on BP + urine alone
3. Urine protein positive at the **most recent** visit

**Conservative rule:** if any systolic reading is missing, the trend does not fire.

### Implementation

**DAO:** `LocalAssessmentDao._ancTrendSnapshotsForMany(patientIds)`
- Batch query: last 3 ANC assessments per patient, ordered newest-first, collected and reversed to oldest-first
- Parses `systolic` / `bloodPressureSystolic`, `weight` / `bodyWeight`, `urineProtein` / `urinaryAlbumin`
- Returns `Map<String, List<_AncTrendSnapshot>>`

**Detector:** `LocalAssessmentDao._hasEclampsiaTrend(List<_AncTrendSnapshot>)`
```dart
static bool _hasEclampsiaTrend(List<_AncTrendSnapshot> snapshots) {
  if (snapshots.length < 3) return false;
  // sys: non-decreasing at each step AND overall strictly increasing
  if (sys1 > sys2 || sys2 > sys3 || sys1 >= sys3) return false;
  // weight: where both ends present, overall must rise; middle must not dip
  if (w1 != null && w3 != null && w1 >= w3) return false;
  // urine: latest visit must show protein
  return s3.urineProteinPositive;
}
```

**Merge:** `latestClinicalVitalsForMany()` ORs the trend flag into `ClinicalVitals.hasEclampsia`:
```dart
final hasEclampsia = (eclampsiaRaw == true || ...) || eclampsiaTrendPids.contains(pid);
```

**Tests:** `test/core/db/local_assessment_eclampsia_trend_test.dart` — 11 cases covering happy path,
flat BP, dipping BP, absent urine, < 3 visits, missing systolic, absent weight, weight dip, form-level
flag, batch correctness, sliding-window boundary.

---

## 7. `_classify()` — Display Tier Assignment

`MissionDashboardService._classify()` runs after `RiskScoringService` has stamped `band` on each
`WorklistEntry`. It reads `entry.band` and the behavioural signal sets from `MissionInputData` to
assign a `DashboardTier` (for the status pill) and emit driver tags (for the card reason).

### Critical drivers (always → `DashboardTier.critical`)

| Driver tag | Condition |
|------------|-----------|
| `red-flag` | `redFlagPatientIds` contains patient OR `band == Band.band1` |
| `referral-sla-breach` | `slaBreachedReferralPatientIds` contains patient |
| `hi-risk-anc-gap` | High-risk pregnant AND has ANC schedule gaps |
| `neonate` | Age < 28 days |
| `young-infant` | Age 28–60 days |
| `pnc-window` | Within 42 days postpartum |
| `anc-near-term` | EDD within 14 days |
| `delivery-complication` | Delivery complications recorded |
| `pnc-illness` | PNC illness recorded |

### Overdue-minimum drivers (floor → `DashboardTier.overdue`)

| Driver tag | Condition |
|------------|-----------|
| `ltfu-streak` | `patientsLtfu` OR unsuccessful attempts > 2 |
| `tb-default-risk` | TB enrolment + unsuccessful contact attempts |
| `ncd-drift` | NCD patient with past-due assessment date |
| `referral-arrival-pending` | Referred, facility arrival not recorded ≥ 3 days |
| `child-disability` | Age < 5 AND disability flag |

### Date-based tier (no driver)

| `daysToDue` | Tier |
|-------------|------|
| `null` or `> 7` | `upcoming` |
| `1` to `7` | `thisWeek` |
| `−2` to `0` | `dueToday` |
| `< −2` | `overdue` |

---

## 8. Status-Pill Mapping

| `DashboardTier` | Pill label | Dot colour | Token |
|-----------------|------------|------------|-------|
| `critical` | **Now** | Red | `urgency.visitNow` |
| `overdue` | **Overdue** | Amber | `urgency.today` |
| `dueToday` | **Today** | Green | `tokens.statusSuccess` |
| `thisWeek` | **This week** | Teal | `urgency.thisWeek` |
| `upcoming` | **Routine** | Grey | `urgency.routine` |

`DashboardTier` is driven by scheduling (`dueAt`) and behavioural drivers. It does **not** affect sort
order — sort order is band + modifier only.

---

## 9. Comparator Specification

```dart
// Primary sort in computeTieredQueue()
result.sort((a, b) {
  final bandCmp = a.band.index.compareTo(b.band.index); // ASC — Band 1 first
  if (bandCmp != 0) return bandCmp;
  return MissionQueueItem.compareInBand(a, b);
});

// Within-band comparator (MissionQueueItem.compareInBand)
static int compareInBand(MissionQueueItem a, MissionQueueItem b) {
  // 1. Modifier: a(0) < b(1) < none(2)
  final modCmp = a.modifier.sortRank.compareTo(b.modifier.sortRank);
  if (modCmp != 0) return modCmp;
  // 2. ANC programme priority when modifier ties (CD-1)
  final ancCmp = _ancRank(b).compareTo(_ancRank(a));
  if (ancCmp != 0) return ancCmp;
  // 3. Pregnant before non-pregnant (PRD §2.8 requirement)
  final pregCmp = (b.isPregnant ? 0 : 1).compareTo(a.isPregnant ? 0 : 1);
  if (pregCmp != 0) return pregCmp;
  // 4. Stable alphabetical tiebreaker
  return a.patientName.compareTo(b.patientName);
}
```

---

## 10. Sort key persisted to SQLite

`sortRankFor(band, modifier)` produces an integer written to `patients.risk_score` so SQL
`ORDER BY risk_score DESC` gives the same sequence as the Dart comparator:

| Position | risk_score |
|----------|-----------|
| 1a | 1030 |
| 1b | 1020 |
| 1 (none) | 1010 |
| 2a | 730 |
| 2b | 720 |
| 2 (none) | 710 |
| 3a | 430 |
| 3b | 420 |
| 3 (none) | 410 |
| 4 (any) | 100–130 |

Pregnancy is not baked into `risk_score` — it is a secondary sort applied at query / comparator time.

---

## 11. Open Items

| # | Item | Status |
|---|------|--------|
| G11 | CQL integration — `cqlResults` wired into `MissionInputData` but not consulted by classification | Future iteration |
| — | FHIR Observations (Hb LOINC 718-7, BP 85354-9, glucose 2339-0) are online-only; not cached locally | Accepted v1 limitation |
| — | `compareByDueAtAsc` on `MissionQueueItem` retained for deep-link patient list but currently unused | Delete in follow-up |
