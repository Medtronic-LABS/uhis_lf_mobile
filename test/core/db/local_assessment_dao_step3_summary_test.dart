import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/features/visit/forms/visit_summary_details.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;
  late LocalAssessmentDao dao;

  setUp(() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    appDb = AppDatabase.forTesting(raw);
    dao = LocalAssessmentDao(appDb);
  });

  tearDown(() => appDb.close());

  Future<String> insertAnc({required String encounterId}) async {
    final id = 'a-${encounterId.hashCode}';
    await dao.insert(LocalAssessmentEntity(
      id: id,
      householdMemberLocalId: 1,
      patientId: 'p1',
      assessmentType: 'ANC',
      assessmentDetails: '{}',
      otherDetails: jsonEncode({'encounterId': encounterId}),
      syncStatus: AssessmentSyncStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    return id;
  }

  test('pending assessment is syncable before Step 3 (Spice parity)', () async {
    const encounterId = 'enc-1';
    await insertAnc(encounterId: encounterId);

    expect(await dao.getUnsynced(), hasLength(1),
        reason: 'no hold flag — reconnect sync can upload if Step 3 abandoned');
  });

  test('Step 3 merge stamps nextVisitDate onto pending assessment', () async {
    const encounterId = 'enc-2';
    await insertAnc(encounterId: encounterId);

    final date = DateTime.utc(2026, 8, 20);
    final n = await dao.mergeOtherDetailsForEncounter(
      encounterId: encounterId,
      patchFor: (row) => VisitSummaryDetails.patchFor(
        assessmentType: row.assessmentType,
        nextVisitDate: date,
        isReferred: true,
        referralFacilityType: 'Community Clinic',
      ),
    );
    expect(n, 1);

    final ready = await dao.getUnsynced();
    expect(ready, hasLength(1));
    final summary = jsonDecode(ready.single.otherDetails!) as Map;
    expect(summary['nextVisitDate'], '2026-08-20T00:00:00+00:00');
    expect(summary['referralFacilityType'], 'Community Clinic');
    expect(summary['encounterId'], encounterId);
  });
}
