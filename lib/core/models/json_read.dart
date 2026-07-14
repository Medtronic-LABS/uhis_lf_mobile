import 'dart:convert';

/// Tolerant readers for the loosely-typed JSON the spice-service DTOs return.
///
/// Field names vary across endpoints (`firstName`/`givenName`, `householdId`/
/// `houseHoldId`, `nationalId`/`idCode`…). These helpers centralise the
/// coercion so every model parses the same way — one home for the rule
/// (Engineering Design Standards: DRY).
abstract final class JsonRead {
  JsonRead._();

  /// First non-empty string among [keys], trimmed. Returns null if none.
  static String? firstString(Map json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  /// First parseable int among [keys] (accepts int, num, or numeric String).
  static int? firstInt(Map json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n != null) return n;
      }
    }
    return null;
  }

  /// First boolean among [keys] (accepts bool or "true"/"false" String).
  static bool? firstBool(Map json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v is bool) return v;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true') return true;
        if (s == 'false') return false;
      }
    }
    return null;
  }

  /// Composes a display name from first/last parts, falling back to a single
  /// `name`/`fullName` field. Returns null when nothing usable is present.
  static String? composeName(Map json) {
    final first = firstString(json, const ['firstName', 'givenName']);
    final last = firstString(json, const ['lastName', 'familyName']);
    final composed =
        [first, last].where((s) => s != null && s.isNotEmpty).join(' ').trim();
    return composed.isEmpty
        ? firstString(json, const ['name', 'fullName'])
        : composed;
  }

  /// A date-ish value (ISO String, or epoch millis as int/num) normalised to
  /// an ISO-8601 String for stable storage. Returns null when absent/unparsable.
  static String? dateIso(Map json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      if (v is num) {
        return DateTime.fromMillisecondsSinceEpoch(v.toInt()).toIso8601String();
      }
      final s = v.toString().trim();
      if (s.isEmpty) continue;
      final asMillis = int.tryParse(s);
      if (asMillis != null) {
        return DateTime.fromMillisecondsSinceEpoch(asMillis).toIso8601String();
      }
      final parsed = DateTime.tryParse(s);
      if (parsed != null) return parsed.toIso8601String();
    }
    return null;
  }

  /// Epoch-millis from a date-ish value (ISO String or epoch int/num).
  static int? epochMillis(Map json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      if (v is num) return v.toInt();
      final s = v.toString().trim();
      if (s.isEmpty) continue;
      final asMillis = int.tryParse(s);
      if (asMillis != null) return asMillis;
      final parsed = DateTime.tryParse(s);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return null;
  }

  /// Tolerant [DateTime] from a single JSON value (ISO string or epoch ms).
  ///
  /// Prefer this over `DateTime.tryParse(v as String)` — backends often send
  /// LMP / visit dates as epoch ints, which would throw on the String cast.
  static DateTime? asDateTime(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final ms = epochMillis({'_': v}, const ['_']);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// First parseable [DateTime] among [keys] (ISO string or epoch ms).
  static DateTime? firstDateTime(Map json, List<String> keys) {
    for (final k in keys) {
      final d = asDateTime(json[k]);
      if (d != null) return d;
    }
    return null;
  }

  /// Compact JSON encoding of [json] for the `raw_json` column.
  static String encode(Map json) => jsonEncode(json);
}
