# Patient Scoring — Mission Dashboard

> **Current model:** Band + Modifier (PRD §2.8, implemented June 2026)  
> **Replaces:** Composite-score / 5-tier model (deleted — see git history)  
> **Source of truth:** `lib/core/risk/risk_scoring_service.dart`  
> **GitHub:** https://github.com/Medtronic-LABS/uhis_lf_mobile/issues/60

---

## How it works in one sentence

The **single worst clinical finding** determines the patient's band (1–4). A letter modifier (a or b) ranks patients within the same band. No composite score is calculated.

---

## Bands

| Band | Label | What it means | Status pill shown to SK |
|------|-------|---------------|------------------------|
| 1 | Severe | Clinical emergency — act immediately | **Now** (red) |
| 2 | Moderate | High clinical risk — prioritise this week | **Overdue** or **Today** (amber/green) |
| 3 | Mild | Moderate risk — routine follow-up | **Today** or **This week** (green/teal) |
| 4 | Routine | Preventive / lifestyle — no acute finding | **Routine** (grey) |

Band and modifier are **never shown to the SK** — they only drive sort order.

---

## Sort order

```
1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4
```

Within any position, **pregnant patients always rank above non-pregnant patients**.  
When modifier and pregnancy are tied, **ANC programme ranks above NCD**, then **alphabetical name** as a stable tiebreaker.

---

## Modifiers

| Modifier | Meaning | Triggers |
|----------|---------|---------|
| **a** | Additional clinical risk | First pregnancy (primigravida) · GA ≥ 36 weeks · ANC patient with diabetes · NCD: comorbid HTN + DM · NCD: age ≥ 60 |
| **b** | Overdue | ANC: last visit > 28 days ago · NCD: last visit > 42 days ago · Missed visits (other programmes) |
| **none** | No modifier | No additional risk or overdue signal |

When both `a` and `b` apply, **`a` takes precedence**.

---

## Band 1 — Severe (visit immediately)

### ANC patients
| Finding | Threshold |
|---------|-----------|
| Any danger sign | Any present on form |
| Severe anaemia | Hb < 7.0 g/dL |
| Severe hypertension | Systolic ≥ 160 OR diastolic ≥ 110 mmHg |

### NCD patients
| Finding | Threshold |
|---------|-----------|
| Stroke sign | One-sided weakness present |
| Breathlessness + high BP | Shortness of breath AND systolic ≥ 140 |
| Hypertensive crisis | Systolic ≥ 180 OR diastolic ≥ 110 mmHg |
| Diabetic crisis | Fasting glucose ≥ 18.0 mmol/L |

### Either programme (overrides clinical band)
| Finding | Source |
|---------|--------|
| Clinician red-flagged patient | Patient record `redFlag = true` |
| Server risk flag = RED or HIGH | Synced from backend |
| Referral SLA breached | Active referral overdue past SLA threshold |

---

## Band 2 — Moderate (prioritise this week)

### ANC patients
| Finding | Threshold |
|---------|-----------|
| Pre-eclampsia pattern | Systolic BP + body weight + urine protein all rising across the last 3 ANC visits |
| Elevated BP (single reading) | Systolic ≥ 140 OR diastolic ≥ 90 mmHg (below Band 1 threshold) |
| Abnormal urine | Protein / albumin / sugar present |
| GDM risk | Fasting glucose ≥ 5.1 mmol/L |
| Moderate anaemia | Hb 7.0–9.9 g/dL |

### NCD patients
| Finding | Threshold |
|---------|-----------|
| Stage 2 hypertension | Systolic 160–179 OR diastolic 100–109 mmHg |
| Poorly controlled diabetes | Fasting glucose 10.0–17.9 mmol/L |

### Either programme
| Finding | Source |
|---------|--------|
| Lost to follow-up | `isLost` flag on follow-up record |
| Server risk flag = YELLOW / AMBER | Synced from backend |
| TB enrolment | Default band for TB patients |

---

## Band 3 — Mild (routine follow-up)

### ANC patients
| Finding | Threshold |
|---------|-----------|
| Mild anaemia | Hb 10.0–10.9 g/dL |
| Near-term pregnancy | GA ≥ 36 weeks (also sets Modifier a) |

### NCD patients
| Finding | Threshold |
|---------|-----------|
| Stage 1 hypertension | Systolic 140–159 OR diastolic 90–99 mmHg |
| Elevated glucose | Fasting glucose 7.0–9.9 mmol/L |

### Either programme
| Finding | Source |
|---------|--------|
| IMCI enrolment | Default band for IMCI patients |
| Child under 5 (no ANC) | Age < 5 years |
| Missed visits in last 90 days | Non-ANC/NCD patients only |

---

## Band 4 — Routine (preventive)

### NCD patients only
| Finding | Threshold |
|---------|-----------|
| Pre-hypertension | Systolic 130–139 OR diastolic 85–89 mmHg |
| Pre-diabetes | Fasting glucose 6.1–6.9 mmol/L |

### Default
Any patient with no band-triggering finding (PNC, EPI, nutrition, family planning, cataract, eye care, and patients with no programme).

---

## Pre-eclampsia trend rule (Band 2 ANC)

The pre-eclampsia pattern fires when **all three** of the following are non-decreasing visit-to-visit AND strictly higher at visit 3 than visit 1:

1. Systolic BP
2. Body weight (kg)
3. Urine protein positive at the most recent visit

**Data:** Last 3 ANC assessments per patient, extracted from `local_assessments` by `LocalAssessmentDao._ancTrendSnapshotsForMany()`.

**Conservative:** If any systolic reading is missing, the trend does not fire. Incomplete data never falsely promotes a patient to Band 2.

**Weight optional:** If weight readings are entirely absent, the rule still fires on BP + urine protein alone.

---

## Scheduling vs. clinical priority

Scheduling urgency (how overdue the next visit is) affects the **status pill label** but **not the sort order**.

| Signal | Effect |
|--------|--------|
| `nextDueAt` (or inferred due date) | Sets the status pill: Overdue / Today / This week / Routine |
| Band + modifier | Sets the sort position — entirely independent of the due date |

A Band 1 patient who has a future scheduled visit still shows **"Now"** (red) and appears at the top of the list.

A Band 4 patient who is 10 days overdue shows **"Overdue"** (amber) but still appears at the bottom of the list.

**Due date inference** (when `nextDueAt` is null):

| Programme | Recall interval |
|-----------|----------------|
| ANC / PNC | 14 days |
| TB | 7 days |
| IMCI | 7 days |
| NCD | 30 days |
| EPI | 30 days |
| Family planning | 90 days |

---

## Data flow

```
Cold/warm sync (API → SQLite)
  patients, local_assessments, follow_ups, patient_programmes, …

WorklistRepository.recomputeAllAfterSync()   [runs after every sync]
  → LocalAssessmentDao.latestClinicalVitalsForMany()
       extracts BP, Hb, glucose, GA, parity, danger signs,
       urine, stroke signs from assessmentDetails JSON
  → RiskScoringService.score(PatientFacts)
       worst-finding → Band; modifier signals → Modifier a/b/none
       persists band_wire_tag + modifier_wire_tag + risk_score to patients table

MissionDashboardRepository.loadQueue()
  → reads band / modifier from patients table into WorklistEntry
  → builds MissionInputData (redFlagPatientIds, neonatePatientIds,
       slaBreachedReferralPatientIds, ltfu sets, …)
  → MissionDashboardService.computeTieredQueue(input)
       per patient: _classify() → DashboardTier + driver tags
       deduplicate by patientId (keep worst band)
       sort: band.index ASC → compareInBand()
               (modifier → ANC priority → pregnant-first → name)
       return List<MissionQueueItem>

MissionDashboardScreen
  → groups by tier, selects up to 8 (min 1 / max 3 per tier)
  → re-sorts by tier.rank for section header grouping
  → renders cards with status pill (Now / Overdue / Today / This week / Routine)
```

---

## Dashboard slot allocation (top 8)

The home screen applies a two-pass selection to guarantee tier variety:

| Pass | Rule |
|------|------|
| Pass 1 | Take 1 from each non-empty tier (critical → upcoming) until 8 total |
| Pass 2 | Fill remaining slots rank-first, up to 3 per tier |

After selection, items are re-sorted by `tier.rank` ASC for section header grouping.
Overflow shown as "+ N more" link.

---

## Status pill colour reference

| Pill label | Colour | Dot token | When shown |
|------------|--------|-----------|------------|
| **Now** | Red | `urgency.visitNow` | DashboardTier.critical |
| **Overdue** | Amber | `urgency.today` | DashboardTier.overdue |
| **Today** | Green | `tokens.statusSuccess` | DashboardTier.dueToday |
| **This week** | Teal | `urgency.thisWeek` | DashboardTier.thisWeek |
| **Routine** | Grey | `urgency.routine` | DashboardTier.upcoming |
