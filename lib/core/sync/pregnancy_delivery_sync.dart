import 'dart:convert';

import '../models/json_read.dart';

/// Shared helpers for pregnancy-outcome delivery dates and the 42-day PNC
/// postpartum window — used by offline sync, episode lifecycle, and read-path
/// fallbacks when the snapshot projection is stale.
class PregnancyDeliverySync {
  PregnancyDeliverySync._();

  /// Matches Android `PregnancyCohortRules.isPostnatal` / WHO PNC window.
  static const int postpartumWindowDays = 42;

  static bool isWithinPostpartumWindow(
    int deliveryDateMillis, [
    DateTime? now,
  ]) {
    now ??= DateTime.now();
    final delivery = DateTime.fromMillisecondsSinceEpoch(deliveryDateMillis);
    final days = now.difference(delivery).inDays;
    return days >= 0 && days <= postpartumWindowDays;
  }

  static bool isPregnancyOutcomeType(String? type) {
    if (type == null || type.isEmpty) return false;
    final normalized = type.toUpperCase().replaceAll(' ', '_');
    return normalized == 'PREGNANCY_OUTCOME' ||
        normalized == 'PREGNANCYOUTCOME';
  }

  /// Extracts delivery epoch ms from an assessment-history row, a local draft
  /// payload, or nested `assessmentDetails` (Spice nests under
  /// `pregnancyOutcome.deliveryOutcomes.dateOfDelivery`).
  static int? deliveryDateMillisFromMap(Map<String, dynamic> json) {
    final top = JsonRead.epochMillis(json, const [
      'dateOfDelivery',
      'deliveryDate',
    ]);
    if (top != null) return top;

    final details = json['assessmentDetails'];
    if (details is Map) {
      final fromDetails =
          _extractFromPoDetails(Map<String, dynamic>.from(details));
      if (fromDetails != null) return fromDetails;
    }

    final obs = json['observations'];
    if (obs is Map) {
      final fromObs = JsonRead.epochMillis(
        Map<String, dynamic>.from(obs),
        const ['dateOfDelivery', 'deliveryDate'],
      );
      if (fromObs != null) return fromObs;
    }

    return _extractFromPoDetails(json);
  }

  static int? deliveryDateMillisFromRawJson(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      return deliveryDateMillisFromMap(json);
    } on Object {
      return null;
    }
  }

  static int? _extractFromPoDetails(Map<String, dynamic> details) {
    final po = details['pregnancyOutcome'];
    if (po is Map) {
      final fromPo = _deliveryFromPoBlock(Map<String, dynamic>.from(po));
      if (fromPo != null) return fromPo;
    }
    return _deliveryFromPoBlock(details);
  }

  static int? _deliveryFromPoBlock(Map<String, dynamic> block) {
    final outcomes = block['deliveryOutcomes'];
    if (outcomes is Map) {
      return JsonRead.epochMillis(
        Map<String, dynamic>.from(outcomes),
        const ['dateOfDelivery', 'deliveryDate'],
      );
    }
    return JsonRead.epochMillis(block, const [
      'dateOfDelivery',
      'deliveryDate',
    ]);
  }
}
