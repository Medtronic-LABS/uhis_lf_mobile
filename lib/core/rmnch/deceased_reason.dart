import '../constants/app_strings.dart';

/// Encoded deceased-reason payloads — mirrors Android `RMNCH` + household
/// summary `MemberDeceasedDialogFragment`.
abstract final class DeceasedReason {
  DeceasedReason._();

  static const deathTypeNeonatal = 'neonatal';
  static const deathTypeMother = 'mother';
  static const deathTypeOther = 'other';

  static const prefixNeonatal = '__neonatal__';
  static const prefixMother = '__mother__';

  static const neonateDaysLimit = 28;
  static const motherDeliveryDaysLimit = 50;

  static const neonatalDeathTypeOptions = [
    DeathTypeOption(id: deathTypeNeonatal),
    DeathTypeOption(id: deathTypeOther),
  ];

  static const maternalDeathTypeOptions = [
    DeathTypeOption(id: deathTypeMother),
    DeathTypeOption(id: deathTypeOther),
  ];

  static const neonatalDeathCauseOptions = [
    DeathCauseOption(id: 'asphyxia'),
    DeathCauseOption(id: 'abnormallyLowTemperature'),
    DeathCauseOption(id: 'lowBirthWeight'),
    DeathCauseOption(id: 'convulsions'),
    DeathCauseOption(id: 'prematureBirth'),
    DeathCauseOption(id: 'sepsisUmbilicalSepsis'),
    DeathCauseOption(id: 'pneumonia'),
    DeathCauseOption(id: 'congenitalAnomaly'),
    DeathCauseOption(id: 'unknown'),
  ];

  static const maternalDeathCauseOptions = [
    DeathCauseOption(id: 'excessiveBleeding'),
    DeathCauseOption(id: 'infection'),
    DeathCauseOption(id: 'hypertensiveDisorder'),
    DeathCauseOption(id: 'obstructedLabor'),
    DeathCauseOption(id: 'uterineRupture'),
    DeathCauseOption(id: 'unsafeAbortion'),
    DeathCauseOption(id: 'severeAnemia'),
    DeathCauseOption(id: 'otherMedicalComplications'),
  ];

  /// Builds wire/local payload from dialog selections.
  static String buildPayload({
    required String? typeId,
    required String freeTextReason,
    required List<String> selectedCauseIds,
  }) {
    final trimmed = freeTextReason.trim();
    if (trimmed.isNotEmpty) return trimmed;

    final causes = selectedCauseIds.where((c) => c.isNotEmpty).join(',');
    if (typeId == deathTypeNeonatal) {
      return '$prefixNeonatal:$causes';
    }
    if (typeId == deathTypeMother) {
      return '$prefixMother:$causes';
    }
    return causes;
  }

  /// Human-readable label for household/search UI.
  static String formatForDisplay(String? reason) {
    if (reason == null || reason.trim().isEmpty) return '—';
    final trimmed = reason.trim();
    final parsed = _parseEncoded(trimmed);
    if (parsed == null) return trimmed;

    final labels = parsed.causeIds
        .map((id) => _labelForCause(parsed.type, id))
        .where((s) => s.isNotEmpty)
        .join(', ');
    if (labels.isEmpty) return trimmed;

    final typeLabel = MemberDeceasedStrings.deathTypeLabel(parsed.type);
    return '$typeLabel($labels)';
  }

  static bool isNeonate(String? dobIso) {
    if (dobIso == null || dobIso.isEmpty) return false;
    final dob = DateTime.tryParse(dobIso);
    if (dob == null) return false;
    final today = DateTime.now();
    final ageDays = today
        .difference(DateTime(dob.year, dob.month, dob.day))
        .inDays;
    return ageDays >= 0 && ageDays < neonateDaysLimit;
  }

  static bool isRecentDelivery(int? deliveryDateMillis) {
    if (deliveryDateMillis == null) return false;
    final delivery = DateTime.fromMillisecondsSinceEpoch(deliveryDateMillis);
    final today = DateTime.now();
    final days = today
        .difference(DateTime(delivery.year, delivery.month, delivery.day))
        .inDays;
    return days >= 0 && days <= motherDeliveryDaysLimit;
  }

  static _EncodedReason? _parseEncoded(String reason) {
    final parts = reason.split(':');
    if (parts.length != 2) return null;
    final prefix = parts[0].trim().toLowerCase();
    final type = switch (prefix) {
      '__neonatal__' => deathTypeNeonatal,
      '__mother__' => deathTypeMother,
      _ => null,
    };
    if (type == null) return null;
    final causeIds = parts[1]
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return _EncodedReason(type: type, causeIds: causeIds);
  }

  static String _labelForCause(String type, String id) =>
      MemberDeceasedStrings.deathCauseLabel(id);
}

class DeathTypeOption {
  const DeathTypeOption({required this.id});
  final String id;
  String get label => MemberDeceasedStrings.deathTypeLabel(id);
}

class DeathCauseOption {
  const DeathCauseOption({required this.id});
  final String id;
  String get label => MemberDeceasedStrings.deathCauseLabel(id);
}

class _EncodedReason {
  const _EncodedReason({required this.type, required this.causeIds});
  final String type;
  final List<String> causeIds;
}
