import 'dart:convert';

/// Parses backend `customStatus` shapes for assessment-history rows.
///
/// UHIS Gson accepts arrays; offline-sync payloads may also send a JSON string
/// or nest tokens under `encounter.customStatus`.
class CustomStatusParse {
  CustomStatusParse._();

  static List<String> decodeTokens(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const [];
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {}
      return [trimmed];
    }
    final s = raw.toString().trim();
    return s.isEmpty ? const [] : [s];
  }

  /// Top-level `customStatus`, then `encounter.customStatus` (Spice parity).
  static List<String> fromAssessmentHistoryJson(Map<String, dynamic> json) {
    final direct = decodeTokens(json['customStatus']);
    if (direct.isNotEmpty) return direct;
    final encounter = json['encounter'];
    if (encounter is Map) {
      return decodeTokens(encounter['customStatus']);
    }
    return const [];
  }
}
