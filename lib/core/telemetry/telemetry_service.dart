/// Emit API for AI Scribe / counselling telemetry.
///
/// The one rule this class exists to enforce: **telemetry must never break a
/// visit.** Every public method swallows its own failures (logging them) so a
/// full disk, a closed database, or a malformed payload can lose a metric but
/// can never surface an error to an SK mid-consultation, or abort a submit
/// that has real clinical data in it.
///
/// The caller supplies no patient identifiers and this class adds none — see
/// the doc on `telemetry_event.dart` for why the rows are deliberately not
/// patient-linked.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../version/app_version_info.dart';
import 'epi_card_telemetry.dart';
import 'telemetry_dao.dart';
import 'telemetry_event.dart';
import 'assistant_session_recorder.dart';
import 'visit_telemetry_recorder.dart';

class TelemetryService {
  TelemetryService({
    required TelemetryDao dao,
    required Future<int?> Function() userIdResolver,
    Future<int?> Function()? tenantIdResolver,
    Uuid uuid = const Uuid(),
  })  : _dao = dao,
        _userIdResolver = userIdResolver,
        _tenantIdResolver = tenantIdResolver,
        _uuid = uuid;

  final TelemetryDao _dao;

  /// Injected rather than depending on `AuthRepository` directly — keeps this
  /// out of the auth layer's dependency graph and makes the service trivially
  /// testable. Wire it to `AuthRepository.userId` at construction.
  final Future<int?> Function() _userIdResolver;

  /// Tenant of the SK signed in when an event is captured, stamped onto the
  /// row so a backlog uploaded during a *different* tenant's session is still
  /// credited to the tenant that produced it — see
  /// [TelemetryEvent.capturedTenantId]. Optional: when absent the row carries
  /// null and the server falls back to the uploading session's tenant, which
  /// is the behaviour every row had before this existed.
  final Future<int?> Function()? _tenantIdResolver;

  final Uuid _uuid;

  /// One telemetry correlator per encounter for the lifetime of this service.
  ///
  /// The encounter id is never stored in telemetry rows — this map is the only
  /// bridge so visit-content, value-audit and visit_completed share one uuid.
  final Map<String, String> _visitUuidByEncounter = {};

  /// A fresh telemetry-only visit correlator. **Not** the encounter id: it is
  /// never used to look anything up, it exists only so several events from one
  /// visit can be tied together in the report.
  ///
  /// Prefer [ensureVisitUuid] when the uuid must match across telemetry,
  /// value-audit and visit-content for the same encounter.
  String newVisitUuid() => _uuid.v4();

  /// Correlates one EPI card scan-screen session with its attempt/update events.
  String newScanSessionId() => _uuid.v4();

  /// Returns the stable telemetry correlator for [encounterId], minting once.
  String ensureVisitUuid(String encounterId) =>
      _visitUuidByEncounter.putIfAbsent(encounterId, () => _uuid.v4());

  // ── One row per visit ([TelemetryEventType.visit]) ────────────────────────

  final Map<String, VisitTelemetryRecorder> _visitRecorders = {};

  /// Saves run one after another so an older snapshot can never land after
  /// a newer one.
  Future<void> _visitSaves = Future.value();

  /// Starts a new visit row for [encounterId] — called each time the visit
  /// flow opens. Re-opening a draft is a new visit, so this always mints a
  /// fresh correlator and replaces the one [ensureVisitUuid] hands out; every
  /// other visit-scoped stream (visit-content, value-audit, visit_completed)
  /// then joins to this row.
  ///
  /// Saves the initial `in_progress` row straight away, so a visit left
  /// before Step 1 Next is still recorded.
  VisitTelemetryRecorder startVisit(
    String encounterId, {
    int Function()? clock,
  }) {
    final visitUuid = _uuid.v4();
    _visitUuidByEncounter[encounterId] = visitUuid;
    final recorder = VisitTelemetryRecorder(visitUuid: visitUuid, clock: clock);
    _visitRecorders[encounterId] = recorder;
    _visitSaves = _visitSaves.then((_) async {
      try {
        recorder.skUserId = (await _userIdResolver())?.toString();
        recorder.capturedTenantId = await _tenantIdResolver?.call();
      } on Object catch (e) {
        debugPrint('[Telemetry] visit identity not resolved: $e');
      }
    });
    saveVisit(recorder);
    return recorder;
  }

  /// The open visit's recorder for [encounterId], or null outside the visit
  /// flow (e.g. the standalone form route) — every caller treats null as
  /// "nothing to record".
  VisitTelemetryRecorder? visitRecorderFor(String? encounterId) =>
      encounterId == null ? null : _visitRecorders[encounterId];

  /// Same, looked up by the telemetry correlator.
  VisitTelemetryRecorder? visitRecorderByUuid(String? visitUuid) {
    if (visitUuid == null) return null;
    for (final r in _visitRecorders.values) {
      if (r.visitUuid == visitUuid) return r;
    }
    return null;
  }

  /// Writes [recorder]'s current state to its row. The payload is snapshotted
  /// now, synchronously; the write is queued behind earlier saves.
  ///
  /// With a null [recorder] nothing is saved; the returned future completes
  /// once every save already queued has been written.
  Future<void> saveVisit(VisitTelemetryRecorder? recorder) {
    if (recorder == null) return _visitSaves;
    final payload = recorder.toPayload();
    return _visitSaves = _visitSaves.then((_) async {
      try {
        await _dao.upsert(TelemetryEvent(
          id: recorder.visitUuid,
          eventType: TelemetryEventType.visit,
          occurredAt: recorder.visitStartTime,
          visitUuid: recorder.visitUuid,
          skUserId: recorder.skUserId,
          capturedTenantId: recorder.capturedTenantId,
          appVersion: AppVersionInfo.current.versionName,
          appBuild: AppVersionInfo.current.versionCode,
          payloadVersion: kTelemetryPayloadVersion,
          payload: payload,
        ));
      } on Object catch (e) {
        // Never rethrow: a lost metric is acceptable, a failed visit is not.
        debugPrint('[Telemetry] visit row not saved: $e');
      }
    });
  }

  /// Saves [encounterId]'s visit row, if one is open.
  Future<void> saveVisitFor(String? encounterId) =>
      saveVisit(visitRecorderFor(encounterId));

  // ── One row per assistant session ([TelemetryEventType.assistantSession]) ─

  /// Starts a session row for one opening of the patient AI assistant and
  /// saves it straight away, so a session closed without a question is still
  /// counted.
  AssistantSessionRecorder startAssistantSession({
    required String context,
    required String appLanguage,
    bool deceasedContext = false,
    int Function()? clock,
  }) {
    final recorder = AssistantSessionRecorder(
      sessionId: _uuid.v4(),
      context: context,
      appLanguage: appLanguage,
      deceasedContext: deceasedContext,
      clock: clock,
    );
    _visitSaves = _visitSaves.then((_) async {
      try {
        recorder.skUserId = (await _userIdResolver())?.toString();
        recorder.capturedTenantId = await _tenantIdResolver?.call();
      } on Object catch (e) {
        debugPrint('[Telemetry] assistant session identity not resolved: $e');
      }
    });
    saveAssistantSession(recorder);
    return recorder;
  }

  /// Writes [recorder]'s current state to its row — same snapshot-now,
  /// write-in-order rule as [saveVisit], on the same queue. A null
  /// [recorder] just waits for queued saves.
  Future<void> saveAssistantSession(AssistantSessionRecorder? recorder) {
    if (recorder == null) return _visitSaves;
    final payload = recorder.toPayload();
    return _visitSaves = _visitSaves.then((_) async {
      try {
        await _dao.upsert(TelemetryEvent(
          id: recorder.sessionId,
          eventType: TelemetryEventType.assistantSession,
          occurredAt: recorder.sessionStartTime,
          skUserId: recorder.skUserId,
          capturedTenantId: recorder.capturedTenantId,
          appVersion: AppVersionInfo.current.versionName,
          appBuild: AppVersionInfo.current.versionCode,
          payloadVersion: kAssistantSessionPayloadVersion,
          payload: payload,
        ));
      } on Object catch (e) {
        debugPrint('[Telemetry] assistant session row not saved: $e');
      }
    });
  }

  /// The correlator minted for [encounterId], if any.
  String? visitUuidFor(String encounterId) =>
      _visitUuidByEncounter[encounterId];

  /// Records a completed visit — report metrics 1-4.
  ///
  /// [durationMs] is wall-clock and may be null when the encounter row could
  /// not be resolved; the report treats a missing duration as "no sample"
  /// rather than zero.
  Future<void> recordVisitCompleted({
    required String visitUuid,
    required List<String> programmes,
    required bool scribeUsed,
    required List<String> aiCorrected,
    required List<String> aiAcceptedUnchanged,
    required List<String> manual,
    required List<String> empty,
    List<String> prefilled = const [],
    List<String> derived = const [],
    List<String> aiOverridden = const [],
    bool scanUsed = false,
    List<String> scanCorrected = const [],
    List<String> scanAcceptedUnchanged = const [],
    required int libraryTotal,
    required int renderedTotal,
    required int extractableVisible,
    List<String> captureFieldIds = const [],
    int? durationMs,
    int? scribeStartedAtMs,
    int? scribeEndedAtMs,
    int? manualEditingMs,
    String? outcome,
    Map<String, int>? failureReasons,
    DateTime? occurredAt,
  }) async {
    final payload = VisitCompletedPayload(
      programmes: programmes,
      scribeUsed: scribeUsed,
      durationMs: durationMs,
      // Union, computed here so the two lists and the total can never disagree.
      aiFilled: [...aiCorrected, ...aiAcceptedUnchanged],
      aiCorrected: aiCorrected,
      aiAcceptedUnchanged: aiAcceptedUnchanged,
      manual: manual,
      empty: empty,
      prefilled: prefilled,
      derived: derived,
      aiOverridden: aiOverridden,
      scanUsed: scanUsed,
      scanFilled: [...scanCorrected, ...scanAcceptedUnchanged],
      scanCorrected: scanCorrected,
      scanAcceptedUnchanged: scanAcceptedUnchanged,
      libraryTotal: libraryTotal,
      renderedTotal: renderedTotal,
      extractableVisible: extractableVisible,
      captureFieldIds: captureFieldIds,
      scribeStartedAtMs: scribeStartedAtMs,
      scribeEndedAtMs: scribeEndedAtMs,
      manualEditingMs: manualEditingMs,
      outcome: outcome,
      failureReasons: failureReasons,
    );
    // The visit row carries this payload verbatim (existing keys unchanged).
    visitRecorderByUuid(visitUuid)?.recordStep2VisitCompleted(payload.toJson());
    await _insert(
      eventType: TelemetryEventType.visitCompleted,
      payload: payload.toJson(),
      visitUuid: visitUuid,
      occurredAt: occurredAt,
    );
  }

  /// Records a counselling share tap — report metric 5.
  ///
  /// [launched] must be false when the compose sheet could not be opened, so
  /// the report never counts a tap that sent nothing.
  Future<void> recordCounsellingShare({
    required String channel,
    required bool hasMessage,
    required bool launched,
    String surface = TelemetryShareSurface.counselling,
    String? visitUuid,
    DateTime? occurredAt,
  }) async {
    visitRecorderByUuid(visitUuid)?.addShare(
      channel: channel,
      surface: surface,
      hasMessage: hasMessage,
      launched: launched,
    );
    await _insert(
      eventType: TelemetryEventType.counsellingShare,
      payload: CounsellingSharePayload(
        channel: channel,
        surface: surface,
        hasMessage: hasMessage,
        launched: launched,
      ).toJson(),
      visitUuid: visitUuid,
      occurredAt: occurredAt,
    );
  }

  /// Records one patient AI assistant ("Ask") question — LEAP-47.
  ///
  /// Non-PHI only: latency, a within-session repeat flag, and the app
  /// language. The question and answer text are PHI and are never passed here
  /// — they must not enter the telemetry table.
  Future<void> recordEpiCardScanSession({
    required String scanSessionId,
    required String outcome,
    required int attemptCount,
    required int successfulAttemptCount,
    required bool appliedToApp,
    String? visitUuid,
    DateTime? occurredAt,
  }) async {
    await _insertEpiCard(
      eventType: TelemetryEventType.epiCardScanSession,
      payload: epiCardScanSessionPayload(
        scanSessionId: scanSessionId,
        outcome: outcome,
        attemptCount: attemptCount,
        successfulAttemptCount: successfulAttemptCount,
        appliedToApp: appliedToApp,
      ),
      visitUuid: visitUuid,
      occurredAt: occurredAt,
    );
  }

  Future<void> recordEpiCardScanAttempt({
    required String scanSessionId,
    required int attemptIndex,
    required bool success,
    required String failureReason,
    required String engine,
    required int matchedVaccineCount,
    String? captureQuality,
    String? visitUuid,
    DateTime? occurredAt,
  }) async {
    await _insertEpiCard(
      eventType: TelemetryEventType.epiCardScanAttempt,
      payload: epiCardScanAttemptPayload(
        scanSessionId: scanSessionId,
        attemptIndex: attemptIndex,
        success: success,
        failureReason: failureReason,
        engine: engine,
        matchedVaccineCount: matchedVaccineCount,
        captureQuality: captureQuality,
      ),
      visitUuid: visitUuid,
      occurredAt: occurredAt,
    );
  }

  Future<void> recordEpiScanDetection({
    required String scanSessionId,
    required List<String> pendingVaccineKeys,
    required List<String> detectedVaccineKeys,
    String? visitUuid,
    DateTime? occurredAt,
  }) async {
    await _insertEpiCard(
      eventType: TelemetryEventType.epiScanDetection,
      payload: epiScanDetectionPayload(
        scanSessionId: scanSessionId,
        pendingVaccineKeys: pendingVaccineKeys,
        detectedVaccineKeys: detectedVaccineKeys,
      ),
      visitUuid: visitUuid,
      occurredAt: occurredAt,
    );
  }

  Future<void> recordEpiVaccinationUpdate({
    required String vaccineKey,
    required String changeType,
    required bool ocrDetected,
    required bool hadScanPrefill,
    required bool dateChangedFromPrefill,
    required int updateDurationMs,
    required bool ocrAssisted,
    String? scanSessionId,
    String? visitUuid,
    DateTime? occurredAt,
  }) async {
    // A detected dose the SK saved (not one flagged as wrongly marked) is
    // "filled by scan" on the visit row.
    if (ocrDetected && changeType != EpiVaccinationChangeTypeWire.wronglyMarked) {
      visitRecorderByUuid(visitUuid)?.markEpiScanFilled(vaccineKey);
    }
    await _insertEpiCard(
      eventType: TelemetryEventType.epiVaccinationUpdate,
      payload: epiVaccinationUpdatePayload(
        scanSessionId: scanSessionId,
        vaccineKey: vaccineKey,
        changeType: changeType,
        ocrDetected: ocrDetected,
        hadScanPrefill: hadScanPrefill,
        dateChangedFromPrefill: dateChangedFromPrefill,
        updateDurationMs: updateDurationMs,
        ocrAssisted: ocrAssisted,
      ),
      visitUuid: visitUuid,
      occurredAt: occurredAt,
    );
  }

  Future<void> recordAssistantAsk({
    required bool askedAgain,
    required String appLanguage,
    int? generationMs,
    String context = 'patient-scoped',
    bool deceasedContext = false,
    String? correlator,
    DateTime? occurredAt,
  }) async {
    await _insert(
      eventType: TelemetryEventType.assistantAsk,
      payload: AssistantAskPayload(
        askedAgain: askedAgain,
        appLanguage: appLanguage,
        generationMs: generationMs,
        context: context,
        deceasedContext: deceasedContext,
      ).toJson(),
      // The per-ask correlator rides the event's visit_uuid slot — the join
      // key the server uses to attach the gated question/answer content.
      visitUuid: correlator,
      occurredAt: occurredAt,
    );
  }

  Future<void> _insertEpiCard({
    required String eventType,
    required Map<String, dynamic> payload,
    String? visitUuid,
    DateTime? occurredAt,
  }) async {
    await _insert(
      eventType: eventType,
      payload: payload,
      visitUuid: visitUuid,
      occurredAt: occurredAt,
      payloadVersion: kEpiCardTelemetryPayloadVersion,
    );
  }

  Future<void> _insert({
    required String eventType,
    required Map<String, dynamic> payload,
    String? visitUuid,
    DateTime? occurredAt,
    int payloadVersion = kTelemetryPayloadVersion,
  }) async {
    try {
      final userId = await _userIdResolver();
      final tenantId = await _tenantIdResolver?.call();
      await _dao.insert(TelemetryEvent(
        id: _uuid.v4(),
        eventType: eventType,
        occurredAt:
            (occurredAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
        visitUuid: visitUuid,
        skUserId: userId?.toString(),
        capturedTenantId: tenantId,
        appVersion: AppVersionInfo.current.versionName,
        appBuild: AppVersionInfo.current.versionCode,
        payloadVersion: payloadVersion,
        payload: payload,
      ));
    } on Object catch (e, st) {
      // Never rethrow: a lost metric is acceptable, a failed visit is not.
      debugPrint('[Telemetry] $eventType dropped: $e');
      debugPrint('[Telemetry] $st');
    }
  }
}
