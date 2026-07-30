/// Pregnant-woman risk factors, ported from Android SPICE
/// `PregnantWomen.computeRiskFactors` + `AssessmentStatusGenerator`.
///
/// The result drives `encounter.customStatus` on the PWPROFILE assessment:
/// any risk factor at all makes the registration HIGH_RISK_PW, otherwise it is
/// NORMAL_PREGNANCY.
abstract final class PwRiskFactors {
  PwRiskFactors._();

  static const String highRisk = 'HIGH_RISK_PW';
  static const String normalPregnancy = 'NORMAL_PREGNANCY';

  static const int minAgeThreshold = 18;
  static const int maxAgeThreshold = 35;

  /// Android maps each picked option id to a fixed English risk label; the
  /// labels are what the server and the summary screen expect.
  static const Map<String, String> _obstetricRisks = {
    'previousCSection': 'Previous C-section',
    'previousAssistedDelivery': 'Previous Assisted delivery',
    'hoStillBirth': 'H/O still birth',
    'hoMiscarriage': 'H/O miscarriage & abortion',
    'hoInducedAbortion': 'H/O miscarriage & abortion',
    'previousPretermLabour': 'Previous Preterm Labour',
  };

  static const Map<String, String> _medicalComplicationRisks = {
    'excessiveBleedingDuringAfterDelivery':
        'H/O excessive bleeding during/after delivery',
    'bleedingAfter24Weeks2ndTrimester': 'H/O Bleeding after 2nd trimester',
    'preEclampsia': 'H/O Pre-eclampsia/Eclampsia',
    'eclampsia': 'H/O Pre-eclampsia/Eclampsia',
    'gestationalDiabetes': 'H/O GDM',
    'infectionSepsis': 'H/O Infection/Sepsis during pregnancy',
    'severeAnemia': 'H/O Severe Anemia',
  };

  static const Map<String, String> _medicalConditionRisks = {
    'highBloodPressure': 'Known patient of HTN',
    'diabetes': 'Known patient of DM',
    'heartDisease': 'Known patient of Heart Disease',
    'tuberculosis': 'Existing patient of Tuberculosis',
    'asthma': 'Known patient of Asthma',
    'thyroidDisease': 'Known patient of Thyroid disease',
    'epilepsy': 'Known patient of Epilepsy',
    'kidneyDisease': 'Known patient of Kidney Disease',
    'liverDisease': 'Known patient of Liver Disease',
    'autoimmuneDisease': 'Known patient of Autoimmune Disease',
  };

  /// [pregnancyHistory] is the `pregnancyDetailsAndHistory` map (lmp, parity,
  /// livingChildren, ageOfLastChild); [riskScreening] is the optional
  /// `healthRiskScreening` card. The age rules are skipped when
  /// [dateOfBirth] is unknown rather than guessed.
  static List<String> compute({
    required Map<String, dynamic> pregnancyHistory,
    Map<String, dynamic>? riskScreening,
    DateTime? dateOfBirth,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final risks = <String>[];

    final lmp = _asDate(pregnancyHistory['lmp']);
    if (dateOfBirth != null) {
      final ageAtLmp = _wholeYearsBetween(dateOfBirth, lmp ?? today);
      if (ageAtLmp < minAgeThreshold) {
        risks.add('Age <18 years');
      } else if (ageAtLmp > maxAgeThreshold) {
        risks.add('Age >35 years');
      }
    }

    final livingChildren = _asNum(pregnancyHistory['livingChildren']) ?? 0;
    if (livingChildren >= 1) {
      final lastChildDob = _asDate(pregnancyHistory['ageOfLastChild']);
      if (lastChildDob != null &&
          _wholeYearsBetween(lastChildDob, today) < 2) {
        risks.add('Short birth spacing <2 year');
      }
    }

    if ((_asNum(pregnancyHistory['parity']) ?? 0) > 3) {
      risks.add('Multipara >3');
    }

    _addRisks(risks, riskScreening?['obstetricComplications'], _obstetricRisks);
    _addRisks(risks, riskScreening?['medicalComplications'],
        _medicalComplicationRisks);
    _addRisks(risks, riskScreening?['currentMedicalConditions'],
        _medicalConditionRisks);

    return risks;
  }

  /// The `encounter.customStatus` list Android sends for a PW registration.
  static List<String> status({
    required Map<String, dynamic> pregnancyHistory,
    Map<String, dynamic>? riskScreening,
    DateTime? dateOfBirth,
    DateTime? now,
  }) {
    final risks = compute(
      pregnancyHistory: pregnancyHistory,
      riskScreening: riskScreening,
      dateOfBirth: dateOfBirth,
      now: now,
    );
    return [risks.isEmpty ? normalPregnancy : highRisk];
  }

  /// Picked options arrive either as plain ids or as `{value: id}` maps,
  /// depending on whether the answer came from the form or from stored data.
  static void _addRisks(
    List<String> out,
    Object? selected,
    Map<String, String> labels,
  ) {
    if (selected == null) return;
    final items = selected is List ? selected : [selected];
    for (final item in items) {
      final id = item is Map ? item['value']?.toString() : item.toString();
      final label = labels[id?.trim()];
      if (label != null && !out.contains(label)) out.add(label);
    }
  }

  static num? _asNum(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString().trim());
  }

  static DateTime? _asDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw) ??
        (int.tryParse(raw) != null
            ? DateTime.fromMillisecondsSinceEpoch(int.parse(raw))
            : null);
  }

  static int _wholeYearsBetween(DateTime from, DateTime to) {
    var years = to.year - from.year;
    final hadBirthday = to.month > from.month ||
        (to.month == from.month && to.day >= from.day);
    if (!hadBirthday) years -= 1;
    return years;
  }
}
