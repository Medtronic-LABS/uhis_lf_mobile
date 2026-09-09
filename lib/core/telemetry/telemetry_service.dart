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

import '../config/app_config.dart';
import 'telemetry_dao.dart';
import 'telemetry_event.dart';

class TelemetryService {
  TelemetryService({
    required TelemetryDao dao,
    required Future<int?> Function() userIdResolver,
    Uuid uuid = const Uuid(),
  })  : _dao = dao,
        _userIdResolver = userIdResolver,
        _uuid = uuid;

  final TelemetryDao _dao;

  /// Injected rather than depending on `AuthRepository` directly — keeps this
  /// out of the auth layer's dependency graph and makes the service trivially
  /// testable. Wire it to `AuthRepository.userId` at construction.
  final Future<int?> Function() _userIdResolver;

  final Uuid _uuid;

  /// A fresh telemetry-only visit correlator. **Not** the encounter id: it is
  /// never used to look anything up, it exists only so several events from one
  /// visit can be tied together in the report.
  String newVisitUuid() => _uuid.v4();

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
    required int libraryTotal,
    required int renderedTotal,
    required int extractableVisible,
    int? durationMs,
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
      libraryTotal: libraryTotal,
      renderedTotal: renderedTotal,
      extractableVisible: extractableVisible,
    );
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

  Future<void> _insert({
    required String eventType,
    required Map<String, dynamic> payload,
    String? visitUuid,
    DateTime? occurredAt,
  }) async {
    try {
      final userId = await _userIdResolver();
      await _dao.insert(TelemetryEvent(
        id: _uuid.v4(),
        eventType: eventType,
        occurredAt:
            (occurredAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
        visitUuid: visitUuid,
        skUserId: userId?.toString(),
        appVersion: AppConfig.appVersionName,
        appBuild: AppConfig.appVersionCode,
        payloadVersion: kTelemetryPayloadVersion,
        payload: payload,
      ));
    } on Object catch (e, st) {
      // Never rethrow: a lost metric is acceptable, a failed visit is not.
      debugPrint('[Telemetry] $eventType dropped: $e');
      debugPrint('[Telemetry] $st');
    }
  }
}
