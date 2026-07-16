/// 5-tier dashboard priority model — drives Mission Dashboard worklist ordering.
///
/// Lower [rank] = more urgent. Strong-driver promotion (red-flag, SLA breach,
/// high-risk pregnancy + gapsInAnc, LTFU streak, plus clinical refinements
/// neonate / young infant / postpartum / near-term ANC / delivery complications /
/// PNC ill / TB default risk / NCD drift / child-with-disability) is applied
/// by the caller in `MissionDashboardService`, not by this enum.
///
/// Spec: leapfrog-setup/designs/dashboard-prioritization.md
library;

import '../time/calendar_day.dart';

/// Dashboard priority tier. Ordered most-urgent → least-urgent.
enum DashboardTier {
  /// Strong-driver hit (red-flag, SLA breach, high-risk pregnancy gap,
  /// neonate / young infant, postpartum, near-term ANC, delivery
  /// complications, PNC illness).
  critical,

  /// Due date ≥ 3 days past today, OR an OVERDUE-min driver fired
  /// (LTFU streak, TB default risk, NCD drift, child-with-disability).
  overdue,

  /// Due today or 1–2 days past.
  dueToday,

  /// Due in 1–7 days.
  thisWeek,

  /// Due > 7 days out, or no due date set.
  upcoming;

  /// Stable urgency rank — lower = more urgent. Backed by enum [index].
  int get rank => index;

  /// Date-only tier mapping. `daysToDue` is positive in the future,
  /// negative when past due. Null means no scheduled due date.
  ///
  ///   `null`   → [upcoming]
  ///   `< -2`   → [overdue]   (3+ days past due)
  ///   `-2..0`  → [dueToday]  (today or 1–2 days past)
  ///   `1..7`   → [thisWeek]
  ///   `> 7`    → [upcoming]
  static DashboardTier fromDaysToDue(int? daysToDue) {
    if (daysToDue == null) return DashboardTier.upcoming;
    if (daysToDue < -2) return DashboardTier.overdue;
    if (daysToDue <= 0) return DashboardTier.dueToday;
    if (daysToDue <= 7) return DashboardTier.thisWeek;
    return DashboardTier.upcoming;
  }

  /// Schedule bucket from [dueAt] using **calendar** days (not wall-clock).
  static DashboardTier fromDueAt(DateTime? dueAt, {DateTime? now}) {
    if (dueAt == null) return DashboardTier.upcoming;
    return fromDaysToDue(CalendarDay.daysBetween(now ?? DateTime.now(), dueAt));
  }

  /// Tasks → Visits tier chips.
  ///
  /// - [critical] / [overdue]: match clinical [itemTier] (includes promotions).
  /// - [dueToday] / [thisWeek] / [upcoming]: match date schedule from [dueAt]
  ///   so e.g. due-in-1–7 still hits **This week** even when promoted to critical.
  static bool matchesVisitFilter({
    required DashboardTier filter,
    required DashboardTier itemTier,
    required DateTime? dueAt,
    DateTime? now,
  }) {
    switch (filter) {
      case DashboardTier.critical:
      case DashboardTier.overdue:
        return itemTier == filter;
      case DashboardTier.dueToday:
      case DashboardTier.thisWeek:
      case DashboardTier.upcoming:
        return fromDueAt(dueAt, now: now) == filter;
    }
  }
}
