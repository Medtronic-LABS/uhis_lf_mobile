/// Lightweight fakes for [UnifiedFormNotifier] dependencies so the AI
/// prefill guard can be unit-tested without a real (SQLCipher) database.
library;

import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/db/patient_dao.dart';
import 'package:uhis_next/core/db/pregnancy_snapshot_dao.dart';
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

/// Builds a [UnifiedFormNotifier] wired to fakes — only the draft DAO does
/// real (in-memory) work; the other dependencies throw if touched.
UnifiedFormNotifier buildTestNotifier({
  required FakeAssessmentDraftDao draftDao,
  List<String> activeFormTypes = const ['ncd'],
}) =>
    UnifiedFormNotifier(
      encounterId: 'enc-test',
      patientId: 'pat-test',
      activeFormTypes: activeFormTypes,
      draftDao: draftDao,
      assessmentRepo: _FakeAssessmentRepository(),
      patientDao: _FakePatientDao(),
      pregnancySnapshotDao: _FakePregnancySnapshotDao(),
    );

/// Lets fire-and-forget `_saveDraft()` futures settle inside a test body.
Future<void> pumpMicrotasks() => Future<void>.delayed(Duration.zero);
