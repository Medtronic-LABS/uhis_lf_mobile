/// Repository for the AI Next Best Action (NABA) endpoint.
///
/// Calls the Frappe `spice_next_ai` app ([Endpoints.nabaGenerateFrappe]) via
/// [FrappeClient], whose response carries the guideline `citations` and
/// `visuals` the Step 3 picture strip needs. Base URL:
/// [AppConfig.spiceNextAiApiBaseUrl].
///
/// No caching — every call is unique (post-assessment context).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/api/endpoints.dart';
import '../../../core/api/frappe_client.dart';
import '../../../core/debug/console_log.dart';
import 'naba_models.dart';

class NabaRepository {
  const NabaRepository(this._client);

  final FrappeClient _client;

  static const _jsonPretty = JsonEncoder.withIndent('  ');

  /// Throws [FrappeException] when the call fails or the body isn't the
  /// expected envelope — callers fall back to rule-based content.
  Future<NabaResponse> generate(NabaRequest request) async {
    const path = Endpoints.nabaGenerateFrappe;
    final payload = request.toJson();
    ConsoleLog.banner(
      '[PayloadDebug] naba-generate POST ${_client.baseUrl}$path',
    );
    if (kDebugMode) {
      debugPrint('[NABA] request payload:\n${_jsonPretty.convert(payload)}');
    }
    try {
      final raw = await _client.postJson(path, payload);
      if (kDebugMode) {
        debugPrint('[NABA] response body:\n${_jsonPretty.convert(raw)}');
        final visuals = raw['visuals'];
        debugPrint(
          '[NABA] visuals pointers='
          '${visuals is Map ? visuals.keys.toList() : '(none)'}',
        );
      }
      return _parse(raw);
    } on FrappeException catch (e) {
      ConsoleLog.warn('[NABA] generate failed: $e');
      rethrow;
    }
  }

  /// A field of the wrong type surfaces from `fromJson` as a [TypeError];
  /// report it as a bad response so the caller's fallback path handles it.
  NabaResponse _parse(Map<String, dynamic> raw) {
    try {
      return NabaResponse.fromJson(raw);
    } on TypeError catch (e) {
      throw FrappeException(
        FrappeErrorKind.badResponse,
        'Malformed NABA response: $e',
      );
    }
  }
}
