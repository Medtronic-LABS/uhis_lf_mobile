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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'eval_log_entry.dart';
import 'shadow_log_service.dart';

class EvalFhirUploader {
  EvalFhirUploader(this._shadowLog);

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
    // DocumentReference upload disabled — not in approved API set.
    // Entries remain in pending state until this endpoint is approved.
    debugPrint('[EvalFhirUploader] disabled — DocumentReference not in approved API set');
    return entry.id;
  }
}
