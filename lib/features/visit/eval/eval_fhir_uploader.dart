/// Uploads shadow eval log entries to FHIR as DocumentReferences.
///
/// Each entry becomes a DocumentReference on the unified Encounter with:
///   - status: current
///   - type: LOINC 11488-4 (Consult note) — closest available
///   - meta.tag: {system: "https://uhis.gov.bd/eval", code: "shadow-hint"}
///   - content: base64-encoded JSON of the EvalLogEntry structured data
///   - context.encounter: reference to the encounterId
///
/// The clinical board queries via:
///   GET /fhir/DocumentReference?_tag=https://uhis.gov.bd/eval|shadow-hint
///
/// Called by the offline sync worker when connectivity is restored.
/// Never blocks the assessment flow — errors are logged and retried.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api/endpoints.dart' show Endpoints;
import '../../../core/config/app_config.dart';
import 'eval_log_entry.dart';
import 'shadow_log_service.dart';

/// FHIR programme tag system — same as fhir-mapper convention (D7).
const String _kProgrammeTagSystem = 'https://uhis.gov.bd/program';

/// Eval dataset tag — used by clinical board queries.
const String _kEvalTagSystem = 'https://uhis.gov.bd/eval';
const String _kEvalTagCode = 'shadow-hint';

class EvalFhirUploader {
  EvalFhirUploader(this._httpClient, this._shadowLog);

  final http.Client _httpClient;
  final ShadowLogService _shadowLog;

  /// Upload all pending entries. Called by offline sync worker on reconnect.
  Future<void> uploadPending(String bearerToken) async {
    final pending = await _shadowLog.getPending();
    for (final entry in pending) {
      try {
        final docRefId = await _uploadEntry(entry, bearerToken);
        await _shadowLog.markUploaded(entry.id, docRefId);
      } on http.ClientException catch (_) {
        await _shadowLog.markFailed(entry.id);
      } on Exception catch (_) {
        await _shadowLog.markFailed(entry.id);
      }
    }
  }

  Future<String> _uploadEntry(EvalLogEntry entry, String bearerToken) async {
    final programmes = (jsonDecode(entry.activatedProgrammes) as List)
        .cast<String>();

    final docRef = {
      'resourceType': 'DocumentReference',
      'status': 'current',
      'type': {
        'coding': [
          {'system': 'http://loinc.org', 'code': '11488-4', 'display': 'Consult note'}
        ]
      },
      'meta': {
        'tag': [
          {'system': _kEvalTagSystem, 'code': _kEvalTagCode},
          for (final prog in programmes)
            {'system': _kProgrammeTagSystem, 'code': prog},
        ]
      },
      'subject': {'reference': 'Patient/${entry.patientId}'},
      'context': {
        'encounter': [
          {'reference': 'Encounter/${entry.encounterId}'}
        ]
      },
      'date': entry.capturedAt.toUtc().toIso8601String(),
      'content': [
        {
          'attachment': {
            'contentType': 'application/json',
            'data': base64Encode(utf8.encode(jsonEncode(entry.toDb()))),
            'title': 'eval-shadow-hint',
          }
        }
      ],
    };

    final url = '${AppConfig.apiBaseUrl}${Endpoints.fhirServerBase}/DocumentReference';
    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/fhir+json',
            'Authorization': 'Bearer $bearerToken',
          },
          body: jsonEncode(docRef),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
          'FHIR upload failed: ${response.statusCode}', Uri.parse(url));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['id'] as String? ?? entry.id;
  }
}
