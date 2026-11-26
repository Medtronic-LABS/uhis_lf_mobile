import 'dart:convert';

/// Reduces a request URL to a form that is safe to store and show in the
/// network log. The rule is shared with the Kotlin SDK through
/// `test/fixtures/net_log/url_sanitizer_vectors.json`; keep the regexes
/// portable (no look-behind).
///
/// Pure and total: never throws, result is at most [maxLength] characters,
/// and `sanitize(sanitize(x)) == sanitize(x)` (the app re-sanitises rows).
///
/// Hosts are trusted and kept verbatim apart from lowercasing and the port
/// rule. Known limitations, accepted by owner decision D1:
/// - digits are counted per path segment, so `/017/123/4567` passes;
/// - opaque tokens without `@`, `;`, a UUID or digits are not masked;
/// - circled or other non-decimal digits do not count as digits.
///
/// The one exception to "opaque tokens are kept" is the value that follows a
/// literal `forgot-password` segment (see [_idParents]): it is typed by a
/// signed-out user and may be a username or an email without an at-sign.
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

  /// Literal path segments whose next segment is always an identifier.
  static const Set<String> _idParents = {'forgot-password'};
  static const int maxInputLength = 8192;
  static const String capMarker = '…';
  static const int _maxDecodePasses = 8;
  static const int _minTotalDigits = 7;
  static const Set<String> _atSigns = {'@', '\uFF20', '\uFE6B'};

  static final RegExp _uuid = RegExp(
    r'[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}',
  );
  static final RegExp _dashlessUuid = RegExp(r'[0-9a-fA-F]{32}');
  static final RegExp _digit = RegExp(r'\p{Nd}', unicode: true);
  static final RegExp _digitRun = RegExp(r'\p{Nd}{6,}', unicode: true);
  static final RegExp _escape = RegExp(r'%[0-9a-fA-F]{2}');
  static final RegExp _trailingEscapes = RegExp(r'(%[0-9a-fA-F]{0,2})+$');
  static final RegExp _trailingIdPrefix = RegExp(r'\{(i|id)?$');

  static String sanitize(String raw) {
    if (raw.length > maxInputLength) return unparsable;
    try {
      // A trailing cap marker from an earlier pass is not data: strip it,
      // sanitise the rest and put it back, so the cap output is a fixed point.
      final hadMarker = raw.endsWith(capMarker);
      final body = _sanitize(
        hadMarker ? raw.substring(0, raw.length - capMarker.length) : raw,
      );
      if (body == unparsable) return unparsable;
      return _cap(body, hadMarker);
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
    final path = _sanitizePath(uri.path);
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

  static String _sanitizePath(String rawPath) {
    final segments = rawPath.split('/');
    final out = <String>[];
    for (var i = 0; i < segments.length; i++) {
      final afterIdParent =
          i > 0 && _idParents.contains(_decodeStable(segments[i - 1]));
      out.add(
        afterIdParent && segments[i].isNotEmpty
            ? idToken
            : _sanitizeSegment(segments[i]),
      );
    }
    return out.join('/');
  }

  static String _sanitizeSegment(String segment) {
    if (segment.isEmpty) return segment;
    final decoded = _decodeStable(segment);
    if (decoded == null || _isSensitive(decoded)) return idToken;
    if (decoded == idToken) return idToken;
    return Uri.encodeComponent(decoded);
  }

  static String? _decodeStable(String value) {
    var current = value;
    try {
      for (var i = 0; i < _maxDecodePasses && current.contains(_escape); i++) {
        current = Uri.decodeComponent(current);
      }
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    return current.contains(_escape) ? null : current;
  }

  static bool _isSensitive(String segment) =>
      _atSigns.any(segment.contains) ||
      segment.contains(';') ||
      _uuid.hasMatch(segment) ||
      _dashlessUuid.hasMatch(segment) ||
      _digitRun.hasMatch(segment) ||
      _digit.allMatches(segment).length >= _minTotalDigits;

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

  static String _cap(String body, bool hadMarker) {
    final combined = hadMarker ? '$body$capMarker' : body;
    if (combined.length <= maxLength) return combined;
    final cut = _dropPartialToken(body.substring(0, maxLength - 1));
    return '$cut$capMarker';
  }

  /// Drops a token the cut split (escape run, `{id`, or a half query pair) so
  /// a second pass over the capped text leaves it unchanged.
  static String _dropPartialToken(String cut) {
    var out = cut
        .replaceFirst(_trailingEscapes, '')
        .replaceFirst(_trailingIdPrefix, '');
    final q = out.indexOf('?');
    if (q >= 0 && !out.endsWith('=$redacted')) {
      final amp = out.lastIndexOf('&');
      out = out.substring(0, amp > q ? amp : q);
    }
    return out;
  }
}
