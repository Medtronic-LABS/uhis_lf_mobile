import '../sync/pregnancy_delivery_sync.dart';
import 'local_assessment_dao.dart';

/// Builds Spice-shaped MAH `observations` JSON from a local assessment row.
abstract final class LocalMahObservations {
  static Map<String, dynamic> build({
    required LocalAssessmentEntity entity,
    required Map<String, dynamic> details,
  }) {
    final base = _baseObservations(entity.assessmentType, details);
    final flat = _flattenDetails(details);
    final out = base != null
        ? Map<String, dynamic>.from(base)
        : <String, dynamic>{};

    final episodeId = entity.pregnancyEpisodeId?.trim();
    if (episodeId != null && episodeId.isNotEmpty) {
      out['pregnancyEpisodeId'] = episodeId;
    }

    void copyString(List<String> keys, String target) {
      if (out[target] != null && '$out[target]'.trim().isNotEmpty) return;
      for (final k in keys) {
        final v = flat[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty && s != 'null') {
          out[target] = v is String ? v : s;
          return;
        }
      }
    }

    void copyDynamic(List<String> keys, String target) {
      if (out.containsKey(target) && out[target] != null) return;
      for (final k in keys) {
        if (flat.containsKey(k) && flat[k] != null) {
          out[target] = flat[k];
          return;
        }
      }
    }

    copyString(const ['lastMenstrualPeriod', 'lastMenstrualPeriodDate', 'lmp', 'lmpDate'], 'lastMenstrualPeriod');
    copyString(const ['estimatedDeliveryDate', 'edd', 'eddDate'], 'estimatedDeliveryDate');
    copyDynamic(const ['gravida'], 'gravida');
    copyDynamic(const ['parity'], 'parity');
    copyDynamic(const ['numberOfLivingChildren', 'livingChildren'], 'numberOfLivingChildren');
    copyDynamic(const ['ageOfLastChild'], 'ageOfLastChild');
    copyDynamic(const ['pregnantWomanExistingIllness'], 'pregnantWomanExistingIllness');
    copyDynamic(const ['pregnantWomanOnTreatment'], 'pregnantWomanOnTreatment');
    copyDynamic(const ['highRiskPregnantWoman'], 'highRiskPregnantWoman');
    copyDynamic(const ['gapsInAnc'], 'gapsInAnc');
    copyDynamic(const ['pncIllness'], 'pncIllness');
    copyDynamic(const ['highRiskMother'], 'highRiskMother');
    copyDynamic(const ['gapsInPnc'], 'gapsInPnc');
    copyDynamic(const ['typeOfAbortion'], 'typeOfAbortion');
    copyDynamic(const ['weight'], 'weight');

    final deliveryMs = PregnancyDeliverySync.deliveryDateMillisFromMap(flat);
    if (deliveryMs != null && !out.containsKey('dateOfDelivery')) {
      out['dateOfDelivery'] =
          DateTime.fromMillisecondsSinceEpoch(deliveryMs).toUtc().toIso8601String();
    } else {
      copyString(const ['dateOfDelivery', 'deliveryDate'], 'dateOfDelivery');
    }

    if (out.isEmpty && episodeId == null) return out;
    return out;
  }

  static Map<String, dynamic>? _baseObservations(
    String assessmentType,
    Map<String, dynamic> details,
  ) {
    final upper = assessmentType.toUpperCase();
    if (details['observations'] is Map) {
      return Map<String, dynamic>.from(details['observations'] as Map);
    }
    if (upper == 'ANC' && details['anc'] is Map) {
      return Map<String, dynamic>.from(details['anc'] as Map);
    }
    if ((upper == 'PWPROFILE' || upper == 'PW_PROFILE') &&
        details['pwProfile'] is Map) {
      return Map<String, dynamic>.from(details['pwProfile'] as Map);
    }
    if ((upper == 'PNC_MOTHER' || upper == 'PNC') && details['pnc'] is Map) {
      return Map<String, dynamic>.from(details['pnc'] as Map);
    }
    return details.isEmpty ? null : Map<String, dynamic>.from(details);
  }

  static Map<String, dynamic> _flattenDetails(Map<String, dynamic> details) {
    final flat = <String, dynamic>{
      for (final e in details.entries) e.key: e.value,
    };
    for (final sub in const [
      'anc',
      'pwProfile',
      'pwprofile',
      'pnc',
      'pncMother',
      'pregnancyOutcome',
      'pregnancyDetails',
      'assessmentDetails',
      'observations',
    ]) {
      final nested = details[sub];
      if (nested is Map) {
        for (final e in nested.entries) {
          flat.putIfAbsent(e.key.toString(), () => e.value);
        }
      }
    }
    final po = details['pregnancyOutcome'];
    if (po is Map) {
      final delivery = po['deliveryOutcomes'];
      if (delivery is Map) {
        for (final e in delivery.entries) {
          flat.putIfAbsent(e.key.toString(), () => e.value);
        }
      }
    }
    return flat;
  }
}
