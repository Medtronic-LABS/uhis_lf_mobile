/// Regression test for the v40 migration that introduces `pregnancy_episodes`
/// — a real per-pregnancy entity backfilled from the pre-existing
/// single-row-per-patient `patient_pregnancy_snapshot` table.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('onUpgrade from v39 creates pregnancy_episodes and backfills one row per patient',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Minimal "device last seen on v39" stub — the full v39 snapshot schema,
    // with two patients: one delivered (closed episode), one still pregnant
    // (open episode).
    await db.execute('''
      CREATE TABLE ${AppDatabase.tablePregnancySnapshot} (
        patient_id TEXT PRIMARY KEY,
        high_risk_pregnant_woman INTEGER NOT NULL DEFAULT 0,
        has_gaps_in_anc INTEGER NOT NULL DEFAULT 0,
        is_postpartum_window INTEGER NOT NULL DEFAULT 0,
        is_near_term_anc INTEGER NOT NULL DEFAULT 0,
        had_delivery_complications INTEGER NOT NULL DEFAULT 0,
        has_pnc_illness INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER,
        edd_date INTEGER,
        lmp_date INTEGER,
        delivery_date_millis INTEGER,
        anc_visit_no INTEGER,
        pnc_visit_no INTEGER,
        gravida INTEGER,
        parity INTEGER,
        living_children INTEGER,
        age_of_last_child TEXT,
        pregnancy_test TEXT,
        previous_pregnancy_complications TEXT,
        existing_illness TEXT,
        on_treatment TEXT,
        tt_td_completed TEXT,
        facility_identified_for_delivery TEXT,
        anc_weight REAL,
        last_anc_visit_date_ms INTEGER
      )
    ''');
    await db.insert(AppDatabase.tablePregnancySnapshot, {
      'patient_id': 'delivered-patient',
      'lmp_date': 1000,
      'delivery_date_millis': 2000,
      'anc_visit_no': 4,
    });
    await db.insert(AppDatabase.tablePregnancySnapshot, {
      'patient_id': 'pregnant-patient',
      'lmp_date': 3000,
      'anc_visit_no': 1,
    });

    await AppDatabase.onUpgrade(db, 39, AppDatabase.schemaVersion);

    final rows = await db.query(AppDatabase.tablePregnancyEpisodes,
        orderBy: 'patient_id');
    expect(rows, hasLength(2));

    final delivered =
        rows.firstWhere((r) => r['patient_id'] == 'delivered-patient');
    expect(delivered['id'], isNotEmpty);
    expect(delivered['started_at'], 1000);
    expect(delivered['closed_at'], 2000, reason: 'delivery recorded → closed');
    expect(delivered['anc_visit_no'], 4);

    final pregnant =
        rows.firstWhere((r) => r['patient_id'] == 'pregnant-patient');
    expect(pregnant['started_at'], 3000);
    expect(pregnant['closed_at'], isNull, reason: 'no delivery → still open');
    expect(pregnant['anc_visit_no'], 1);

    // Table + indexes are usable (not just present).
    final open = await db.rawQuery(
      'SELECT * FROM ${AppDatabase.tablePregnancyEpisodes} '
      'WHERE patient_id = ? AND closed_at IS NULL',
      ['pregnant-patient'],
    );
    expect(open, hasLength(1));

    await db.close();
  });
}
