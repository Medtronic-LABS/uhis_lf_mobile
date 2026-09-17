import '../../../core/constants/app_strings.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import 'form_config.dart';

/// ANC `pregnantWomanExistingIllness` / `pregnantWomanOnTreatment` option ids
/// (`field_library.json`).
abstract final class AncExistingIllness {
  AncExistingIllness._();

  static const List<FieldOption> options = [
    FieldOption(
      id: 'htn',
      name: 'HTN',
      cultureValue: 'উচ্চ রক্তচাপ',
    ),
    FieldOption(
      id: 'dm',
      name: 'DM',
      cultureValue: 'ডায়াবেটিস',
    ),
    FieldOption(
      id: 'heartDisease',
      name: 'Heart Disease',
      cultureValue: 'হৃদরোগ',
    ),
    FieldOption(
      id: 'tuberculosis',
      name: 'Tuberculosis',
      cultureValue: 'যক্ষ্মা',
    ),
    FieldOption(
      id: 'asthma',
      name: 'Asthma',
      cultureValue: 'হাঁপানি',
    ),
    FieldOption(
      id: 'kidneyDisease',
      name: 'Kidney Disease',
      cultureValue: 'কিডনি রোগ',
    ),
    FieldOption(
      id: 'thyroidDisease',
      name: 'Thyroid disease',
      cultureValue: 'থাইরয়েড রোগ',
    ),
    FieldOption(
      id: 'none',
      name: 'None',
      cultureValue: 'কোনো রোগ নাই',
    ),
  ];

  static const FieldOption notTakingTreatment = FieldOption(
    id: 'none',
    name: 'Not taking any treatment',
    cultureValue: 'কোনো চিকিৎসা গ্রহণ করছেন না',
  );

  static String labelOf(FieldOption option) => getTranslatedString(
        'VisitFlow.ancExistingIllness.${option.id}',
        option.displayName,
      );

  static String onTreatmentLabelOf(FieldOption option) {
    if (option.id == 'none') {
      return getTranslatedString(
        'VisitFlow.ancOnTreatment.none',
        notTakingTreatment.displayName,
      );
    }
    return labelOf(option);
  }

  static String labelOfId(String wireId) {
    if (wireId.trim().toLowerCase() == 'none') {
      return labelOf(
        options.firstWhere((o) => o.id == 'none'),
      );
    }
    final option = FieldOption.find(wireId, options);
    if (option != null) return labelOf(option);
    return wireId;
  }

  static String onTreatmentLabelOfId(String wireId) {
    if (wireId.trim().toLowerCase() == 'none') {
      return onTreatmentLabelOf(notTakingTreatment);
    }
    final option = FieldOption.find(wireId, options);
    if (option != null) return onTreatmentLabelOf(option);
    return wireId;
  }

  /// Maps a pregnancy-snapshot JSON list (or comma-separated legacy string).
  static String formatExistingIllnessList(String? encoded) =>
      _formatList(encoded, labelOfId);

  static String formatOnTreatmentList(String? encoded) =>
      _formatList(encoded, onTreatmentLabelOfId);

  static String _formatList(
    String? encoded,
    String Function(String id) labelOf,
  ) {
    final items = _expandItems(PregnancySnapshotRow.decodeJsonList(encoded));
    if (items.isEmpty) return '';
    return items.map(labelOf).join(', ');
  }

  static List<String> _expandItems(List<String>? decoded) {
    if (decoded == null || decoded.isEmpty) return const [];
    if (decoded.length == 1 && decoded.first.contains(',')) {
      return decoded.first
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return decoded;
  }
}
