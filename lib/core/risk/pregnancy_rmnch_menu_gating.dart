import '../db/pregnancy_episode_dao.dart';
import '../db/pregnancy_snapshot_dao.dart';
import 'pregnancy_cohort_rules.dart';

/// Step 1 eligible-services gating aligned with Spice
/// `MetaRepository.setCustomStatus` + `PregnancyCohortRules` (see
/// `Spice-SL/docs/menu-enable-disable-logic.md`).
abstract final class PregnancyRmnchMenuGating {
  PregnancyRmnchMenuGating._();

  /// Spice keeps `memberPregnancyDetail` only when
  /// [PregnancyCohortRules.isRelevantForRmnchMenus] — stale / lapsed /
  /// long-closed pregnancies behave as **no pregnancy** for menu tiles.
  static PregnancyEpisodeRow? episodeForMenus(
    PregnancyEpisodeRow? openEpisode, {
    DateTime? now,
  }) {
    if (openEpisode == null) return null;
    if (!PregnancyCohortRules.isRelevantForRmnchMenus(
      openEpisode.obstetric,
      now: now,
    )) {
      return null;
    }
    return openEpisode;
  }

  /// Spice `getANCPNCStatus` → `RMNCH.ANC` branch (before revisit cadence).
  static bool isAncWorkflow(PregnancySnapshotRow? row, {DateTime? now}) {
    if (row == null) return false;
    if (!PregnancyCohortRules.isRelevantForRmnchMenus(row, now: now)) {
      return false;
    }
    return PregnancyCohortRules.isAncEligible(row, now: now);
  }

  /// Spice `getANCPNCStatus` → `RMNCH.PNC` branch.
  static bool isPncWorkflow(PregnancySnapshotRow? row, {DateTime? now}) {
    if (row == null) return false;
    return PregnancyCohortRules.isPostnatal(row, now: now);
  }

  /// True only when LMP is known, pregnancy is active, and fewer than 6 weeks
  /// have elapsed — **not** for lapsed EDD, delivery, or irrelevant episodes.
  static bool isAncEarlyLmpBlocked(PregnancySnapshotRow? row, {DateTime? now}) {
    if (row == null) return false;
    if (!PregnancyCohortRules.isActivePregnancy(row, now: now)) return false;
    final days = PregnancyCohortRules.daysSinceLmp(row, now: now);
    return days != null && days < PregnancyCohortRules.lmpThresholdDays;
  }

  /// `isPWProfileMenuDisable` — profile re-entry blocked once pregnancy is
  /// far enough along or still in the postnatal window.
  static bool isPwRegistrationLocked(
    PregnancySnapshotRow? relevantObstetric, {
    DateTime? now,
  }) {
    if (relevantObstetric == null) return false;
    final days = PregnancyCohortRules.daysSinceLmp(relevantObstetric, now: now);
    if (days != null && days >= PregnancyCohortRules.postnatalWindowDays) {
      return true;
    }
    return PregnancyCohortRules.isPostnatal(relevantObstetric, now: now);
  }

  /// `isPOMenuDisable` (pregnancy-based leg only — same-day service check
  /// is handled separately if added later).
  static bool isPregnancyOutcomeLocked(
    PregnancySnapshotRow? relevantObstetric, {
    DateTime? now,
  }) {
    if (relevantObstetric == null) return false;
    return PregnancyCohortRules.isPostnatal(relevantObstetric, now: now);
  }

  /// `isFPMenuDisable` (pregnancy-based leg): mid-pregnancy block once LMP ≥
  /// 42 days and no delivery recorded.
  static bool isFamilyPlanningLocked(
    PregnancySnapshotRow? relevantObstetric, {
    DateTime? now,
  }) {
    if (relevantObstetric == null) return false;
    if (relevantObstetric.deliveryDateMillis != null) return false;
    final days = PregnancyCohortRules.daysSinceLmp(relevantObstetric, now: now);
    return days != null && days >= PregnancyCohortRules.postnatalWindowDays;
  }
}
