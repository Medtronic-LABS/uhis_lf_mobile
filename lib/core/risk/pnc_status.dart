/// PNC mother `encounter.customStatus` tokens + referred-reason wire strings,
/// ported from Android SPICE `AssessmentStatusGenerator` (PNC branch) and
/// `ReferralResultGenerator.calculateRMNCHReferralResult`.
abstract final class PncStatus {
  PncStatus._();

  static const String highRiskPnc = 'HIGH_RISK_PNC';
  static const String normalPnc = 'NORMAL_PNC';
  static const String gapsInPnc = 'GAPS_IN_PNC';

  /// Spice `LABEL_HIGH_RISK_MOTHER` / `LABEL_GAPS_IN_PNC`.
  static const String reasonHighRisk = 'High risk mother';
  static const String reasonGaps = 'Gaps in PNC';

  /// Visit-label prefix used by Spice `RMNCH.PNC_VISIT_NO`.
  static const String visitLabelPrefix = 'PNC Visit';

  /// Builds PNC customStatus from the mapper's (unwrapped) details map.
  ///
  /// Spice rules:
  /// - `HIGH_RISK_PNC` when `motherRisks` is present, otherwise `NORMAL_PNC`
  /// - `GAPS_IN_PNC` when `pncGaps` is a non-empty list
  static List<String> status(Map<String, dynamic> details) {
    final out = <String>[];
    if (details.containsKey('motherRisks')) {
      out.add(highRiskPnc);
    } else {
      out.add(normalPnc);
    }
    final gaps = details['pncGaps'];
    if (gaps is List && gaps.isNotEmpty) {
      out.add(gapsInPnc);
    }
    return out;
  }

  /// Spice referredReasons for a PNC mother visit.
  ///
  /// - High risk and/or gaps → those labels, with ` - PNC Visit N` on the last
  /// - Neither → just `"PNC Visit N"` (patientStatus stays non-referred)
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

  /// Android `PNCAssessmentEvaluator.getAnemiaLevel` name tokens.
  static String anemiaLevel(double? hemoglobinGdL) {
    if (hemoglobinGdL == null || hemoglobinGdL <= 0) return 'None';
    if (hemoglobinGdL < 8) return 'Severe';
    if (hemoglobinGdL < 10) return 'Moderate';
    if (hemoglobinGdL < 11) return 'Mild';
    return 'None';
  }
}
