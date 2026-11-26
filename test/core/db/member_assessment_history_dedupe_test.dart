import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/assessment_dao.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/db/member_assessment_history_dao.dart';
import 'package:uhis_next/core/db/member_assessment_history_writer.dart';
import 'package:uhis_next/core/db/member_dao.dart';
import 'package:uhis_next/core/db/pregnancy_detail_dao.dart';
import 'package:uhis_next/core/db/spice_dashboard_dao.dart';
import 'package:uhis_next/core/db/sync_meta_dao.dart';
import 'package:uhis_next/core/models/assessment_history_item.dart';
import 'package:uhis_next/core/models/json_read.dart';
import 'package:uhis_next/features/dashboard/sk_spice_dashboard_repository.dart';

class _FakeAuth extends Fake implements AuthRepository {
  @override
  Future<String?> userFhirId() async => 'sk-fhir-9';
}

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
      syncMeta: SyncMetaDao(app),
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
    bool uploaded = false,
  }) => LocalAssessmentEntity(
    id: id,
    referenceId: reference,
    householdMemberLocalId: 7,
    memberId: 'member-fhir-1',
    assessmentType: type,
    assessmentDetails: '{}',
    otherDetails: jsonEncode({'encounterId': clientVisitId}),
    customStatus: customStatus,
    createdAt: at ?? visitAt,
    // Uploaded with no fhirId: the server id was never stored on it,
    // the only case matched to a server row by visit second.
    syncStatus: fhirId != null || uploaded
        ? AssessmentSyncStatus.success
        : AssessmentSyncStatus.pending,
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
      visitDate: DateTime.utc(
        t.year,
        t.month,
        t.day,
        t.hour,
        t.minute,
        t.second,
      ),
      serviceProvided: service,
      customStatus: customStatus,
    );
  }

  Future<List<Map<String, Object?>>> mahRows() =>
      app.db.query(MemberAssessmentHistoryDao.tableName, orderBy: 'id');

  /// The repository the dashboard tab loads through.
  SkSpiceDashboardRepository dashboardRepo() {
    final mah = MemberAssessmentHistoryDao(app);
    return SkSpiceDashboardRepository(
      dashboard: SpiceDashboardDao(app),
      mah: mah,
      mahWriter: writer,
      pregnancyDetail: PregnancyDetailDao(app, mah, MemberDao(app)),
      auth: _FakeAuth(),
    );
  }

  Future<void> saveLocal(LocalAssessmentEntity e) async {
    await app.db.insert(LocalAssessmentDao.tableName, e.toDb());
    await writer.upsertFromLocal(e, projectPregnancy: false);
  }

  test(
    'visit saved, uploaded, then pulled back is one row (server copy)',
    () async {
      await saveLocal(localVisit());
      await app.db.update(LocalAssessmentDao.tableName, {
        'fhir_id': 'server-enc-1',
        'sync_status': 'success',
      });
      await writer.upsertFromHistoryItems([serverVisit()]);
      // Every dashboard load re-merges local_assessments.
      await writer.rebuildFromLocalAssessments();

      final rows = await mahRows();
      expect(rows, hasLength(1));
      expect(rows.single['encounter_id'], 'server-enc-1');
    },
  );

  test('matches on member + service + visit second when no server id was '
      'stamped on the local row', () async {
    await saveLocal(localVisit(uploaded: true));
    await writer.upsertFromHistoryItems([serverVisit()]);
    await writer.rebuildFromLocalAssessments();

    final rows = await mahRows();
    expect(rows, hasLength(1));
    expect(rows.single['encounter_id'], 'server-enc-1');
  });

  test('a device that already has the duplicate heals on the next dashboard '
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
        occurredAt: DateTime.utc(
          2026,
          11,
          20,
          9,
          30,
          15,
        ).millisecondsSinceEpoch,
        rawJson: jsonEncode({'householdMemberId': 'member-fhir-1'}),
      ),
    ]);
    expect(await mahRows(), hasLength(2));

    // The real path: what the dashboard runs on its first load.
    final day = DateTime.utc(2026, 11, 20, 12);
    await dashboardRepo().load(from: day, to: day);

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
    await saveLocal(localVisit(uploaded: true));
    await saveLocal(
      localVisit(
        id: 'la-2',
        reference: 2,
        clientVisitId: 'client-visit-2',
        at: later,
        uploaded: true,
      ),
    );
    await writer.upsertFromHistoryItems([
      serverVisit(),
      serverVisit(encounterId: 'server-enc-2', at: later),
    ]);
    await writer.rebuildFromLocalAssessments();

    final ids = (await mahRows()).map((r) => r['encounter_id']).toSet();
    expect(ids, {'server-enc-1', 'server-enc-2'});
  });

  test('one visit covering two programmes keeps one row per service', () async {
    await saveLocal(localVisit(uploaded: true));
    await saveLocal(
      localVisit(
        id: 'la-2',
        reference: 2,
        type: 'FAMILY_PLANNING',
        uploaded: true,
      ),
    );
    await writer.upsertFromHistoryItems([
      serverVisit(),
      serverVisit(encounterId: 'server-enc-fp', service: 'family_planning'),
    ]);
    await writer.rebuildFromLocalAssessments();

    final rows = await mahRows();
    final services = rows.map((r) => r['service_provided'] as String).toList()
      ..sort();
    expect(services, ['anc', 'family_planning']);
    expect(rows.map((r) => r['encounter_id']).toSet(), {
      'server-enc-1',
      'server-enc-fp',
    });
  });

  test('dashboard: 2 ANC visits with glasses sold show 2, not 4', () async {
    final later = visitAt.add(const Duration(days: 30));
    await saveLocal(
      localVisit(customStatus: '["GLASSES_SOLD"]', uploaded: true),
    );
    await saveLocal(
      localVisit(
        id: 'la-2',
        reference: 2,
        clientVisitId: 'client-visit-2',
        at: later,
        customStatus: '["GLASSES_SOLD"]',
        uploaded: true,
      ),
    );
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

  test(
    'a visit saved on the device is stamped with the logged-in SK',
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
    },
  );

  test(
    'a rebuild keeps the SK who saved the visit, not the one logged in now',
    () async {
      MemberAssessmentHistoryWriter as(String sk) =>
          MemberAssessmentHistoryWriter(
            mah: MemberAssessmentHistoryDao(app),
            members: MemberDao(app),
            appDb: app,
            currentUserFhirId: () async => sk,
          );
      writer = as('sk-a');
      await saveLocal(localVisit(type: 'NCD'));

      // SK-B logs in on the same device and opens the dashboard.
      await as('sk-b').rebuildFromLocalAssessments();
      expect((await mahRows()).single['practitioner_id'], 'sk-a');
    },
  );

  test(
    'a rebuild does not stamp a visit that was saved without an SK',
    () async {
      await saveLocal(localVisit(type: 'NCD'));
      expect((await mahRows()).single['practitioner_id'], isNull);

      await MemberAssessmentHistoryWriter(
        mah: MemberAssessmentHistoryDao(app),
        members: MemberDao(app),
        appDb: app,
        currentUserFhirId: () async => 'sk-b',
      ).rebuildFromLocalAssessments();
      expect((await mahRows()).single['practitioner_id'], isNull);
    },
  );

  test(
    'unreadable other_details on another row does not lose the batch',
    () async {
      await saveLocal(localVisit(uploaded: true));
      await app.db.insert(
        LocalAssessmentDao.tableName,
        localVisit(id: 'la-bad', reference: 2).toDb()
          ..['other_details'] = '{not json'
          ..['fhir_id'] = 'server-enc-1',
      );

      await writer.upsertFromHistoryItems([serverVisit()]);

      final rows = await mahRows();
      expect(rows, hasLength(1));
      expect(rows.single['encounter_id'], 'server-enc-1');
    },
  );

  test('two server encounters in the same second are both kept', () async {
    await writer.upsertFromHistoryItems([
      serverVisit(encounterId: 'e1', customStatus: const ['GLASSES_SOLD']),
      serverVisit(encounterId: 'e2'),
    ]);
    // A later sync sends one of them again.
    await writer.upsertFromHistoryItems([serverVisit(encounterId: 'e2')]);

    final rows = await mahRows();
    expect(rows.map((r) => r['encounter_id']), ['e1', 'e2']);
  });

  group('visit time matching', () {
    test('visitSecond gives the UTC second for any zone form', () {
      const utc = '2026-11-20T09:30:15';
      String second(String v) => MemberAssessmentHistoryDao.visitSecond(v);
      expect(second('2026-11-20T09:30:15.123Z'), utc);
      expect(second('2026-11-20T15:30:15+06:00'), utc);
      expect(second('2026-11-20T09:30:15+00:00'), utc);
      // No zone: read as UTC, the way SQLite reads the stored text.
      expect(second('2026-11-20T09:30:15'), utc);
      expect(second('2026-11-20 09:30:15.500'), utc);
    });

    test('a device copy stored with an offset is still replaced', () async {
      final local = localVisit(uploaded: true);
      await app.db.insert(LocalAssessmentDao.tableName, local.toDb());
      await app.db.insert(MemberAssessmentHistoryDao.tableName, {
        'member_id': 7,
        'member_fhir_id': 'member-fhir-1',
        'visit_date': '2026-11-20T15:30:15+06:00',
        'service_provided': 'anc',
        'encounter_id': 'client-visit-1',
        'latest_visit': 1,
      });

      await writer.upsertFromHistoryItems([serverVisit()]);

      final rows = await mahRows();
      expect(rows, hasLength(1));
      expect(rows.single['encounter_id'], 'server-enc-1');
    });

    test('a device copy stored with no zone is still replaced', () async {
      await app.db.insert(
        LocalAssessmentDao.tableName,
        localVisit(uploaded: true).toDb(),
      );
      await app.db.insert(MemberAssessmentHistoryDao.tableName, {
        'member_id': 7,
        'member_fhir_id': 'member-fhir-1',
        'visit_date': '2026-11-20T09:30:15',
        'service_provided': 'anc',
        'encounter_id': 'client-visit-1',
        'latest_visit': 1,
      });

      await writer.upsertFromHistoryItems([serverVisit()]);

      expect((await mahRows()).single['encounter_id'], 'server-enc-1');
    });
  });

  group('re-writing existing rows when parse rules change', () {
    Future<void> cacheVisit(String id, {List<String> status = const []}) =>
        AssessmentDao(app).upsertMany([
          AssessmentRow(
            id: id,
            patientId: 'member-fhir-1',
            kind: 'ANC',
            occurredAt: DateTime.utc(
              2026,
              11,
              20,
              9,
              30,
              15,
            ).millisecondsSinceEpoch,
            rawJson: jsonEncode({
              'householdMemberId': 'member-fhir-1',
              'customStatus': status,
            }),
          ),
        ]);

    final day = DateTime.utc(2026, 11, 20, 12);

    test('runs once, only for visits already in the table', () async {
      // A row written by older parse rules (no custom status)...
      await app.db.insert(MemberAssessmentHistoryDao.tableName, {
        'member_fhir_id': 'member-fhir-1',
        'visit_date': '2026-11-20T09:30:15.000Z',
        'service_provided': 'anc',
        'encounter_id': 'kept',
        'latest_visit': 1,
      });
      await cacheVisit('kept', status: const ['GLASSES_SOLD']);
      // ...and a cached visit a full sync has since removed.
      await cacheVisit('removed-by-full-sync');

      await dashboardRepo().load(from: day, to: day);

      var rows = await mahRows();
      expect(rows.single['encounter_id'], 'kept');
      expect(rows.single['custom_status'], contains('GLASSES_SOLD'));

      // Same version next session: the cache is not read again.
      await cacheVisit('kept');
      await dashboardRepo().load(from: day, to: day);
      rows = await mahRows();
      expect(rows.single['custom_status'], contains('GLASSES_SOLD'));
    });
  });

  test('JsonRead.idOrNull treats blank and text "no value" forms as none', () {
    expect(JsonRead.idOrNull(null), isNull);
    expect(JsonRead.idOrNull('  '), isNull);
    expect(JsonRead.idOrNull('null'), isNull);
    expect(JsonRead.idOrNull(' NULL '), isNull);
    expect(JsonRead.idOrNull('undefined'), isNull);
    expect(JsonRead.idOrNull(' 900004432063 '), '900004432063');
  });

  test(
    'two visits saved on the device in the same second are both kept',
    () async {
      await saveLocal(localVisit());
      await saveLocal(
        localVisit(id: 'la-2', reference: 2, clientVisitId: 'client-visit-2'),
      );
      final day = DateTime.utc(2026, 11, 20, 12);
      await dashboardRepo().load(from: day, to: day);

      expect(
        (await mahRows()).map((r) => r['encounter_id']),
        unorderedEquals(['client-visit-1', 'client-visit-2']),
      );
    },
  );

  test(
    'two server encounters in the same second survive a dashboard load',
    () async {
      await writer.upsertFromHistoryItems([
        serverVisit(encounterId: 'e1'),
        serverVisit(encounterId: 'e2'),
      ]);
      final day = DateTime.utc(2026, 11, 20, 12);
      await dashboardRepo().load(from: day, to: day);

      expect((await mahRows()).map((r) => r['encounter_id']), ['e1', 'e2']);
    },
  );

  group('practitioner stamped at save time', () {
    setUp(() {
      writer = MemberAssessmentHistoryWriter(
        mah: MemberAssessmentHistoryDao(app),
        members: MemberDao(app),
        appDb: app,
        currentUserFhirId: () async => 'sk-fhir-9',
      );
    });

    AssessmentHistoryItem serverNcd({String? practitionerId}) =>
        AssessmentHistoryItem(
          householdMemberId: 'member-fhir-1',
          encounterId: 'server-enc-1',
          visitDate: DateTime.utc(2026, 11, 20, 9, 30, 15),
          serviceProvided: 'NCD',
          rawJson: {'practitionerId': ?practitionerId},
        );

    test(
      'moves to the server row when that row names no practitioner',
      () async {
        await saveLocal(localVisit(type: 'NCD', uploaded: true));
        await writer.upsertFromHistoryItems([serverNcd()]);

        final row = (await mahRows()).single;
        expect(row['encounter_id'], 'server-enc-1');
        expect(row['practitioner_id'], 'sk-fhir-9');
      },
    );

    test('does not replace the practitioner the server sent', () async {
      await saveLocal(localVisit(type: 'NCD', uploaded: true));
      await writer.upsertFromHistoryItems([
        serverNcd(practitionerId: 'sk-other'),
      ]);

      expect((await mahRows()).single['practitioner_id'], 'sk-other');
    });

    test(
      'moves to the server row when the rebuild replaces the device copy',
      () async {
        // Both copies present, as left by a build without the dedupe.
        await saveLocal(localVisit(type: 'NCD', uploaded: true));
        await app.db.insert(MemberAssessmentHistoryDao.tableName, {
          'member_fhir_id': 'member-fhir-1',
          'visit_date': '2026-11-20T09:30:15.000Z',
          'service_provided': 'ncd',
          'encounter_id': 'server-enc-1',
          'latest_visit': 1,
        });

        await writer.rebuildFromLocalAssessments();

        final row = (await mahRows()).single;
        expect(row['encounter_id'], 'server-enc-1');
        expect(row['practitioner_id'], 'sk-fhir-9');
      },
    );
  });

  group('practitioner on the server row survives later writes', () {
    setUp(() {
      writer = MemberAssessmentHistoryWriter(
        mah: MemberAssessmentHistoryDao(app),
        members: MemberDao(app),
        appDb: app,
        currentUserFhirId: () async => 'sk-fhir-9',
      );
    });

    AssessmentHistoryItem serverNcd() => AssessmentHistoryItem(
      householdMemberId: 'member-fhir-1',
      encounterId: 'server-enc-1',
      visitDate: DateTime.utc(2026, 11, 20, 9, 30, 15),
      serviceProvided: 'NCD',
    );

    test('the same encounter pulled again keeps the stamp', () async {
      await saveLocal(localVisit(type: 'NCD', uploaded: true));
      await writer.upsertFromHistoryItems([serverNcd()]);
      await writer.upsertFromHistoryItems([serverNcd()]);

      expect((await mahRows()).single['practitioner_id'], 'sk-fhir-9');
    });
  });

  group('full history pull (replaceAll)', () {
    test('removes rows the server no longer returns, in one step', () async {
      await writer.upsertFromHistoryItems([
        serverVisit(encounterId: 'gone'),
        serverVisit(
          encounterId: 'stays',
          at: visitAt.add(const Duration(hours: 1)),
        ),
      ]);

      await writer.upsertFromHistoryItems([
        serverVisit(
          encounterId: 'stays',
          at: visitAt.add(const Duration(hours: 1)),
        ),
      ], replaceAll: true);

      expect((await mahRows()).single['encounter_id'], 'stays');
    });

    test('keeps a visit not yet uploaded, with its practitioner', () async {
      writer = MemberAssessmentHistoryWriter(
        mah: MemberAssessmentHistoryDao(app),
        members: MemberDao(app),
        appDb: app,
        currentUserFhirId: () async => 'sk-fhir-9',
      );
      await saveLocal(localVisit(type: 'NCD'));

      await writer.upsertFromHistoryItems([
        serverVisit(
          encounterId: 'other',
          at: visitAt.add(const Duration(hours: 1)),
        ),
      ], replaceAll: true);
      await writer.rebuildFromLocalAssessments();

      final rows = await mahRows();
      expect(
        rows.map((r) => r['encounter_id']),
        unorderedEquals(['client-visit-1', 'other']),
      );
      expect(
        rows.firstWhere(
          (r) => r['encounter_id'] == 'client-visit-1',
        )['practitioner_id'],
        'sk-fhir-9',
      );
    });

    test('replaces the device copy of a visit the pull returns', () async {
      await saveLocal(localVisit(uploaded: true));
      await writer.upsertFromHistoryItems([serverVisit()], replaceAll: true);
      await writer.rebuildFromLocalAssessments();

      expect((await mahRows()).single['encounter_id'], 'server-enc-1');
    });
  });

  test('a pending visit in the same second as a synced one is not removed '
      'by the synced visit\'s server row', () async {
    await saveLocal(localVisit(fhirId: 'server-enc-1'));
    await saveLocal(
      localVisit(id: 'la-2', reference: 2, clientVisitId: 'client-visit-2'),
    );

    await writer.upsertFromHistoryItems([serverVisit()]);

    expect(
      (await mahRows()).map((r) => r['encounter_id']),
      unorderedEquals(['server-enc-1', 'client-visit-2']),
    );
  });

  test(
    'matches on the local member id when the device row has no FHIR id',
    () async {
      final local = LocalAssessmentEntity(
        id: 'la-1',
        referenceId: 1,
        householdMemberLocalId: 7,
        assessmentType: 'ANC',
        assessmentDetails: '{}',
        otherDetails: jsonEncode({'encounterId': 'client-visit-1'}),
        createdAt: visitAt,
        syncStatus: AssessmentSyncStatus.success,
      );
      await saveLocal(local);
      // The server row resolves to the same local member.
      await MemberAssessmentHistoryDao(app).upsertMany([
        MemberAssessmentHistoryRow(
          memberId: 7,
          memberFhirId: 'member-fhir-1',
          visitDate: '2026-11-20T09:30:15.000Z',
          serviceProvided: 'anc',
          encounterId: 'server-enc-1',
        ),
      ], fromServer: true);

      expect((await mahRows()).single['encounter_id'], 'server-enc-1');
    },
  );

  test(
    'the server spelling of family planning matches the device copy',
    () async {
      await saveLocal(localVisit(type: 'FAMILY_PLANNING', uploaded: true));
      await writer.upsertFromHistoryItems([
        serverVisit(service: 'familyPlanning'),
      ]);
      await writer.rebuildFromLocalAssessments();

      expect((await mahRows()).single['encounter_id'], 'server-enc-1');
    },
  );

  test('loads started together wait for one hydration', () async {
    // Both copies present, as left by a build without the dedupe.
    await saveLocal(localVisit(uploaded: true));
    await app.db.insert(MemberAssessmentHistoryDao.tableName, {
      'member_fhir_id': 'member-fhir-1',
      'visit_date': '2026-11-20T09:30:15.000Z',
      'service_provided': 'anc',
      'encounter_id': 'server-enc-1',
      'latest_visit': 1,
    });
    final repo = dashboardRepo();
    final day = DateTime.utc(2026, 11, 20, 12);

    final counts = await Future.wait([
      repo.load(from: day, to: day),
      repo.load(from: day, to: day),
    ]);

    expect(counts[0].ancCount, 1);
    expect(counts[1].ancCount, 1);
  });

  test(
    'a large pull costs about the same with visits saved on the device',
    () async {
      List<AssessmentHistoryItem> pull(String prefix) => [
        for (var i = 0; i < 4000; i++)
          AssessmentHistoryItem(
            householdMemberId: 'member-${i % 400}',
            encounterId: '$prefix-$i',
            visitDate: DateTime.utc(2026, 11, 1).add(Duration(minutes: i)),
            serviceProvided: 'ANC',
          ),
      ];
      Future<int> timed(List<AssessmentHistoryItem> items) async {
        final watch = Stopwatch()..start();
        await writer.upsertFromHistoryItems(items);
        return watch.elapsedMilliseconds;
      }

      final without = await timed(pull('a'));
      await saveLocal(localVisit());
      final withLocal = await timed(pull('b'));

      // Each server row used to scan the whole table once a local visit
      // existed, which made this several times slower and quadratic.
      expect(withLocal, lessThan(without * 3 + 500));
      expect(await mahRows(), hasLength(8001));
    },
  );

  group('the visit second is a hint, never proof (PR #776 review)', () {
    List<Object?> ids(List<Map<String, Object?>> rows) =>
        rows.map((r) => r['encounter_id']).toList();

    test('sync: one server row does not remove two device visits saved in '
        'the same second', () async {
      await saveLocal(localVisit(uploaded: true));
      await saveLocal(
        localVisit(
          id: 'la-2',
          reference: 2,
          clientVisitId: 'client-visit-2',
          uploaded: true,
        ),
      );

      await writer.upsertFromHistoryItems([serverVisit()]);

      expect(
        ids(await mahRows()),
        unorderedEquals(['client-visit-1', 'client-visit-2', 'server-enc-1']),
      );
    });

    test('save: a pending visit is written even when a server row shares '
        'its second', () async {
      await writer.upsertFromHistoryItems([serverVisit()]);
      await saveLocal(
        localVisit(id: 'la-2', reference: 2, clientVisitId: 'client-visit-2'),
      );
      await writer.rebuildFromLocalAssessments();

      expect(
        ids(await mahRows()),
        unorderedEquals(['server-enc-1', 'client-visit-2']),
      );
      final counts = await SpiceDashboardDao(app).loadCounts();
      expect(counts.ancCount, 2);
    });

    test('save: a visit whose own server row has not arrived is not matched '
        'to another server visit in that second', () async {
      await writer.upsertFromHistoryItems([serverVisit()]);
      await saveLocal(
        localVisit(
          id: 'la-2',
          reference: 2,
          clientVisitId: 'client-visit-2',
          fhirId: 'server-enc-9',
        ),
      );
      await writer.rebuildFromLocalAssessments();

      expect(
        ids(await mahRows()),
        unorderedEquals(['server-enc-1', 'client-visit-2']),
      );
    });

    test('sync: a visit stamped with another server id is not removed by a '
        'server row in its second', () async {
      await saveLocal(localVisit(fhirId: 'server-enc-9'));
      await writer.upsertFromHistoryItems([serverVisit()]);

      expect(
        ids(await mahRows()),
        unorderedEquals(['client-visit-1', 'server-enc-1']),
      );
    });

    test('save: two server visits in the second leave an unlinked device '
        'visit alone', () async {
      await writer.upsertFromHistoryItems([
        serverVisit(encounterId: 'e1'),
        serverVisit(encounterId: 'e2'),
      ]);
      await saveLocal(localVisit(uploaded: true));
      await writer.rebuildFromLocalAssessments();

      expect(
        ids(await mahRows()),
        unorderedEquals(['e1', 'e2', 'client-visit-1']),
      );
    });

    test('sync: two server visits in the second leave an unlinked device '
        'visit alone', () async {
      await saveLocal(localVisit(uploaded: true));
      await writer.upsertFromHistoryItems([
        serverVisit(encounterId: 'e1'),
        serverVisit(encounterId: 'e2'),
      ]);

      expect(
        ids(await mahRows()),
        unorderedEquals(['client-visit-1', 'e1', 'e2']),
      );
    });

    test('a leftover device copy goes once the server id is stored', () async {
      await saveLocal(localVisit(uploaded: true));
      await saveLocal(
        localVisit(
          id: 'la-2',
          reference: 2,
          clientVisitId: 'client-visit-2',
          uploaded: true,
        ),
      );
      await writer.upsertFromHistoryItems([serverVisit()]);
      expect(await mahRows(), hasLength(3));

      await LocalAssessmentDao(app).applyFhirIdByReferenceId(1, 'server-enc-1');
      await writer.upsertFromHistoryItems([serverVisit()]);

      expect(
        ids(await mahRows()),
        unorderedEquals(['client-visit-2', 'server-enc-1']),
      );
    });
  });

  test(
    'a full pull keeps the SK stamp an earlier sync moved to the server row',
    () async {
      writer = MemberAssessmentHistoryWriter(
        mah: MemberAssessmentHistoryDao(app),
        members: MemberDao(app),
        appDb: app,
        currentUserFhirId: () async => 'sk-fhir-9',
      );
      AssessmentHistoryItem serverNcd() => AssessmentHistoryItem(
        householdMemberId: 'member-fhir-1',
        encounterId: 'server-enc-1',
        visitDate: DateTime.utc(2026, 11, 20, 9, 30, 15),
        serviceProvided: 'NCD',
      );
      await saveLocal(localVisit(type: 'NCD', fhirId: 'server-enc-1'));
      await writer.upsertFromHistoryItems([serverNcd()]);
      expect((await mahRows()).single['practitioner_id'], 'sk-fhir-9');

      // Re-login: a full pull, the device copy is already gone.
      await writer.upsertFromHistoryItems([serverNcd()], replaceAll: true);
      await writer.rebuildFromLocalAssessments();

      final row = (await mahRows()).single;
      expect(row['encounter_id'], 'server-enc-1');
      expect(row['practitioner_id'], 'sk-fhir-9');
    },
  );

  group('deleteDuplicateRecords', () {
    Future<void> row({
      int? memberId = 7,
      String memberFhirId = 'member-fhir-1',
      String visitDate = '2026-11-20T09:30:15.000Z',
      String service = 'anc',
      String encounterId = 'e',
      String? customStatus,
    }) => app.db.insert(MemberAssessmentHistoryDao.tableName, {
      'member_id': memberId,
      'member_fhir_id': memberFhirId,
      'visit_date': visitDate,
      'service_provided': service,
      'encounter_id': encounterId,
      'custom_status': customStatus,
      'latest_visit': 1,
    });

    test('a repeated encounter id + service becomes one row', () async {
      await row(encounterId: 'a');
      await row(encounterId: 'a', service: 'ANC');
      await MemberAssessmentHistoryDao(app).deleteDuplicateRecords();
      expect(await mahRows(), hasLength(1));
    });

    test('different encounters are kept, even in the same second', () async {
      await row(encounterId: 'a');
      await row(encounterId: 'b');
      await row(encounterId: 'a', service: 'family_planning');
      await row(encounterId: 'c', customStatus: '["GLASSES_SOLD"]');
      await MemberAssessmentHistoryDao(app).deleteDuplicateRecords();
      expect(await mahRows(), hasLength(4));
    });

    test('rows before the cut-off date are not touched', () async {
      await row(encounterId: 'a', visitDate: '2026-04-10T09:30:15.000Z');
      await row(encounterId: 'a', visitDate: '2026-04-10T09:30:15.000Z');
      await MemberAssessmentHistoryDao(app).deleteDuplicateRecords();
      expect(await mahRows(), hasLength(2));
    });
  });
}
