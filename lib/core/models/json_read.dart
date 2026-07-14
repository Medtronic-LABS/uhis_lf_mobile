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
    final ms = epochMillis(json, keys);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String();
  }

  /// Epoch-millis from a date-ish value (ISO String or epoch int/num).
  ///
  /// Tolerates spice / Android formats:
  /// - epoch millis (num or numeric string ≥ 1e12)
  /// - epoch seconds (numeric string 1e9..1e12)
  /// - `yyyy-MM-dd'T'HH:mm:ss[+00:00|Z]`
  /// - `yyyy-MM-dd HH:mm:ss`
  /// - `yyyy-MM-dd`
  /// - `dd-MM-yyyy` / `dd/MM/yyyy` (Android UI display formats)
  static int? epochMillis(Map json, List<String> keys) {
    for (final k in keys) {
      final ms = _epochFromValue(json[k]);
      if (ms != null) return ms;
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
    final ms = _epochFromValue(v);
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

  static int? _epochFromValue(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is num) {
      final n = v.toInt();
      // Heuristic: values that look like epoch seconds vs millis.
      if (n > 1000000000000) return n;
      if (n > 1000000000) return n * 1000;
      return null;
    }
    final s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;

    // Numeric string — only treat as epoch when it looks like one (avoid
    // yyyyMMdd like 20260402 being misread as a tiny epoch).
    final asInt = int.tryParse(s);
    if (asInt != null) {
      if (s.length >= 13 || asInt > 1000000000000) return asInt;
      if (s.length == 10 || (asInt > 1000000000 && asInt < 1000000000000)) {
        return asInt * 1000;
      }
    }

    final parsed = _parseFlexibleDate(s);
    return parsed?.millisecondsSinceEpoch;
  }

  static DateTime? _parseFlexibleDate(String s) {
    final direct = DateTime.tryParse(s);
    if (direct != null) return direct;

    // `yyyy-MM-dd HH:mm:ss(.SSS)` → swap space for T
    if (s.contains(' ') && !s.contains('T')) {
      final swapped = DateTime.tryParse(s.replaceFirst(' ', 'T'));
      if (swapped != null) return swapped;
    }

    // `dd-MM-yyyy` / `dd/MM/yyyy` (± optional time)
    final dmy = RegExp(
      r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})(?:[ T].*)?$',
    ).firstMatch(s);
    if (dmy != null) {
      final day = int.parse(dmy[1]!);
      final month = int.parse(dmy[2]!);
      final year = int.parse(dmy[3]!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }

    // Compact `yyyyMMdd`
    final ymd = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s);
    if (ymd != null) {
      return DateTime(
        int.parse(ymd[1]!),
        int.parse(ymd[2]!),
        int.parse(ymd[3]!),
      );
    }
    return null;
  }

  /// Compact JSON encoding of [json] for the `raw_json` column.
  static String encode(Map json) => jsonEncode(json);
}
