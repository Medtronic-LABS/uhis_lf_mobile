/// Regression tests for resync duplicates on the pull side.
///
/// A member the SK enrolled offline exists locally under a local PK with no
/// FHIR id, carrying only its `referenceId`. When it comes back from the server
/// on the next pull it arrives with a freshly-assigned FHIR id. If the merge
/// keyed only on `fhirId`, that echo would insert a *second* row and the SK
/// would see the same person twice on the roster — and could assess or immunise
/// against the wrong one.
///
/// [MemberDao.insertOrUpdateFromBE] therefore falls back to matching on
/// `referenceId`. These tests pin that, so the pull side stays sound while the
/// push side (which is where duplicates actually originate — see
/// AssessmentRepository's in-flight handling) is fixed separately.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/member_dao.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;
  late MemberDao dao;

  setUp(() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    appDb = AppDatabase.forTesting(raw);
    dao = MemberDao(appDb);
  });

  tearDown(() => appDb.close());

  Future<int> memberCount() async {
    final rows = await appDb.db.query(AppDatabase.tableMembers);
    return rows.length;
  }

  test('a locally-enrolled member returning with a FHIR id merges, not twins',
      () async {
    // As enrolled offline: local PK, no FHIR id, referenceId set.
    final localId = await dao.insertOrUpdateFromBE(
      HouseholdMemberEntity(
        id: '0',
        referenceId: 'ref-100',
        name: 'Ruma Akter',
        syncStatus: 'NotSynced',
      ),
    );
    expect(await memberCount(), 1);

    // The same person echoed back by the server on the next pull.
    final mergedId = await dao.insertOrUpdateFromBE(
      HouseholdMemberEntity(
        id: '0',
        fhirId: 'fhir-abc',
        referenceId: 'ref-100',
        name: 'Ruma Akter',
      ),
    );

    expect(await memberCount(), 1,
        reason: 'the server echo must merge into the local row, not insert');
    expect(mergedId, localId, reason: 'same local PK is preserved');

    final row = await dao.getByFhirId('fhir-abc');
    expect(row, isNotNull, reason: 'the local row is stamped with the FHIR id');
    expect(row!.id, localId);
  });

  test('a second pull of the same member is idempotent', () async {
    await dao.insertOrUpdateFromBE(
      HouseholdMemberEntity(
          id: '0', fhirId: 'fhir-xyz', referenceId: 'ref-200', name: 'Nazmeen'),
    );
    await dao.insertOrUpdateFromBE(
      HouseholdMemberEntity(
          id: '0', fhirId: 'fhir-xyz', referenceId: 'ref-200', name: 'Nazmeen'),
    );

    expect(await memberCount(), 1,
        reason: 're-pulling an already-merged member must not duplicate it');
  });

  test('genuinely different members are still inserted separately', () async {
    await dao.insertOrUpdateFromBE(
      HouseholdMemberEntity(
          id: '0', fhirId: 'fhir-1', referenceId: 'ref-1', name: 'A'),
    );
    await dao.insertOrUpdateFromBE(
      HouseholdMemberEntity(
          id: '0', fhirId: 'fhir-2', referenceId: 'ref-2', name: 'B'),
    );

    expect(await memberCount(), 2,
        reason: 'dedup must not collapse distinct people');
  });
}
