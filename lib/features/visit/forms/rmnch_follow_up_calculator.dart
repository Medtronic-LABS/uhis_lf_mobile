/// RMNCH next-visit date rules ported from Android `RMNCH.kt` +
/// `AssessmentRMNCHSummaryFragment`.
///
/// Community ANC assessment summary uses a fixed **+28 days** from today.
/// Medical-review ANC uses LMP pregnancy-month bands (`calculateNextANCVisitDate`).
/// PNC summary uses days-since-delivery bands.
abstract final class RmnchFollowUpCalculator {
  RmnchFollowUpCalculator._();

  /// Android `AssessmentRMNCHSummaryFragment.bindAncSummary` —
  /// `DateUtils.getDateAfterDays(28)`.
  static DateTime ancCommunityDefault([DateTime? now]) {
    final base = _dateOnly(now ?? DateTime.now());
    return base.add(const Duration(days: 28));
  }

  /// Android `RMNCH.calculateNextANCVisitDate`.
  ///
  /// Pregnancy "month" ≈ gestational weeks / 4. Community SK path subtracts
  /// 15 days from the month boundary; medical review does not.
  static DateTime? ancFromLmp(
    DateTime lmp, {
    bool isMedicalReview = false,
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final lmpDay = _dateOnly(lmp);
    final days = today.difference(lmpDay).inDays.abs();
    final pregnancyMonth = (days / 7.0) / 4.0;
    final offsetDays = isMedicalReview ? 0 : 15;

    int? monthMultiple;
    if (pregnancyMonth >= 0.0 && pregnancyMonth <= 4.0) {
      monthMultiple = 5;
    } else if (pregnancyMonth >= 4.1 && pregnancyMonth <= 5.0) {
      monthMultiple = 6;
    } else if (pregnancyMonth >= 5.1 && pregnancyMonth <= 6.0) {
      monthMultiple = 7;
    } else if (pregnancyMonth >= 6.1 && pregnancyMonth <= 7.0) {
      monthMultiple = 8;
    } else if (pregnancyMonth >= 7.1 && pregnancyMonth <= 8.9) {
      monthMultiple = 9;
    }
    if (monthMultiple == null) return null;
    return lmpDay.add(Duration(days: (28 * monthMultiple) - offsetDays));
  }

  /// Android `AssessmentRMNCHSummaryFragment.bindPNCSummary` day offsets.
  static DateTime pncFromDaysSinceDelivery(
    int daysSinceDelivery, [
    DateTime? now,
  ]) {
    final base = _dateOnly(now ?? DateTime.now());
    final addDays = switch (daysSinceDelivery) {
      >= 0 && <= 2 => 3,
      >= 3 && <= 6 => 7,
      >= 7 && <= 13 => 14,
      _ => 42,
    };
    return base.add(Duration(days: addDays));
  }

  /// ISO `yyyy-MM-dd` for form [DatePicker] storage.
  static String toFormDate(DateTime date) =>
      _dateOnly(date).toIso8601String().substring(0, 10);

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
