import '../db/pregnancy_snapshot_dao.dart';

/// Live-derived pregnancy-episode state, ported from Android Spice's
/// `PregnancyCohortRules` (`ui/assessment/rmnch/PregnancyCohortRules.kt`).
///
/// Unlike `PregnancyFacts.isPostpartumWindow` (a boolean baked in at sync
/// time from server `pregnancyInfos[]`), these functions compute state fresh
/// against [now] from the locally-tracked [PregnancySnapshotRow] dates, so
/// gating decisions don't go stale between syncs. Android additionally checks
/// `typeOfAbortion` when closing a pregnancy; [PregnancySnapshotRow] has no
/// equivalent field, so `deliveryDateMillis` is the only "pregnancy ended"
/// signal available here.
abstract final class PregnancyCohortRules {
  PregnancyCohortRules._();

  /// Android `OVERDUE_GRACE_DAYS`.
  static const int overdueGraceDays = 45;

  /// Android `POSTNATAL_WINDOW_DAYS`.
  static const int postnatalWindowDays = 42;

  /// True while the pregnancy is still open: LMP known, no delivery
  /// recorded, and EDD (if known) isn't more than [overdueGraceDays] days in
  /// the past.
  static bool isActivePregnancy(PregnancySnapshotRow? row, {DateTime? now}) {
    if (row == null) return false;
    if (row.lmpDate == null) return false;
    if (row.deliveryDateMillis != null) return false;
    final eddMs = row.eddDate;
    if (eddMs == null) return true;
    final cutoff =
        (now ?? DateTime.now()).subtract(const Duration(days: overdueGraceDays));
    return DateTime.fromMillisecondsSinceEpoch(eddMs).isAfter(cutoff);
  }

  /// True while delivery was recorded within the last [postnatalWindowDays]
  /// days.
  static bool isPostnatal(PregnancySnapshotRow? row, {DateTime? now}) {
    final deliveryMs = row?.deliveryDateMillis;
    if (deliveryMs == null) return false;
    final cutoff = (now ?? DateTime.now())
        .subtract(const Duration(days: postnatalWindowDays));
    return !DateTime.fromMillisecondsSinceEpoch(deliveryMs).isBefore(cutoff);
  }

  /// Days since LMP, or `null` when LMP is unknown.
  static int? daysSinceLmp(PregnancySnapshotRow? row, {DateTime? now}) {
    final lmpMs = row?.lmpDate;
    if (lmpMs == null) return null;
    return (now ?? DateTime.now())
        .difference(DateTime.fromMillisecondsSinceEpoch(lmpMs))
        .inDays;
  }

  /// Days since delivery, or `null` when no delivery has been recorded.
  static int? daysSinceDelivery(PregnancySnapshotRow? row, {DateTime? now}) {
    final deliveryMs = row?.deliveryDateMillis;
    if (deliveryMs == null) return null;
    return (now ?? DateTime.now())
        .difference(DateTime.fromMillisecondsSinceEpoch(deliveryMs))
        .inDays;
  }
}
