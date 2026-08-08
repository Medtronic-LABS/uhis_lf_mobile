# Patient Card (Home Screen) — Dynamic Information & Data Sources

Widget: `MissionQueueCard` — `lib/features/visit/widgets/mission_queue_card.dart`
Model: `MissionQueueItem` — `lib/core/models/mission_queue_item.dart`
Builder: `MissionDashboardService` — `lib/core/mission/mission_dashboard_service.dart`

---

## Visual anatomy

```
┌─ 4px left border ─────────────────────────────────────────────────┐
│ [Avatar]  Patient Name                            [Action Button] │
│           [Reason Badge]                                           │
│           [Driver Chip]                                            │
│           Age · House #N · Village · Due label                    │
└───────────────────────────────────────────────────────────────────┘
```

---

## 1. Left border color

**What it shows:** urgency tier at a glance.

| Tier | Color token | Meaning |
|------|-------------|---------|
| `critical` | `statusCritical` (red) | Red-flag, neonate, high-risk pregnancy, etc. |
| `overdue` | `statusWarning` (orange) | 3+ days past due, LTFU, NCD drift, TB risk |
| `dueToday` | `statusInfo` (blue) | Due exactly today |
| `thisWeek` | `brandNavy` (navy) | Due within 7 days |
| `upcoming` | `textMuted` (grey) | Due > 7 days out or no due date |

**Source:** `item.tier` — assigned by `MissionDashboardService._classify()`.

**Tier classification logic:**

Critical drivers (any one → `critical`):
- `redFlagPatientIds` or `RiskBand.urgent`
- High-risk pregnant + ANC gaps (`hi-risk-anc-gap`)
- Neonate (under 28 days)
- Young infant (28–60 days)
- Postpartum window (within 42 days)
- Near-term ANC (EDD within 14 days)
- Delivery complications recorded
- PNC illness reported

Overdue-minimum drivers (any one → at least `overdue`):
- Lost-to-follow-up or unsuccessful attempts > 2 (`ltfu-streak`)
- TB treatment default risk (`tb-default-risk`)
- NCD treatment overdue (`ncd-drift`)
- Referral arrival pending ≥ 3 days (`referral-arrival-pending`)
- Child under 5 with disability (`child-disability`)

Date-based fallback (when no strong driver):

| `daysToDue` | Tier |
|------------|------|
| `< -2` | `overdue` |
| `-2` to `0` | `dueToday` |
| `1` to `7` | `thisWeek` |
| `> 7` or null | `upcoming` |

---

## 2. Avatar

**What it shows:** patient initials (2 letters: first + last name initial).
Example: "Fatema Begum" → `FB`

**When visited today:** replaced by a green ✓ checkmark icon.

**Background color:** same as the left border color (at 18% opacity) — tier-matched.

**Source:** `item.patientName` → `_initials(name)` splits on whitespace, takes first char of first and last parts.

---

## 3. Patient name

**What it shows:** full display name.

**When visited today:** shown with strikethrough + muted color + green "Visited" badge pill.

**Card opacity:** 0.6 when completed, 1.0 otherwise.

**Source:** `item.patientName`
- Patient visit → `worklist.displayName` (from `patients` table, synced from API)
- Referral → `"Patient " + referral.patientId.substring(0, 8)` (no name in referral payload)
- Follow-up → `followUp.patientName` (synced from API)

---

## 4. Reason badge

**What it shows:** the primary clinical reason this patient is in the queue. Colored by `MissionPriority`.

| Priority | Badge background | Text color |
|----------|-----------------|-----------|
| `critical` | red at 15% opacity | red |
| `high` | orange at 15% opacity | orange |
| `medium` | navy at 12% opacity | navy |
| `low` | muted surface | muted text |

**Source:** `item.reason`
- Patient visit → `worklist.reasons[0]` (first reason string from worklist entry), or `'Scheduled visit'` if empty
- Referral → `referral.diagnosisLabel` or `'Referral'`
- Follow-up → `followUp.reason` or `'Follow-up due'`

**`MissionPriority`** is derived from `priorityScore`:

| Score threshold | Priority |
|----------------|---------|
| ≥ 80 | `critical` |
| ≥ 50 | `high` |
| ≥ 25 | `medium` |
| < 25 | `low` |

---

## 5. Driver chip

**What it shows:** one-line human-readable explanation of *why* this card landed in its tier. Shows only the first driver tag. Inherits border color from the card's left border.

**Only rendered when** `item.drivers.isNotEmpty`.

**Tag → label mapping** (`MissionDashboardStrings.driverLabel`):

| Tag | Displayed label |
|-----|----------------|
| `sla-breached` | Referral SLA breached |
| `red-flag` | Red-flag patient |
| `hi-risk-anc-gap` | High-risk pregnancy with ANC gap |
| `neonate` | Neonate (under 28 days) |
| `young-infant` | Young infant (under 60 days) |
| `pnc-window` | Postpartum (within 42 days) |
| `anc-near-term` | Near-term pregnancy (EDD within 14 days) |
| `delivery-complication` | Delivery complications recorded |
| `pnc-illness` | Postnatal illness reported |
| `ltfu-streak` | Lost-to-follow-up streak |
| `tb-default-risk` | TB treatment — default risk |
| `ncd-drift` | NCD treatment overdue |
| `referral-arrival-pending` | Referral pending arrival |
| `child-disability` | Child under 5 with disability |
| *(unknown)* | Clinical priority signal |

**Source:** `item.drivers` — list of tag strings assigned by `_classify()` in `MissionDashboardService`.

---

## 6. Subtitle line

**What it shows:** `Age · House #N · Village · Due label` — only non-null parts joined by ` · `.

| Part | Shown when | Source |
|------|-----------|--------|
| `Age X` | `item.age != null` | `worklist.age` or `agesByPatientId` map |
| `House #N` | `item.householdNumber != null` | `householdNumbersById[householdId]` looked up at build time in the service |
| Village name | house number absent AND `item.village != null` | `worklist.householdName` → `villageName` → `villageId` (first non-null) |
| Due label | `item.dueAt != null` | `worklist.nextDueAt` or inferred from programme interval (see below) |

**Due label logic** (`_dueLabel`):

| Days until due | Label |
|---------------|-------|
| 0 | `Due today` |
| > 0 | `Due in Nd` |
| < 0 | `Overdue Nd` |

**Inferred due date** (when `nextDueAt` is null — `_inferDueAt`):

| Programme | Interval |
|-----------|---------|
| ANC / PNC | 14 days from last visit |
| TB | 7 days |
| IMCI | 7 days |
| NCD | 30 days |
| EPI | 30 days |
| Family planning | 90 days |

**Fallback:** if none of the above apply, subtitle shows `item.reason` directly.

---

## 7. Action button

**What it shows:** a pill CTA button. Label and color are driven by tier.

| Tier | Label | Background | Text color |
|------|-------|-----------|-----------|
| `critical` | Visit now | `statusCritical` (red) | white |
| `overdue` | Visit now | `statusCritical` (red) | white |
| `dueToday` | Visit today | `brandNavy` (navy) | white |
| `thisWeek` | Plan visit | `cardSurfaceMuted` | navy |
| `upcoming` | Schedule | `cardSurfaceMuted` | muted |

**When completed:** button is replaced by a green ✓ `check_circle_rounded` icon.
**When `showActionButton = false`** (Tasks screen): button is hidden entirely.

**Tap action:** calls `_startVisitFromQueue(item)` on the dashboard screen → creates an encounter → navigates to `/patients/visit/:encounterId/triage?origin=dashboard`.

---

## 8. Priority score (internal — drives ordering)

Not directly visible on the card but controls which 8 items are shown and their order within a tier.

**Composite score formula** (`_compositeScore`):

```
+ min(daysOverdue, 30) × 3
+ min(unsuccessfulAttempts, 5) × 5
+ (age < 1  → +25)
+ (age < 5  → +12)
+ (age ≥ 60 → +6)
+ (pregnant → +10)
+ (pregnancySnapshot present → +4)
+ (onTreatment → +8)
+ (everReferred → +5)
+ (householdHead → +3)
+ (disability → +6)
+ (lastUpdated stale > 30d → +5)
− min(daysUntilDue, 14)   [future penalty]
```

---

## 9. Item types

Three item types appear in the queue. The card renders identically; behaviour differs:

| Type | `reason` field | Navigation on tap |
|------|---------------|------------------|
| `patientVisit` | From worklist reasons | `/patient/:patientId?origin=dashboard` |
| `referral` | `diagnosisLabel` or 'Referral' | `/referral/:referralId` |
| `followUp` | `followUp.reason` or 'Follow-up due' | `/patient/:patientId?origin=dashboard` |

---

## 10. Data flow summary

```
Cold sync (API → SQLite)
  patients, worklist, referrals, patient_programmes, pregnancyInfos, …

WorklistRepository.recomputeAllAfterSync()
  → risk scores, nextDueAt computed and written to worklist table

MissionDashboardRepository.loadQueue()
  → MissionDashboardService.computeTieredQueue(MissionInputData)
      → _classify()         tier + drivers per patient
      → _compositeScore()   intra-tier ranking score
      → _worklistToQueueItem() / _followUpToQueueItem()
      → dedup by patientId (keep most-urgent tier)
      → sort: tier.rank ASC, priorityScore DESC

DashboardScreen._loadFilteredQueue()
  → exclude completedTodayPatientIds
  → apply village chip filter
  → apply need filter (_needMatches)
  → return filtered List<MissionQueueItem>

FutureBuilder → round-robin 8-slot selection → MissionQueueCard render
```
