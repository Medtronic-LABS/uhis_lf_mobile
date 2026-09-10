/// Lightweight fakes for [UnifiedFormNotifier] dependencies so the AI
/// prefill guard can be unit-tested without a real (SQLCipher) database.
library;

import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/db/patient_dao.dart';
import 'package:uhis_next/core/db/pregnancy_episode_dao.dart';
import 'package:uhis_next/core/db/pregnancy_snapshot_dao.dart';
import 'package:uhis_next/core/telemetry/telemetry_dao.dart';
import 'package:uhis_next/core/telemetry/telemetry_event.dart';
import 'package:uhis_next/core/telemetry/telemetry_service.dart';
import 'package:uhis_next/features/visit/assessment_repository.dart';
import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

/// In-memory [AssessmentDraftDao] capturing the last saved row.
class FakeAssessmentDraftDao implements AssessmentDraftDao {
  AssessmentDraftRow? lastSaved;

  /// Pre-load a row so [getDraft] can restore it (draft round-trip tests).
  void seed(AssessmentDraftRow row) => lastSaved = row;

  @override
  Future<void> saveDraft(AssessmentDraftRow draft) async {
    lastSaved = draft;
  }

  @override
  Future<AssessmentDraftRow?> getDraft(String encounterId) async => lastSaved;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakeAssessmentRepository implements AssessmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakePatientDao implements PatientDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakePregnancySnapshotDao implements PregnancySnapshotDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakePregnancyEpisodeDao implements PregnancyEpisodeDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

/// Captures the telemetry a submit would have emitted, so the notifier's
/// field-provenance classification can be asserted without a database.
///
/// Subclasses [TelemetryService] rather than faking it wholesale so the real
/// payload construction (including the derived `aiFilled` union) still runs.
class CapturingTelemetryService extends TelemetryService {
  CapturingTelemetryService()
      : super(dao: _UnusedTelemetryDao(), userIdResolver: _noUser);

  static Future<int?> _noUser() async => 1;

  VisitCompletedPayload? captured;

  @override
  Future<void> recordVisitCompleted({
    required String visitUuid,
    required List<String> programmes,
    required bool scribeUsed,
    required List<String> aiCorrected,
    required List<String> aiAcceptedUnchanged,
    required List<String> manual,
    required List<String> empty,
    required int libraryTotal,
    required int renderedTotal,
    required int extractableVisible,
    List<String> prefilled = const [],
    List<String> derived = const [],
    List<String> aiOverridden = const [],
    int? durationMs,
    int? scribeStartedAtMs,
    int? scribeEndedAtMs,
    int? manualEditingMs,
    String? outcome,
    Map<String, int>? failureReasons,
    DateTime? occurredAt,
  }) async {
    captured = VisitCompletedPayload(
      programmes: programmes,
      scribeUsed: scribeUsed,
      durationMs: durationMs,
      aiFilled: [...aiCorrected, ...aiAcceptedUnchanged],
      aiCorrected: aiCorrected,
      aiAcceptedUnchanged: aiAcceptedUnchanged,
      manual: manual,
      prefilled: prefilled,
      derived: derived,
      aiOverridden: aiOverridden,
      empty: empty,
      libraryTotal: libraryTotal,
      renderedTotal: renderedTotal,
      extractableVisible: extractableVisible,
      scribeStartedAtMs: scribeStartedAtMs,
      scribeEndedAtMs: scribeEndedAtMs,
      manualEditingMs: manualEditingMs,
      outcome: outcome,
      failureReasons: failureReasons,
    );
  }
}

class _UnusedTelemetryDao implements TelemetryDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('telemetry DAO must not be touched');
}

/// Builds a [UnifiedFormNotifier] wired to fakes — only the draft DAO does
/// real (in-memory) work; the other dependencies throw if touched.
UnifiedFormNotifier buildTestNotifier({
  required FakeAssessmentDraftDao draftDao,
  List<String> activeFormTypes = const ['ncd'],
  TelemetryService? telemetryService,
}) =>
    UnifiedFormNotifier(
      encounterId: 'enc-test',
      patientId: 'pat-test',
      activeFormTypes: activeFormTypes,
      draftDao: draftDao,
      assessmentRepo: _FakeAssessmentRepository(),
      patientDao: _FakePatientDao(),
      pregnancySnapshotDao: _FakePregnancySnapshotDao(),
      pregnancyEpisodeDao: _FakePregnancyEpisodeDao(),
      telemetryService: telemetryService,
    );

/// Lets fire-and-forget `_saveDraft()` futures settle inside a test body.
Future<void> pumpMicrotasks() => Future<void>.delayed(Duration.zero);
