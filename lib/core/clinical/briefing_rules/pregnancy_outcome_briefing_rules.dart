/// Deterministic Pregnancy Outcome clinical findings for the "Before You
/// Knock" briefing. Pure function — reads directly from the raw
/// `local_assessments.assessment_details` JSON produced by
/// `UnifiedPayloadMapper._toPregnancyOutcome`.
///
/// Only ever called for the most-recent PREGNANCY_OUTCOME record, and only
/// when the caller has already confirmed the patient is currently in the
/// postpartum window with a real delivery date (see
/// `BriefingFindingsAggregator`'s gating) — otherwise a stale delivery from
/// long ago would keep surfacing "healthy delivery" forever.
///
/// NOTE: a recorded maternal death is deliberately not given its own message
/// here — the rule table this implements only covers stillbirth/neonatal
/// death, abortion, and healthy live birth. A maternal-death outcome simply
/// won't match any of the three branches below (never miscategorized as
/// "healthy"), but nothing is emitted for it — flag for a follow-up rule
/// once one is specified.
library;

import '../../../features/visit/forms/form_config.dart';
import '../../constants/app_strings.dart';
import 'clinical_finding.dart';

List<ClinicalFinding> evaluatePregnancyOutcomeFindings({
  required Map<String, dynamic>? latest,
}) {
  if (latest == null) return const [];

  final deliveryOutcomes =
      (latest['deliveryOutcomes'] as Map?)?.cast<String, dynamic>();
  final abortion = (latest['abortion'] as Map?)?.cast<String, dynamic>();
  final newbornDetails =
      (latest['newbornDetails'] as List?)?.cast<Map>().cast<Map<String, dynamic>>();
  final firstNewborn =
      newbornDetails != null && newbornDetails.isNotEmpty ? newbornDetails.first : null;

  final outcome = deliveryOutcomes?['deliveryOutcome'] as String?;
  final stillbirthNumbers = _int(deliveryOutcomes?['stillbirthNumbers']) ?? 0;
  final isBabyAlive = _boolOrNull(firstNewborn?['isBabyAlive']);

  final isStillbirth = outcome == 'stillbirth' || stillbirthNumbers > 0;
  final isNeonatalDeath = isBabyAlive == false;

  if (isStillbirth || isNeonatalDeath) {
    return [
      ClinicalFinding(
        code: 'pregnancyOutcome.stillbirthOrNeonatalDeath',
        message: ClinicalFindingStrings.pregnancyOutcomeStillbirthOrNeonatalDeath,
        programme: 'pregnancyOutcome',
      ),
    ];
  }

  final abortionType = abortion?['typeOfAbortion'] as String?;
  if (abortionType != null && abortionType.isNotEmpty) {
    return [
      ClinicalFinding(
        code: 'pregnancyOutcome.abortion',
        message: ClinicalFindingStrings.pregnancyOutcomeAbortion(
            _resolveAbortionTypeLabel(abortionType)),
        programme: 'pregnancyOutcome',
      ),
    ];
  }

  final hasComplications =
      deliveryOutcomes?['anyComplicationsDuringDelivery'] == 'Yes';
  if (outcome == 'liveBirth' && isBabyAlive != false && !hasComplications) {
    return [
      ClinicalFinding(
        code: 'pregnancyOutcome.healthy',
        message: ClinicalFindingStrings.pregnancyOutcomeHealthy,
        programme: 'pregnancyOutcome',
      ),
    ];
  }

  return const [];
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool? _boolOrNull(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  if (s == 'yes' || s == 'true') return true;
  if (s == 'no' || s == 'false') return false;
  return null;
}

String _resolveAbortionTypeLabel(String code) {
  try {
    final options = FormConfig.instance.fields['typeOfAbortion']?.options ?? const [];
    final option = FieldOption.find(code, options);
    if (option != null) return option.displayName;
  } on Object {
    // FormConfig not loaded yet — degrade to the raw code rather than throw.
  }
  return code;
}
