import 'dart:convert';

/// Reduces a request URL to a form that is safe to store and show in the
/// network log. The rule is shared with the Kotlin SDK through
/// `test/fixtures/net_log/url_sanitizer_vectors.json`; keep the regexes
/// portable (no look-behind).
///
/// Pure and total: never throws, result is at most [maxLength] characters.
abstract final class UrlSanitizer {
  static const int maxLength = 2048;
  static const String unparsable = '<unparsable>';
  static const String idToken = '{id}';
  static const String redacted = '<redacted>';

  static const Set<String> _schemes = {'http', 'https', 'ws', 'wss'};
  static const Map<String, int> _defaultPorts = {
    'http': 80,
    'https': 443,
    'ws': 80,
    'wss': 443,
  };
  static const Set<String> _queryAllowlist = {
    '_count',
    '_lang',
    'encounter',
    'key',
    'language',
    'model',
    'since',
    'limit',
    'offset',
    'cursor',
    'from_date',
    'to_date',
  };
  static const int _maxDecodePasses = 3;

  static final RegExp _uuid = RegExp(
    r'[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}',
  );
  static final RegExp _phoneLike = RegExp(
    r'^\+?[\p{Nd} ()\-.]{7,}$',
    unicode: true,
  );
  static final RegExp _digit = RegExp(r'\p{Nd}', unicode: true);
  static final RegExp _digitRun = RegExp(r'\p{Nd}{6,}', unicode: true);
  static const int _phoneMinDigits = 7;

  static String sanitize(String raw) {
    try {
      return _cap(_sanitize(raw));
    } on Object {
      // Total by contract: any unforeseen failure yields the marker.
      return unparsable;
    }
  }

  static String _sanitize(String raw) {
    final uri = Uri.tryParse(_percentEncodeNonAscii(raw));
    if (uri == null ||
        !_schemes.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      return unparsable;
    }
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final authority = host.contains(':') ? '[$host]' : host;
    final port = uri.hasPort && uri.port != _defaultPorts[scheme]
        ? ':${uri.port}'
        : '';
    final path = uri.path.split('/').map(_sanitizeSegment).join('/');
    final query = _sanitizeQuery(uri.query);
    return '$scheme://$authority$port$path${query.isEmpty ? '' : '?$query'}';
  }

  /// `Uri.tryParse` rejects raw non-ASCII; encode it so such paths still
  /// reach the per-segment rule (Bengali digits count towards the 6+ run).
  static String _percentEncodeNonAscii(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune < 0x80) {
        buffer.writeCharCode(rune);
      } else {
        for (final byte in utf8.encode(String.fromCharCode(rune))) {
          buffer.write('%${byte.toRadixString(16).toUpperCase()}');
        }
      }
    }
    return buffer.toString();
  }

  static String _sanitizeSegment(String segment) {
    if (segment.isEmpty) return segment;
    final decoded = _decodeStable(segment);
    if (decoded == null || _isSensitive(decoded)) return idToken;
    return Uri.encodeComponent(decoded);
  }

  static String? _decodeStable(String value) {
    var current = value;
    try {
      for (var i = 0; i < _maxDecodePasses && current.contains('%'); i++) {
        final next = Uri.decodeComponent(current);
        if (next == current) break;
        current = next;
      }
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    return current;
  }

  static bool _isSensitive(String segment) {
    if (segment.contains('@') ||
        _uuid.hasMatch(segment) ||
        _digitRun.hasMatch(segment)) {
      return true;
    }
    return _phoneLike.hasMatch(segment) &&
        _digit.allMatches(segment).length >= _phoneMinDigits;
  }

  static String _sanitizeQuery(String rawQuery) {
    if (rawQuery.isEmpty) return '';
    final seen = <String>{};
    final out = <String>[];
    try {
      for (final pair in rawQuery.split('&')) {
        if (pair.isEmpty) continue;
        final eq = pair.indexOf('=');
        final rawKey = eq < 0 ? pair : pair.substring(0, eq);
        final key = Uri.decodeQueryComponent(rawKey);
        if (_queryAllowlist.contains(key) && seen.add(key)) {
          out.add('$key=$redacted');
        }
      }
    } on FormatException {
      return '';
    } on ArgumentError {
      return '';
    }
    return out.join('&');
  }

  static String _cap(String value) => value.length <= maxLength
      ? value
      : '${value.substring(0, maxLength - 1)}…';
}
