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
    DeathTypeOption(id: deathTypeNeonatal, label: 'Neo Natal'),
    DeathTypeOption(id: deathTypeOther, label: 'Other'),
  ];

  static const maternalDeathTypeOptions = [
    DeathTypeOption(id: deathTypeMother, label: 'Maternal'),
    DeathTypeOption(id: deathTypeOther, label: 'Other'),
  ];

  static const neonatalDeathCauseOptions = [
    DeathCauseOption(id: 'asphyxia', label: 'Asphyxia'),
    DeathCauseOption(id: 'abnormallyLowTemperature', label: 'Abnormally low temperature'),
    DeathCauseOption(id: 'lowBirthWeight', label: 'Low birth weight'),
    DeathCauseOption(id: 'convulsions', label: 'Convulsions'),
    DeathCauseOption(id: 'prematureBirth', label: 'Premature birth'),
    DeathCauseOption(id: 'sepsisUmbilicalSepsis', label: 'Sepsis/ Umbilical sepsis'),
    DeathCauseOption(id: 'pneumonia', label: 'Pneumonia'),
    DeathCauseOption(id: 'congenitalAnomaly', label: 'Congenital Anomaly'),
    DeathCauseOption(id: 'unknown', label: 'Unknown'),
  ];

  static const maternalDeathCauseOptions = [
    DeathCauseOption(id: 'excessiveBleeding', label: 'Excessive bleeding'),
    DeathCauseOption(id: 'infection', label: 'Infection'),
    DeathCauseOption(
      id: 'hypertensiveDisorder',
      label: 'Hypertensive disorder (Eclampsia)',
    ),
    DeathCauseOption(id: 'obstructedLabor', label: 'Obstructed labor'),
    DeathCauseOption(id: 'uterineRupture', label: 'Uterine rupture'),
    DeathCauseOption(id: 'unsafeAbortion', label: 'Unsafe abortion'),
    DeathCauseOption(id: 'severeAnemia', label: 'Severe Anemia'),
    DeathCauseOption(
      id: 'otherMedicalComplications',
      label: 'Other medical complications',
    ),
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

    final typeLabel = switch (parsed.type) {
      deathTypeNeonatal => 'Neo Natal',
      deathTypeMother => 'Maternal',
      _ => parsed.type,
    };
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

  static String _labelForCause(String type, String id) {
    final options = type == deathTypeNeonatal
        ? neonatalDeathCauseOptions
        : maternalDeathCauseOptions;
    for (final o in options) {
      if (o.id == id) return o.label;
    }
    return id;
  }
}

class DeathTypeOption {
  const DeathTypeOption({required this.id, required this.label});
  final String id;
  final String label;
}

class DeathCauseOption {
  const DeathCauseOption({required this.id, required this.label});
  final String id;
  final String label;
}

class _EncodedReason {
  const _EncodedReason({required this.type, required this.causeIds});
  final String type;
  final List<String> causeIds;
}
