import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/encounter_dao.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, EncounterDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, EncounterDao(app));
  }

  EncounterRow _row({
    required String id,
    required EncounterStatus status,
    Map<String, dynamic>? vitals,
    int startedAt = 1_700_000_000_000,
  }) {
    return EncounterRow(
      id: id,
      patientId: 'p1',
      programme: 'anc',
      startedAt: startedAt,
      completedAt: startedAt,
      status: status,
      syncStatus: SyncStatus.synced,
      vitalsJson: vitals == null ? null : jsonEncode(vitals),
    );
  }

  group('EncounterDao.recentWithVitalsForPatient', () {
    test('includes synced and vitalsComplete; excludes completed-only filter miss',
        () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(_row(
        id: 'e-synced',
        status: EncounterStatus.synced,
        vitals: {'systolic': 120, 'diastolic': 80},
        startedAt: 3,
      ));
      await dao.upsert(_row(
        id: 'e-vitals',
        status: EncounterStatus.vitalsComplete,
        vitals: {'weight': 62.5},
        startedAt: 2,
      ));
      await dao.upsert(_row(
        id: 'e-completed',
        status: EncounterStatus.completed,
        vitals: {'systolic': 130, 'diastolic': 85},
        startedAt: 1,
      ));
      // Draft with vitals must not appear.
      await dao.upsert(_row(
        id: 'e-draft',
        status: EncounterStatus.draft,
        vitals: {'systolic': 140, 'diastolic': 90},
        startedAt: 4,
      ));
      // Synced without vitals must not appear.
      await dao.upsert(_row(
        id: 'e-empty',
        status: EncounterStatus.synced,
        startedAt: 5,
      ));

      final completedOnly = await dao.recentForPatient('p1');
      expect(completedOnly.map((e) => e.id), ['e-completed']);

      final withVitals = await dao.recentWithVitalsForPatient('p1');
      expect(withVitals.map((e) => e.id).toList(), [
        'e-synced',
        'e-vitals',
        'e-completed',
      ]);
    });
  });
}
