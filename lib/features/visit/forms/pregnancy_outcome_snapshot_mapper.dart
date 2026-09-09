import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../../core/mission/mission_pregnancy_facts.dart';
import '../../../core/models/json_read.dart';
import '../../../core/sync/pregnancy_delivery_sync.dart';
import 'canonical_visit_data.dart';

/// Builds a [PregnancySnapshotRow] from a locally submitted pregnancy-outcome
/// assessment — mirrors Android `savePregnancyOutcomeDetails` plus the
/// `pregnancyInfos[]` row shape applied during initial sync download.
class PregnancyOutcomeSnapshotMapper {
  PregnancyOutcomeSnapshotMapper._();

  /// Maps PO form values onto the episode/snapshot projection, merging with
  /// [existing] obstetric data (LMP, EDD, ANC counters, gravida, etc.).
  static PregnancySnapshotRow fromPoData({
    required String patientId,
    required CanonicalVisitData data,
    PregnancySnapshotRow? existing,
    DateTime? now,
  }) {
    now ??= DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    final flat = data.values;
    final deliveryMs = JsonRead.epochMillis(flat, const [
          'dateOfDelivery',
          'deliveryDate',
        ]) ??
        nowMs;

    final placeOfDelivery = _string(flat['placeOfDelivery']);
    final isHomeDelivery =
        placeOfDelivery?.toLowerCase() == 'home';

    final complications = flat['complicationsDuringDelivery'] ??
        flat['anyComplicationsDuringDelivery'];
    final hadComplications = _hasContent(complications) || isHomeDelivery;

    final existingFacts = existing?.facts ?? PregnancyFacts.empty;
    final isPostpartum =
        PregnancyDeliverySync.isWithinPostpartumWindow(deliveryMs, now);

    final facts = PregnancyFacts(
      highRiskPregnantWoman: existingFacts.highRiskPregnantWoman,
      hasGapsInAnc: existingFacts.hasGapsInAnc,
      isPostpartumWindow: isPostpartum,
      isNearTermAnc: false,
      hadDeliveryComplications: hadComplications,
      hasPncIllness: existingFacts.hasPncIllness,
    );

    final facility = placeOfDelivery != null && !isHomeDelivery
        ? placeOfDelivery
        : null;

    final patch = PregnancySnapshotRow(
      patientId: patientId,
      facts: facts,
      updatedAt: nowMs,
      deliveryDateMillis: deliveryMs,
      facilityIdentifiedForDelivery: facility,
    );

    if (existing == null) return patch;
    return existing.mergedWith(patch);
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }

  static bool _hasContent(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    final s = value.toString().trim();
    if (s.isEmpty || s == '[]' || s == '{}' || s.toLowerCase() == 'none') {
      return false;
    }
    return true;
  }
}
