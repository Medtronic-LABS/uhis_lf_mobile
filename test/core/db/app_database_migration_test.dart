/// Regression test for a real merge-conflict bug: this branch's EPI
/// migrations and a separately-landed set on `main` both independently
/// claimed schema versions 31-33 for unrelated changes. Resolving the
/// conflict meant renumbering this branch's migrations to 34-35 (dropping
/// one that turned out to be a duplicate of main's v31). This test proves
/// the full merged v31-35 chain runs cleanly end-to-end from a pre-v31
/// device with no version collision and no missing column.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
      'onUpgrade from v30 adds every column across the merged v31-35 chain',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Minimal "device last seen on v30" stub — just the tables this range
    // of migrations touches, deliberately missing every column v31-35 are
    // expected to add.
    await db.execute(
        'CREATE TABLE ${AppDatabase.tableLocalAssessments} (id TEXT PRIMARY KEY)');
    await db.execute(
        'CREATE TABLE ${AppDatabase.tablePregnancySnapshot} (patient_id TEXT PRIMARY KEY)');
    await db.execute(
        'CREATE TABLE ${AppDatabase.tableImmunisations} (id TEXT PRIMARY KEY)');

    await AppDatabase.onUpgrade(db, 30, AppDatabase.schemaVersion);

    Future<Set<String>> columnsOf(String table) async {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      return rows.map((r) => r['name'] as String).toSet();
    }

    expect(await columnsOf(AppDatabase.tableLocalAssessments),
        contains('custom_status'),
        reason: 'v31 — shared between both branches, kept once');
    expect(await columnsOf(AppDatabase.tablePregnancySnapshot),
        containsAll(['pnc_visit_no', 'anc_visit_no']),
        reason: 'v32/v33 — main\'s migrations, unchanged version numbers');
    expect(
        await columnsOf(AppDatabase.tableImmunisations),
        containsAll(['status', 'missed_reason', 'referral_facility']),
        reason: 'v34/v35 — this branch\'s migrations, renumbered from the '
            'original v31/v33 to slot in after main\'s chain');

    await db.close();
  });
}
