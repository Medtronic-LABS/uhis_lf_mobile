import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/assessment_dao.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/db/member_assessment_history_dao.dart';
import 'package:uhis_next/core/db/member_assessment_history_writer.dart';
import 'package:uhis_next/core/db/member_dao.dart';
import 'package:uhis_next/core/db/spice_dashboard_dao.dart';
import 'package:uhis_next/core/models/assessment_history_item.dart';

/// LEAP-128: a visit saved on the device and later pulled back from
/// member-assessment-history must be one dashboard row, not two.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase app;
  late MemberAssessmentHistoryWriter writer;

  setUp(() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
        singleInstance: false,
      ),
    );
    app = AppDatabase.forTesting(db);
    writer = MemberAssessmentHistoryWriter(
      mah: MemberAssessmentHistoryDao(app),
      members: MemberDao(app),
      appDb: app,
    );
  });

  tearDown(() => app.db.close());

  final visitAt = DateTime.utc(2026, 11, 20, 9, 30, 15, 123);

  LocalAssessmentEntity localVisit({
    String id = 'la-1',
    int reference = 1,
    String clientVisitId = 'client-visit-1',
    String type = 'ANC',
    DateTime? at,
    String? fhirId,
    String? customStatus,
  }) =>
      LocalAssessmentEntity(
        id: id,
        referenceId: reference,
        householdMemberLocalId: 7,
        memberId: 'member-fhir-1',
        assessmentType: type,
        assessmentDetails: '{}',
        otherDetails: jsonEncode({'encounterId': clientVisitId}),
        customStatus: customStatus,
        createdAt: at ?? visitAt,
        syncStatus: fhirId == null
            ? AssessmentSyncStatus.pending
            : AssessmentSyncStatus.success,
        fhirId: fhirId,
      );

  /// The server's copy: uploaded with whole-second precision.
  AssessmentHistoryItem serverVisit({
    String encounterId = 'server-enc-1',
    String service = 'ANC',
    DateTime? at,
    List<String> customStatus = const [],
  }) {
    final t = at ?? visitAt;
    return AssessmentHistoryItem(
      householdMemberId: 'member-fhir-1',
      encounterId: encounterId,
      visitDate:
          DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second),
      serviceProvided: service,
      customStatus: customStatus,
    );
  }

  Future<List<Map<String, Object?>>> mahRows() =>
      app.db.query(MemberAssessmentHistoryDao.tableName, orderBy: 'id');

  Future<void> saveLocal(LocalAssessmentEntity e) async {
    await app.db.insert(LocalAssessmentDao.tableName, e.toDb());
    await writer.upsertFromLocal(e, projectPregnancy: false);
  }

  test('visit saved, uploaded, then pulled back is one row (server copy)',
      () async {
    await saveLocal(localVisit());
    await app.db.update(
      LocalAssessmentDao.tableName,
      {'fhir_id': 'server-enc-1', 'sync_status': 'success'},
    );
    await writer.upsertFromHistoryItems([serverVisit()]);
    // Every dashboard load re-merges local_assessments.
    await writer.rebuildFromLocalAssessments();

    final rows = await mahRows();
    expect(rows, hasLength(1));
    expect(rows.single['encounter_id'], 'server-enc-1');
  });

  test(
      'matches on member + service + visit second when no server id was '
      'stamped on the local row', () async {
    await saveLocal(localVisit());
    await writer.upsertFromHistoryItems([serverVisit()]);
    await writer.rebuildFromLocalAssessments();

    final rows = await mahRows();
    expect(rows, hasLength(1));
    expect(rows.single['encounter_id'], 'server-enc-1');
  });

  test(
      'a device that already has the duplicate heals on the next dashboard '
      'rebuild', () async {
    // State written by the old code: both copies of one visit.
    final local = localVisit(fhirId: 'server-enc-1');
    await app.db.insert(LocalAssessmentDao.tableName, local.toDb());
    await app.db.insert(MemberAssessmentHistoryDao.tableName, {
      'member_id': 7,
      'member_fhir_id': 'member-fhir-1',
      'visit_date': visitAt.toIso8601String(),
      'service_provided': 'anc',
      'encounter_id': 'client-visit-1',
      'latest_visit': 1,
    });
    await app.db.insert(MemberAssessmentHistoryDao.tableName, {
      'member_fhir_id': 'member-fhir-1',
      'visit_date': '2026-11-20T09:30:15.000Z',
      'service_provided': 'anc',
      'encounter_id': 'server-enc-1',
      'latest_visit': 1,
    });
    await AssessmentDao(app).upsertMany([
      AssessmentRow(
        id: 'server-enc-1',
        patientId: 'member-fhir-1',
        kind: 'ANC',
        occurredAt:
            DateTime.utc(2026, 11, 20, 9, 30, 15).millisecondsSinceEpoch,
        rawJson: jsonEncode({'householdMemberId': 'member-fhir-1'}),
      ),
    ]);
    expect(await mahRows(), hasLength(2));

    // Same order as SkSpiceDashboardRepository.load().
    await writer.rebuildFromAssessmentsTable();
    await writer.rebuildFromLocalAssessments();

    final rows = await mahRows();
    expect(rows, hasLength(1));
    expect(rows.single['encounter_id'], 'server-enc-1');
  });

  test('a visit not yet synced still counts', () async {
    await saveLocal(localVisit());
    await writer.rebuildFromLocalAssessments();

    final rows = await mahRows();
    expect(rows, hasLength(1));
    expect(rows.single['encounter_id'], 'client-visit-1');
  });

  test('two real visits by the same member stay two rows', () async {
    final later = visitAt.add(const Duration(days: 30));
    await saveLocal(localVisit());
    await saveLocal(localVisit(
      id: 'la-2',
      reference: 2,
      clientVisitId: 'client-visit-2',
      at: later,
    ));
    await writer.upsertFromHistoryItems([
      serverVisit(),
      serverVisit(encounterId: 'server-enc-2', at: later),
    ]);
    await writer.rebuildFromLocalAssessments();

    final ids = (await mahRows()).map((r) => r['encounter_id']).toSet();
    expect(ids, {'server-enc-1', 'server-enc-2'});
  });

  test('one visit covering two programmes keeps one row per service',
      () async {
    await saveLocal(localVisit());
    await saveLocal(
        localVisit(id: 'la-2', reference: 2, type: 'FAMILY_PLANNING'));
    await writer.upsertFromHistoryItems([
      serverVisit(),
      serverVisit(encounterId: 'server-enc-fp', service: 'family_planning'),
    ]);
    await writer.rebuildFromLocalAssessments();

    final rows = await mahRows();
    final services = rows.map((r) => r['service_provided'] as String).toList()
      ..sort();
    expect(services, ['anc', 'family_planning']);
    expect(rows.map((r) => r['encounter_id']).toSet(),
        {'server-enc-1', 'server-enc-fp'});
  });

  test('dashboard: 2 ANC visits with glasses sold show 2, not 4', () async {
    final later = visitAt.add(const Duration(days: 30));
    await saveLocal(localVisit(customStatus: '["GLASSES_SOLD"]'));
    await saveLocal(localVisit(
      id: 'la-2',
      reference: 2,
      clientVisitId: 'client-visit-2',
      at: later,
      customStatus: '["GLASSES_SOLD"]',
    ));
    await writer.upsertFromHistoryItems([
      serverVisit(customStatus: const ['GLASSES_SOLD']),
      serverVisit(
        encounterId: 'server-enc-2',
        at: later,
        customStatus: const ['GLASSES_SOLD'],
      ),
    ]);
    await writer.rebuildFromLocalAssessments();

    final counts = await SpiceDashboardDao(app).loadCounts();
    expect(counts.ancCount, 2);
    expect(counts.glassesSoldCustomStatusCount, 2);
  });

  test('medical review rows from sync are left out, as in Spice', () async {
    await writer.upsertFromHistoryItems([
      serverVisit(
        encounterId: 'mr-1',
        service: 'medicalReview',
        customStatus: const ['GLASSES_SOLD'],
      ),
      serverVisit(
        encounterId: 'mr-2',
        service: 'medicalreviewvisit',
        customStatus: const ['GLASSES_SOLD'],
      ),
      serverVisit(customStatus: const ['GLASSES_SOLD']),
    ]);

    final counts = await SpiceDashboardDao(app).loadCounts();
    expect(counts.glassesSoldCustomStatusCount, 1);
  });

  test('existing medical review rows are deleted', () async {
    await app.db.insert(MemberAssessmentHistoryDao.tableName, {
      'member_fhir_id': 'member-fhir-1',
      'visit_date': '2026-11-20T09:30:15.000Z',
      'service_provided': 'medicalreviewvisit',
      'encounter_id': 'mr-1',
      'latest_visit': 1,
    });
    await MemberAssessmentHistoryDao(app).deleteMedicalReviewRows();
    expect(await mahRows(), isEmpty);
  });

  test('a visit saved on the device is stamped with the logged-in SK',
      () async {
    writer = MemberAssessmentHistoryWriter(
      mah: MemberAssessmentHistoryDao(app),
      members: MemberDao(app),
      appDb: app,
      currentUserFhirId: () async => 'sk-fhir-9',
    );
    await saveLocal(localVisit(type: 'NCD'));
    expect((await mahRows()).single['practitioner_id'], 'sk-fhir-9');

    await writer.rebuildFromLocalAssessments();
    expect((await mahRows()).single['practitioner_id'], 'sk-fhir-9');
  });

  group('deleteDuplicateRecords (Spice parity)', () {
    Future<void> row({
      int? memberId = 7,
      String memberFhirId = 'member-fhir-1',
      String visitDate = '2026-11-20T09:30:15.000Z',
      String service = 'anc',
      String encounterId = 'e',
      String? customStatus,
    }) =>
        app.db.insert(MemberAssessmentHistoryDao.tableName, {
          'member_id': memberId,
          'member_fhir_id': memberFhirId,
          'visit_date': visitDate,
          'service_provided': service,
          'encounter_id': encounterId,
          'custom_status': customStatus,
          'latest_visit': 1,
        });

    test('two copies of one visit become one', () async {
      await row(encounterId: 'a');
      await row(
        encounterId: 'b',
        service: 'ANC',
        visitDate: '2026-11-20T09:30:15.123Z',
      );
      await MemberAssessmentHistoryDao(app).deleteDuplicateRecords();
      final rows = await mahRows();
      expect(rows, hasLength(1));
      expect(rows.single['encounter_id'], 'a');
    });

    test('different members, services, times or statuses are kept', () async {
      await row(encounterId: 'a');
      await row(encounterId: 'b', memberId: 8, memberFhirId: 'member-fhir-2');
      await row(encounterId: 'c', service: 'family_planning');
      await row(encounterId: 'd', visitDate: '2026-11-20T09:30:16.000Z');
      await row(encounterId: 'e', customStatus: '["GLASSES_SOLD"]');
      await row(
        encounterId: 'f',
        memberId: null,
        memberFhirId: 'member-fhir-3',
      );
      await row(
        encounterId: 'g',
        memberId: null,
        memberFhirId: 'member-fhir-4',
      );
      await MemberAssessmentHistoryDao(app).deleteDuplicateRecords();
      expect(await mahRows(), hasLength(7));
    });

    test('rows before the cut-off date are not touched', () async {
      await row(encounterId: 'a', visitDate: '2026-04-10T09:30:15.000Z');
      await row(encounterId: 'b', visitDate: '2026-04-10T09:30:15.000Z');
      await MemberAssessmentHistoryDao(app).deleteDuplicateRecords();
      expect(await mahRows(), hasLength(2));
    });
  });
}
