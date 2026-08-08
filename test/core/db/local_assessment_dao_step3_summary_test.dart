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

  Future<String> insertAnc({
    required String encounterId,
    bool awaitingSummary = false,
    DateTime? updatedAt,
    String idSuffix = '',
  }) async {
    final id = 'a-${encounterId.hashCode}$idSuffix';
    await dao.insert(LocalAssessmentEntity(
      id: id,
      householdMemberLocalId: 1,
      patientId: 'p1',
      assessmentType: 'ANC',
      assessmentDetails: '{}',
      otherDetails: jsonEncode({
        'encounterId': encounterId,
        if (awaitingSummary) kAwaitingSummaryKey: true,
      }),
      syncStatus: AssessmentSyncStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    ));
    return id;
  }

  test('a held assessment is still visible to Step 3, but not to the push queue',
      () async {
    // Step 2 writes a complete payload, so the row is unsynced and Step 3 must
    // be able to find it to stamp the summary. It must NOT be pushable yet:
    // offline-sync/create has no idempotency key, so once pushed the summary
    // can never be added without duplicating the assessment.
    const encounterId = 'enc-held';
    await insertAnc(encounterId: encounterId, awaitingSummary: true);

    expect(await dao.getUnsynced(), hasLength(1),
        reason: 'forEncounter reads getUnsynced — Step 3 must still match it');
    expect(await dao.forEncounter(encounterId), hasLength(1));

    final pushable = await dao.getUnsyncedForPush();
    expect(pushable.ready, isEmpty,
        reason: 'held rows must not reach the push queue');
    expect(pushable.blocked, isEmpty,
        reason: 'a summary hold is not the same as a blocked identity');
  });

  test('an unheld assessment is syncable immediately', () async {
    // Leaving after Step 2 is a final submission — nothing holds it back once
    // the hold is released or was never set.
    await insertAnc(encounterId: 'enc-free');

    expect(await dao.getUnsynced(), hasLength(1));
  });

  test('Step 3 merge releases the hold, making the row pushable', () async {
    const encounterId = 'enc-release';
    await insertAnc(encounterId: encounterId, awaitingSummary: true);

    final n = await dao.mergeOtherDetailsForEncounter(
      encounterId: encounterId,
      patchFor: (row) => VisitSummaryDetails.patchFor(
        assessmentType: row.assessmentType,
        nextVisitDate: DateTime.utc(2026, 8, 20),
        isReferred: true,
        referralFacilityType: 'Community Clinic',
      ),
    );
    expect(n, 1);

    final ready = await dao.getUnsynced();
    final summary = jsonDecode(ready.single.otherDetails!) as Map;
    expect(summary.containsKey(kAwaitingSummaryKey), isFalse,
        reason: 'stamping the summary is what releases the hold');
    expect(summary['nextVisitDate'], '2026-08-20T00:00:00+00:00');
  });

  test('releaseSummaryHolds by encounter frees every row of that visit',
      () async {
    // One visit writes one assessment row per programme payload — a combined
    // ANC+NCD visit produces several, and they must release together.
    const encounterId = 'enc-multi';
    await insertAnc(
        encounterId: encounterId, awaitingSummary: true, idSuffix: '-1');
    await insertAnc(
        encounterId: encounterId, awaitingSummary: true, idSuffix: '-2');
    await insertAnc(
        encounterId: 'enc-other', awaitingSummary: true, idSuffix: '-3');

    final released = await dao.releaseSummaryHolds(encounterId: encounterId);

    expect(released, 2);
    final pushable = await dao.getUnsyncedForPush();
    expect(pushable.ready.length + pushable.blocked.length, 2,
        reason: 'both rows of this visit release; the other visit stays held');
  });

  test('the stale sweep releases aged holds and leaves fresh ones alone',
      () async {
    // Recovery path for an app killed on Step 3: without it, that assessment
    // would sit out of the push queue forever — worse than the race the hold
    // exists to close.
    await insertAnc(
      encounterId: 'enc-stale',
      awaitingSummary: true,
      updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      idSuffix: '-old',
    );
    await insertAnc(
      encounterId: 'enc-fresh',
      awaitingSummary: true,
      idSuffix: '-new',
    );

    final released =
        await dao.releaseSummaryHolds(olderThan: const Duration(minutes: 30));

    expect(released, 1, reason: 'only the aged hold is reclaimed');
    expect(
      await dao.forEncounter('enc-fresh').then(
          (rows) => LocalAssessmentDao.isAwaitingSummary(rows.single.otherDetails)),
      isTrue,
      reason: 'an SK still working through Step 3 must not be cut short',
    );
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
