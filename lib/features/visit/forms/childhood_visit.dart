/// Spice childhood visit (`ChildHood_Visit` / `rmnch_childhood_visit.json`)
/// helpers — age bands, weight ranges, illness option filter, next visit date.
abstract final class ChildhoodVisit {
  ChildhoodVisit._();

  /// Spice `RMNCH.childHoodVisitMaxMonth` — next-visit stamp only through 15 mo.
  static const int maxVisitMonth = 15;

  /// Whole months since [birthDate] (Spice `DateUtils.calculateAgeInMonths`).
  static int ageInMonths(DateTime birthDate, [DateTime? now]) {
    final n = now ?? DateTime.now();
    var months =
        (n.year - birthDate.year) * 12 + (n.month - birthDate.month);
    if (n.day < birthDate.day) months -= 1;
    return months < 0 ? 0 : months;
  }

  /// Valid weight (kg) for childhood visit by age — Spice
  /// `RMNCH.getChildWeightValidationRange`.
  static (double min, double max)? weightRangeKg(int? ageInMonths) {
    if (ageInMonths == null || ageInMonths < 0) return null;
    if (ageInMonths <= 3) return (1.1, 9.0);
    if (ageInMonths <= 6) return (3.0, 12.0);
    if (ageInMonths <= 11) return (4.0, 15.0);
    if (ageInMonths <= 18) return (5.0, 20.0);
    return (6.0, 25.0);
  }

  /// Next childhood follow-up from birth — Spice
  /// `RMNCH.calculateNextChildHoodVisitDate` (first `when` branch wins).
  static DateTime? nextVisitDate({
    required int ageInMonths,
    required DateTime birthDate,
  }) {
    if (ageInMonths < 0 || ageInMonths > maxVisitMonth) return null;
    // Kotlin `in 0..4` matches before `in 4..5`, so age 4 → +5 months.
    if (ageInMonths <= 4) {
      return DateTime(birthDate.year, birthDate.month + 5, birthDate.day);
    }
    if (ageInMonths <= 5) {
      return DateTime(birthDate.year, birthDate.month + 9, birthDate.day);
    }
    if (ageInMonths <= 9) {
      return DateTime(birthDate.year, birthDate.month + 12, birthDate.day);
    }
    if (ageInMonths <= 12) {
      return DateTime(birthDate.year, birthDate.month + 15, birthDate.day);
    }
    return null;
  }

  /// Wire `summary.nextVisitDate` — midnight UTC, Spice `yyyy-MM-dd'T'HH:mm:ssZZZZZ`.
  static String formatNextVisitDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-${d}T00:00:00+00:00';
  }

  /// Illness option `value` codes removed for the child's age — Spice
  /// `AssessmentRMNCHFragment` checkbox filter on `childIllnessType`.
  static Set<String> illnessOptionIdsExcluded(int ageInMonths) {
    if (ageInMonths <= 18) {
      return const {
        'cannotStandWalk',
        'cannotBalance',
        'cannotSpeak',
      };
    }
    return const {
      'convulsion',
      'rapidBreathing',
      'fever',
      'lethargy',
      'unableToSuckMilk',
      'redUmbilicus',
      'skinRash',
      'eyeProblem',
    };
  }

  /// Age-band visibility for childhood-visit fields.
  ///
  /// Returns `null` when [fieldId] is not age-gated (caller falls through).
  /// Matches exclusive `if / else if` in Spice `showHideOptionsForChildHealth`.
  static bool? fieldVisible(String fieldId, int? ageInMonths) {
    const ageGated = {
      'hrsBreastFed',
      'monthAdditionalFeedGiven',
      'childBreastFeeding',
      'additionalFood24Hrs',
      'dewormingMedicine',
      'receivedVaccine',
      'childFeedLast24Hrs',
    };
    if (!ageGated.contains(fieldId)) return null;

    // Without a known age, keep the always-on feed question; hide band extras.
    if (ageInMonths == null) {
      return fieldId == 'childFeedLast24Hrs';
    }

    final age = ageInMonths;
    switch (fieldId) {
      case 'childFeedLast24Hrs':
        return age <= 18;
      case 'hrsBreastFed':
        return age <= 3;
      case 'monthAdditionalFeedGiven':
        // Spice: else if (age > 6) after rejecting age > 11 → months 7–11.
        return age > 6 && age <= 11;
      case 'childBreastFeeding':
      case 'additionalFood24Hrs':
      case 'dewormingMedicine':
        return age > 11;
      case 'receivedVaccine':
        return age > 18;
      default:
        return null;
    }
  }
}
