/// Eye care `encounter.customStatus` tokens, ported from Android SPICE
/// `AssessmentStatusGenerator.buildEyeCareStatuses` / its NCD branch.
///
/// Spice emits, in this order: one token per eye problem found, then
/// `GLASSES_SOLD`, then the `GLASS_POWER:<power>` extra token — e.g.
/// `["PRESBYOPIA", "GLASSES_SOLD", "GLASS_POWER:2.0"]`.
abstract final class EyeCareStatus {
  EyeCareStatus._();

  static const String glassesSold = 'GLASSES_SOLD';

  /// Spice `AssessmentDefinedParams.GLASS_POWER_STATUS_PREFIX`.
  static const String glassPowerPrefix = 'GLASS_POWER:';

  static const String noEyeProblem = 'NO_EYE_PROBLEM';

  /// Option id → status token (`mapEyeProblemIdToStatus`). Ids not listed here
  /// contribute no token, exactly as Spice's `else -> null` branch does.
  static const Map<String, String> _problemIdToStatus = {
    'cataracts': 'CATARACTS',
    'lecrimalTearDuctProblem': 'LECRIMAL_TEAR_DUCT_PROBLEM',
    'pterygium': 'PTERYGIUM',
    'glaucoma': 'GLAUCOMA',
    'myopia': 'MYOPIA',
    'presbyopia': 'PRESBYOPIA',
    'otherProblem': 'OTHER_EYE_PROBLEM',
    'noProblem': noEyeProblem,
  };

  /// Builds the customStatus list for an `eyeCare` card body.
  ///
  /// [skipNoProblem] mirrors Spice's NCD branch, which drops `NO_EYE_PROBLEM`
  /// so a clean eye check doesn't dilute the NCD statuses.
  static List<String> status(
    Map<String, dynamic>? eyeCare, {
    bool skipNoProblem = false,
  }) {
    if (eyeCare == null || eyeCare.isEmpty) return const [];

    final out = <String>[];
    for (final id in _problemIds(eyeCare)) {
      if (skipNoProblem && id == 'noProblem') continue;
      final token = _problemIdToStatus[id];
      if (token != null) out.add(token);
    }

    // Spice compares with String.equals(…, ignoreCase = true) against "Yes".
    if (eyeCare['haveTheGlassesBeenSold']?.toString().toLowerCase() == 'yes') {
      out.add(glassesSold);
    }

    final power = eyeCare['glassPower']?.toString().trim();
    if (power != null && power.isNotEmpty) {
      out.add('$glassPowerPrefix$power');
    }
    return out;
  }

  /// `extractEyeProblemIds` — the cataract form stores `eyeDisease`, eye care
  /// stores `eyeTestOutcomes`, and pre-transform drafts may still hold the
  /// singular `eyeTestOutcome`. Entries can be plain ids or `{id: …}` maps.
  static List<String> _problemIds(Map<String, dynamic> section) {
    final ids = <String>[];
    void addAll(dynamic raw) {
      if (raw is! List) return;
      for (final item in raw) {
        if (item is String && item.isNotEmpty) {
          ids.add(item);
        } else if (item is Map && item['id'] is String) {
          ids.add(item['id'] as String);
        }
      }
    }

    addAll(section['eyeDisease']);
    final single = section['eyeTestOutcome'];
    if (single is String && single.trim().isNotEmpty) ids.add(single);
    addAll(section['eyeTestOutcomes']);
    return ids.toSet().toList();
  }
}
