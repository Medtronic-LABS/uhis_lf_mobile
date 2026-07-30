/// Pregnancy-outcome `encounter.customStatus` tokens, ported from Android
/// SPICE `AssessmentStatusGenerator` (pregnancyOutcome branch).
///
/// Multiple tokens can coexist (e.g. NORMAL_DELIVERY + LIVE_BIRTH + STILL_BIRTH).
abstract final class PregnancyOutcomeStatus {
  PregnancyOutcomeStatus._();

  static const String abortion = 'ABORTION';
  static const String normalDelivery = 'NORMAL_DELIVERY';
  static const String assistedDelivery = 'ASSISTED_DELIVERY';
  static const String cSection = 'C_SECTION';
  static const String liveBirth = 'LIVE_BIRTH';
  static const String stillBirth = 'STILL_BIRTH';
  static const String neonatalDeath = 'NEONATAL_DEATH';

  /// [details] is the mapper output *before* `_wrapDetailsForType` — i.e. the
  /// map that becomes `assessmentDetails.pregnancyOutcome`.
  static List<String> status(Map<String, dynamic> details) {
    if (details.containsKey('abortion')) {
      return [abortion];
    }

    final out = <String>[];
    final delivery = details['deliveryOutcomes'];
    if (delivery is! Map) return out;

    final mode = delivery['modeOfDelivery']?.toString();
    if (mode == 'normalDelivery') {
      out.add(normalDelivery);
    } else if (mode == 'assistedDelivery') {
      out.add(assistedDelivery);
    } else if (mode == 'cesareanSection') {
      out.add(cSection);
    }

    final live = _asNum(delivery['liveBirthNumbers']) ?? 0;
    final still = _asNum(delivery['stillbirthNumbers']) ?? 0;

    if (live > 0) {
      final newborns = details['newbornDetails'];
      if (newborns is List) {
        final anyDead = newborns.any((baby) {
          if (baby is! Map) return false;
          final alive = baby['isBabyAlive']?.toString().toLowerCase();
          return alive != 'yes';
        });
        if (anyDead) out.add(neonatalDeath);
      }
    }

    if (still > 0) out.add(stillBirth);
    if (live > 0) out.add(liveBirth);
    return out;
  }

  static num? _asNum(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString().trim());
  }
}
