/// Emit API for teleconsult patient-consent decisions.
///
/// Same contract as [TelemetryService]: never throws, never blocks the
/// caller. One row per decision, written once when the SK taps Agree or
/// Decline -- unlike the multi-stage visit-content capture, a consent
/// decision is complete in one go.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import 'teleconsult_consent_log_dao.dart';
import 'teleconsult_consent_log_entry.dart';

class TeleconsultConsentLogService {
  TeleconsultConsentLogService({
    required TeleconsultConsentLogDao dao,
    required Future<int?> Function() userIdResolver,
    Future<int?> Function()? tenantIdResolver,
    Uuid uuid = const Uuid(),
  })  : _dao = dao,
        _userIdResolver = userIdResolver,
        _tenantIdResolver = tenantIdResolver,
        _uuid = uuid;

  final TeleconsultConsentLogDao _dao;
  final Future<int?> Function() _userIdResolver;
  final Future<int?> Function()? _tenantIdResolver;
  final Uuid _uuid;

  /// Records one Agree/Decline decision on the teleconsult consent gate.
  ///
  /// Never throws and never gated behind a feature flag -- unlike
  /// [AssistantContentService], this is a compliance audit record, not
  /// optional usage telemetry, so it must always be attempted and must never
  /// delay the Agree/Decline navigation that triggers it.
  Future<void> record({
    required String patientId,
    String? visitId,
    required bool agreed,
    required String lng,
    String? consentVersion,
    String? versionId,
    String? patientDob,
    DateTime? occurredAt,
  }) async {
    try {
      final at = (occurredAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
      final userId = (await _userIdResolver())?.toString();
      final tenantId = await _tenantIdResolver?.call();
      await _dao.upsert(TeleconsultConsentLogEntry(
        id: _uuid.v4(),
        patientId: patientId,
        visitId: visitId,
        decision: agreed
            ? TeleconsultConsentDecision.agreed
            : TeleconsultConsentDecision.declined,
        lng: lng,
        consentVersion: consentVersion,
        versionId: versionId,
        patientDob: patientDob,
        skUserId: userId,
        capturedTenantId: tenantId,
        occurredAt: at,
      ));
    } on Object catch (e, st) {
      debugPrint('[TeleconsultConsentLog] capture dropped: $e');
      debugPrint('[TeleconsultConsentLog] $st');
    }
  }
}
