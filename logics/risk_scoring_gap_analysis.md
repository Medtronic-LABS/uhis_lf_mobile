# Gap Analysis — §2.8 AI Risk Scoring & Prioritization (Band + Modifier Model)

Compares the clinical-lead-approved §2.8 spec (Band + Modifier severity model) against the current
`uhis_lf_mobile` implementation. No code changes are made by this document — it is a reference for
review with the clinical lead / team.

---

## 0. Sort-order primacy — documented deviation (open decision, not fixed here)

**Spec:** Band is the primary sort key across the whole worklist:
`1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4`, with pregnancy breaking ties within a band. Band tiers
table is explicit: "Sorted first" (Band 1) → "Sorted last" (Band 4).

**Actual:** date-due tier is primary; Band/Modifier only break ties **within** a tier. This applies to
both live sort paths:
- `WorklistRepository._applySpecSort()` (`lib/features/worklist/worklist_repository.dart`) — order is
  date-tier → band → pregnant → modifier → village-match → name.
- `MissionDashboardService.computeTieredQueue()` + the Home dashboard's round-robin
  (`mission_dashboard_service.dart`, `mission_dashboard_screen.dart`) — groups by `DashboardTier`
  (date-due based, with strong-driver promotion), then within a tier by `priorityScore`
  (= `sortRankFor(band, modifier)`) then name.

**Provenance:** introduced by commits `fbf84ba` / `8154cde` ("date-tier-first sort"). Both carry a
hand-authored commit message ("Sort order change: Primary key: date tier ... Secondary keys within each
tier: band → pregnant → modifier → village → name") but were merged locally with **no PR review and no
design doc** — unlike the earlier band-primary work, which explicitly cited the spec
(`a07ed33 feat(dashboard): PRD §2.8 Band + Modifier risk sort...`, `64ddb56 feat(risk): replace
composite-score RiskBand with spec §2.8 band+modifier model`). The code's own doc-comment quietly
dropped the "§2.8" citation when date-tier-first landed, rather than amending the spec reference.

**Status:** kept as-is per product decision — **needs formal clinical-lead sign-off** that date-urgency
should outrank clinical severity as the top-level sort, since this inverts the spec's literal ordering
(e.g. a Band-3 patient overdue today outranks a Band-1 patient not yet due, under current behaviour).
The likely original motivation — all Band-1 patients clustering at the top regardless of how overdue
they individually are — is a reasonable UX concern, but it isn't written down anywhere as an approved
deviation.

---

## 1. Card border / status pill are not Band-driven at all

**Spec (§2.8.3):** Band1 = Red border / "NOW" pill (pulsing). Band2 = Amber border / "TODAY" pill.
Band3 = Navy border / "TODAY / THIS WEEK" pill. Band4 = Grey border / "ROUTINE" pill.

**Actual:** the card's left border is **always neutral grey** (`mission_queue_card.dart`, with an
explicit comment that urgency is conveyed only via the right-side status pill, not the border). The
pill itself is driven by `DashboardTier` — a 5-value enum, not the spec's 4 bands:

| DashboardTier | Color | Label |
|---|---|---|
| critical | `#EF4444` red | "Today" |
| overdue | `#F59E0B` amber | "Overdue" |
| dueToday | `#10B981` green | "Today" |
| thisWeek | `#0EA5E9` teal | "This week" |
| upcoming | `#6B7280` grey | "Routine" |

The spec's pulsing **"NOW"** label is defined in `app_strings.dart` (`statusPillNow`) but is **never
referenced** anywhere in the pill-rendering code — `critical` renders "Today" instead. Band3's spec
color (navy) doesn't appear in the actual palette at all (`thisWeek` is teal); Band2's spec color
(amber) coincidentally matches `overdue`'s amber, but for an unrelated reason (date lateness, not
clinical severity).

---

## 2. Dashboard's own ordering skips pregnancy and village tie-breaks entirely

The Home dashboard's final visible-card sort — the `visible.sort(...)` call in
`mission_dashboard_screen.dart` — calls `MissionQueueItem.compareInTier()`
(`lib/core/models/mission_queue_item.dart`), which orders by `priorityScore` DESC then patient name.
**No pregnancy check, no village check** — even though `isPregnant` is computed and stamped onto every
`MissionQueueItem` in `computeTieredQueue()`, it is never read by the comparator that actually orders
the visible cards.

The one comparator that *does* implement the spec's intra-band order —
`MissionQueueItem.compareInBand()` (modifier → ANC-over-NCD → pregnant → name) — is **dead code**. Its
only call site is inside `MissionDashboardService.computeQueue()`, which is marked `@Deprecated('Use
computeTieredQueue for the 5-tier model')` and has zero live callers anywhere in `lib/` or `test/`.

Village-match exists only in `WorklistRepository._applySpecSort()` (the general `/patients` worklist
screen) — the Home dashboard path has no village-match concept in its sort at all (the village chip
filter in `mission_dashboard_screen.dart` is a pre-filter, not a tie-break on order).

---

## 3. Three tie-break rules have no backing data model anywhere

| Spec rule | Finding |
|---|---|
| **CCE alert active → ranked first** | No `cce_alert_active` concept exists anywhere in `lib/` for patient-card tie-breaking. The only "CCE" hits are an unrelated referral-list string (`aiSortedTagCce`) and a "CCE integration coming soon" placeholder — neither feeds worklist ordering. |
| **Open referral pending → ranked higher** | Not implemented as a same-band/same-tier tie-break. The closest analog, `referralArrivalPendingPatientIds` (`mission_dashboard_service.dart`), only *promotes a patient's date-tier* to at worst `overdue` — it never reorders patients within a shared band/tier, and only fires for a referred-and-unclosed follow-up ≥3 days old, not any referral with `status = pending`. |
| **Earlier scheduled visit time → ranked higher** | No `visit_scheduled_time` field or scheduling concept exists anywhere in the codebase yet — there's no data model to hang this rule on. |

---

## 4. Modifier `b` has no "longer overdue = higher" magnitude

`Modifier.b` is a flat boolean bucket — `sortRankFor()` (`lib/core/models/risk.dart`) gives it a fixed
`+20` offset regardless of degree. Two same-band patients both flagged modifier-`b` — one 3 days
overdue, one 60 days overdue — sort **identically** today; whatever breaks the tie next (ANC-over-NCD,
pregnancy, name) has nothing to do with lateness. The spec requires this for both ANC (>28 days overdue)
and NCD (>42 days overdue) missed-visit rules.

---

## 5. Pre-eclampsia trend rule is looser than the spec's "all three rising"

**Spec:** BP **and** weight **and** urine protein all rising across 3 visits → Band 2.

**Actual** (`local_assessment_dao.dart`, `_hasEclampsiaTrend` / `_ancTrendSnapshotsForMany`):
- **BP** — correctly a hard AND: all 3 systolic readings required, non-decreasing step-to-step, and
  strictly higher at visit 3 than visit 1. Missing any BP value → rule doesn't fire (conservative).
- **Weight** — only checked **if both** visit-1 and visit-3 weight values are present; if weight data
  is missing entirely, the rule still fires on BP + urine alone (code comment: "weight optional",
  confirmed by `test/core/db/local_assessment_eclampsia_trend_test.dart` — "weight absent... still
  fires").
- **Urine protein** — only requires **positive at the 3rd (latest) visit**; this is a single-visit
  presence check, not a rising trend across visits as the spec specifies.

Net effect: the implemented rule is a **superset** of the spec's intent — it can flag pre-eclampsia
pattern in scenarios (missing weight, or urine protein present only at the latest visit rather than
rising) that the literal spec would not.

---

## 6. Band 4 "may be hidden if SK list > 10 unvisited patients" — not implemented

Exhaustive grep across `lib/` (`band4`, `Band.band4`, `unvisited`, `maxUnvisited`, `routineCap`,
`hideRoutine`, `>10`/`>=10` thresholds) found no count-based hide rule for Band 4 patients anywhere.
All `Band.band4` references are display/sort/priority-mapping only. The only unrelated count/hide
mechanism in the codebase is `MissionDashboardService.hiddenPatientIds` (inactive household members /
same-day-completed follow-ups) — conceptually unrelated to this spec rule.

---

## What already matches the spec closely

- **ANC and NCD clinical threshold tables** (BP / glucose / Hb bands 1–4, from danger signs through
  pre-diabetes/pre-hypertension) are implemented near value-for-value in `risk_scoring_service.dart` —
  this is the most faithfully-implemented part of the spec.
- **Modifier `a` triggers** — primigravida, ANC comorbid diabetes, NCD comorbid HTN+DM, age ≥ 60,
  gestational age ≥ 36 weeks — are all correctly implemented and correctly flagged.
- **Pregnancy-ranks-above-non-pregnant** IS correctly implemented — but only in the general `/patients`
  worklist path (`WorklistRepository._applySpecSort`), not in the Home dashboard path (see §2 above).
  The concept isn't missing from the app; it's just not reused everywhere it should be.

---

## Summary table

| # | Gap | Severity | Where |
|---|---|---|---|
| 0 | Sort order is date-tier-primary, not band-primary | Architectural — needs clinical-lead sign-off | Both sort paths |
| 1 | Card border/pill driven by tier, not band; spec colors/labels don't match | High — visible to every SK, every card | `mission_queue_card.dart`, `tier_header.dart` |
| 2 | Dashboard ordering ignores pregnancy + village; the correct comparator is dead code | High — silently wrong on the one screen SKs use most | `mission_dashboard_screen.dart`, `mission_queue_item.dart` |
| 3 | CCE-alert / referral-pending / scheduled-time tie-breaks have no data model | Medium — no underlying feature exists yet | n/a |
| 4 | Modifier-b has no overdue-magnitude ranking | Medium — clinically meaningful within band | `risk.dart` |
| 5 | Pre-eclampsia trend rule looser than spec (weight optional, urine = single-visit) | Medium — can over-fire vs. spec intent | `local_assessment_dao.dart` |
| 6 | Band4 hide->10-unvisited rule absent | Low — no reports of this being needed yet | n/a |
