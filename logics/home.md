# Home Screen — Business Logic

Source: `lib/features/dashboard/mission_dashboard_screen.dart`

---

## 1. Initialization

On first render (`initState`), three things happen in sequence via `addPostFrameCallback`:

1. `_reloadStats()` — loads household/member count from local DB (falls back to API if local is empty), then caches the household count into `AuthRepository`.
2. `_loadSummary(auth)` — fetches the SK's user profile (first name, ward, upazila) from `AuthState`.
3. `_loadVillagesLine()` — reads up to 50 households from `HouseholdDao`, collects distinct village names, formats up to 2 names + "+N more" as the header sub-text.
4. `_loadMissionData()` — triggers the queue and referral futures.

---

## 2. Header

### Greeting

Time-based salutation derived from `DateTime.now().hour`:

| Hour | Greeting |
|------|---------|
| 0–11 | Good morning |
| 12–16 | Good afternoon |
| 17–23 | Good evening |

Name resolution order:
1. `UserProfileSummary.firstName` (from API profile)
2. Username portion before `.` or `@` (e.g. `sk1` from `sk1@uhis.localhost`), capitalized
3. Salutation only if neither available

### Location line

Priority order:
1. `ward + " · " + upazila` if both present in user profile
2. `ward` alone
3. `upazila` (or `area`) alone
4. Village names from `HouseholdDao` (formatted as `"Village A · Village B · +1 more"`)
5. Generic fallback string if none of the above resolved

### Referral notification badge

A live badge on the bell icon. Loaded from `ReferralRepository.counts()` which returns `{critical, active}`:

- **Badge count** = `critical + active`
- **Badge color** = red if `critical > 0`, otherwise primary blue
- **Icon** = `notification_important` if critical, else `notifications_outlined`
- Listens to `ReferralRepository.changes` and reloads on any data change.

---

## 3. Settings Menu

| Option | Shown when | Action |
|--------|-----------|--------|
| Enable device unlock | biometricEnabled == false | Offers biometric enrolment dialog; skips if device has no biometric, shows snackbar to set screen lock instead |
| Disable device unlock | biometricEnabled == true | Confirmation dialog → `auth.disableBiometric()` |
| Set PIN | pinEnabled == false | Navigates to `/pin-setup` |
| Remove PIN | pinEnabled == true | Confirmation dialog → `auth.disablePin()` |
| Dark / Light / System mode | always | Cycles through system → dark → light via `ThemeProvider.toggleDarkMode()` |
| Sign out | always | Confirmation dialog → `auth.logout()` → navigate to `/login` |

---

## 4. Stats Row

Two tappable cards side by side, each driven by a `FutureBuilder`.

### Visits today card (left)

- **Value** = `queue.length` (full filtered queue count, not the 8 visible)
- **Subline** = number of distinct villages in the queue (e.g. "3 villages")
- **Tap** → navigates to `/tasks` (full worklist)
- Shows spinner while loading

### Referral alerts card (right)

- **Value** = `referralSummary.breached + referralSummary.awaitingReview`
- **Pulse dot** shown if `hasBreaches` (SLA-breached referrals exist)
- **Tap** → navigates to `/referrals`
- Shows spinner while loading

---

## 5. Village Filter

Single-select horizontal chip row. Chips are built from distinct non-null village names in the current unfiltered queue, sorted alphabetically. Always includes an "All villages" chip.

- Selecting a village chip sets `_selectedVillageChipName` and reloads the queue.
- Selecting the active chip again deselects it (returns to "All").
- Tapping "All villages" clears the selection.
- Village list is re-derived on every queue reload.

---

## 6. Filter by Need

### Which chips are shown — `_computeAvailableNeeds()`

Called on the queue after completed-today patients are excluded. Scans every `MissionQueueItem`
and builds a `Set<_NeedFilter>` of needs that have at least one matching patient. Only needs
with ≥1 match get a chip.

| Chip | Condition on `MissionQueueItem` |
|---|---|
| ⚠️ High-risk | `priority == critical` or `priority == high` |
| 🤰 ANC/MNCH | `programmes` contains `anc` or `pnc` |
| 👶 Child immunisation | `programmes` contains `imci` or `epi` |
| 💊 NCD | `programmes` contains `ncd` |
| 👁️ Eye care | `programmes` contains `eyeCare` or `cataract` |
| ⏰ Missed follow-up | `daysOverdue > 0` |
| 📋 Pending referral | `referralId != null` |

### How filtering works — `_needMatches()`

Multi-select with **OR logic**: a queue item is included if it satisfies **any** selected need.
Selecting no chips shows all patients.

### Data sources

| Field | Source |
|---|---|
| `priority` | `worklist` table — computed by risk-score engine in `WorklistRepository.recomputeAllAfterSync()` |
| `programmes` | `patient_programmes` table — synced from API |
| `daysOverdue` | `worklist` table — derived from `next_due_at` vs today |
| `referralId` | `referrals` table — synced from API |

---

## 7. Today's Visits — Queue Prioritization

### 5-tier model

Every `MissionQueueItem` carries a `DashboardTier`. Tiers in rank order:

| Tier | Patients |
|------|---------|
| T1 — Urgent | Critical priority, SLA breached |
| T2 — High | High priority or SLA due soon |
| T3 — Due today | Follow-up due today |
| T4 — Scheduled | Routine visit planned |
| T5 — Household | Household-level item (no specific patient) |

### Visible slot allocation (max 8 cards shown)

A **round-robin + top-up** algorithm prevents any single tier from occupying all 8 slots.

**Pass 1 — guarantee variety:** walk tiers in rank order, take 1 item per non-empty tier (up to 8 total).

**Pass 2 — fill remaining slots:** walk tiers again rank-first, add more items up to `maxPerTier = 3` per tier until 8 total are filled.

After selection, items are re-sorted by `tier.rank` ASC, then `MissionQueueItem.compareInTier()` (composite score DESC within tier).

### Overflow link

If `queue.length > 8`, a "+ N more visits today" link appears below the cards. It navigates to `/patients?tier=<dominant tier>` where the dominant tier is the tier of the first item not shown.

---

## 8. Queue Card Actions

### Card tap (patient row)

- If `patientId` is valid → navigate to `/patient/:id?origin=dashboard`
- If `referralId` is set (and no valid patientId) → navigate to `/referral/:id`

### Card action button ("Visit now")

Calls `VisitController.startVisit(patientId, programme, name, age, householdId)` which creates an encounter record. On success:
- Navigates to `/patients/visit/:encounterId/triage?origin=dashboard`
- Passes `patientId`, `householdId`, `patientAge` as `extra`

On failure (e.g. no patientId): shows a snackbar error.

---

## 9. Queue Loading Pipeline

```
_loadMissionData()
  ↓ increments _refreshVersion (forces FutureBuilder rebuild)
  ↓ _loadFilteredQueue(missionRepo, encounterDao)
      ↓ encounterDao.completedTodayPatientIds()   → today's visited patient IDs
      ↓ missionRepo.loadQueue(limit: 500)          → full queue
      ↓ exclude completed patients
      ↓ extract village labels                     → _inlineVillages
      ↓ extract available programmes               → _availableProgrammes
      ↓ _computeAvailableNeeds()                   → _availableNeeds
      ↓ apply village chip filter (if active)
      ↓ apply programme filter (if active) — OR logic
      ↓ apply need filter via _needMatches()       — OR logic
      ↓ return filtered List<MissionQueueItem>
  ↓ missionRepo.loadReferralSummary()             → referral stats
```

---

## 10. Data Refresh

### Pull-to-refresh

User swipes down → `_refresh()` → `missionRepo.refresh()` (API sync) → `_onMissionChanges()` fires via `changes` listener → `_loadMissionData()` reloads from local DB. Stats also reload via `_reloadStats()`.

### Change listener

`MissionDashboardRepository.changes` is a `ValueNotifier`. Any repository write (e.g. after assessment completion) fires `_onMissionChanges()`, which:
1. Calls `_loadMissionData()` immediately.
2. Sets `_pendingRefresh = true` in case the widget is off-screen (another tab active).
3. On next `build()`, `_checkPendingRefresh()` clears the flag — the existing `_queueFuture` already holds fresh data so no second load is needed.

---

## 11. Navigation Map

| Trigger | Destination |
|---------|------------|
| Visits stat card tap | `/tasks` |
| Referral stat card tap | `/referrals` |
| Bell icon tap | `/referrals` |
| Patient card tap | `/patient/:id?origin=dashboard` |
| Referral card tap (no patient) | `/referral/:id` |
| "Visit now" action → success | `/patients/visit/:encounterId/triage?origin=dashboard` |
| Overflow link | `/patients?tier=:tier` |
| Sign out confirmed | `/login` |
| Set PIN | `/pin-setup` |
