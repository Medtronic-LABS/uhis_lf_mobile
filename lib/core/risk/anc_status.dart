/// ANC `encounter.customStatus` tokens + referred-reason wire strings, ported
/// from Android SPICE `AssessmentStatusGenerator` (ANC branch) and
/// `ReferralResultGenerator.calculateRMNCHReferralResult`.
abstract final class AncStatus {
  AncStatus._();

  static const String highRiskPw = 'HIGH_RISK_PW';
  static const String normalPregnancy = 'NORMAL_PREGNANCY';
  static const String gapsInAnc = 'GAPS_IN_ANC';

  /// Spice `LABEL_HIGH_RISK_PREGNANT_WOMAN` / `LABEL_GAPS_IN_ANC`.
  static const String reasonHighRisk = 'High risk pregnant woman';
  static const String reasonGaps = 'Gaps in ANC';

  /// Visit-label prefix used by Spice `RMNCH.ANC_VISIT_NO`.
  static const String visitLabelPrefix = 'ANC Visit';

  /// Builds ANC customStatus from the mapper's (unwrapped) details map.
  ///
  /// Spice rules:
  /// - `HIGH_RISK_PW` when `summary.highRiskPregnantWoman` is present,
  ///   otherwise `NORMAL_PREGNANCY`
  /// - `GAPS_IN_ANC` when `summary.gapsInAnc` is present
  static List<String> status(Map<String, dynamic> details) {
    final summary = _summaryOf(details);
    final out = <String>[];
    if (summary != null && summary.containsKey('highRiskPregnantWoman')) {
      out.add(highRiskPw);
    } else {
      out.add(normalPregnancy);
    }
    final gaps = summary?['gapsInAnc'];
    if (gaps is List && gaps.isNotEmpty) {
      out.add(gapsInAnc);
    }
    return out;
  }

  /// Spice referredReasons for an ANC visit.
  ///
  /// - High risk and/or gaps → those labels, with ` - ANC Visit N` appended to
  ///   the last reason (Android `updateVisitCount`).
  /// - Neither → just `"ANC Visit N"` (still sent; patientStatus stays non-referred).
  static List<String> referredReasons({
    required bool hasHighRisk,
    required bool hasGaps,
    Object? visitNo,
  }) {
    final reasons = <String>[
      if (hasHighRisk) reasonHighRisk,
      if (hasGaps) reasonGaps,
    ];
    final visitInfo = visitNo == null || visitNo.toString().trim().isEmpty
        ? visitLabelPrefix.trim()
        : '$visitLabelPrefix $visitNo';
    if (reasons.isEmpty) return [visitInfo];
    reasons[reasons.length - 1] = '${reasons.last} - $visitInfo';
    return reasons;
  }

  static Map<String, dynamic>? _summaryOf(Map<String, dynamic> details) {
    final direct = details['summary'];
    if (direct is Map<String, dynamic>) return direct;
    if (direct is Map) return Map<String, dynamic>.from(direct);
    final nested = details['anc'];
    if (nested is Map) {
      final s = nested['summary'];
      if (s is Map<String, dynamic>) return s;
      if (s is Map) return Map<String, dynamic>.from(s);
    }
    return null;
  }
}
