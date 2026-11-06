import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/db/assessment_dao.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/features/visit/assessment_repository.dart';

class _FakeLocalDao extends Fake implements LocalAssessmentDao {
  _FakeLocalDao(this._byPatient);

  final Map<String, List<LocalAssessmentEntity>> _byPatient;

  @override
  Future<List<LocalAssessmentEntity>> getByPatientId(String patientId) async =>
      _byPatient[patientId] ?? const [];
}

class _FakeHistoryDao extends Fake implements AssessmentDao {
  _FakeHistoryDao(this._byPatient);

  final Map<String, List<AssessmentRow>> _byPatient;

  @override
  Future<Map<String, List<AssessmentRow>>> forMany(
    List<String> patientIds,
  ) async =>
      {for (final id in patientIds) id: _byPatient[id] ?? const []};
}

class _FakeApi extends Fake implements ApiClient {}

class _FakeAuth extends Fake implements AuthRepository {}

LocalAssessmentEntity _local(String id, String type) => LocalAssessmentEntity(
      id: id,
      householdMemberLocalId: 1,
      assessmentType: type,
      assessmentDetails: '{}',
    );

AssessmentRow _history(String id, String patientId, String kind) =>
    AssessmentRow(id: id, patientId: patientId, kind: kind, rawJson: '{}');

AssessmentRepository _repo({
  Map<String, List<LocalAssessmentEntity>> local = const {},
  Map<String, List<AssessmentRow>> history = const {},
}) =>
    AssessmentRepository(
      dao: _FakeLocalDao(local),
      api: _FakeApi(),
      auth: _FakeAuth(),
      historyDao: _FakeHistoryDao(history),
    );

void main() {
  group('AssessmentRepository.priorNcdVisitCount', () {
    test('is zero for an empty patient id', () async {
      expect(await _repo().priorNcdVisitCount(''), 0);
    });

    test('counts local NCD rows and synced NCD history', () async {
      final repo = _repo(
        local: {
          'p1': [_local('l1', 'NCD'), _local('l2', 'ANC')],
        },
        history: {
          'p1': [_history('h1', 'p1', 'NCD'), _history('h2', 'p1', 'ANC')],
        },
      );
      expect(await repo.priorNcdVisitCount('p1'), 2);
    });

    test('finds a visit filed only under the alternate id', () async {
      final repo = _repo(
        history: {
          'member-pk': [_history('h1', 'member-pk', 'NCD')],
        },
      );
      expect(await repo.priorNcdVisitCount('patient-id'), 0);
      expect(
        await repo.priorNcdVisitCount('patient-id', alsoId: 'member-pk'),
        1,
      );
    });

    test('counts a row returned under both ids once', () async {
      final shared = _local('l1', 'NCD');
      final repo = _repo(
        local: {
          'patient-id': [shared],
          'member-pk': [shared],
        },
      );
      expect(
        await repo.priorNcdVisitCount('patient-id', alsoId: 'member-pk'),
        1,
      );
    });
  });
}
