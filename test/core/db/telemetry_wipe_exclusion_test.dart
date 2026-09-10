/// Guards the two schema-lifecycle properties the telemetry report depends on.
///
/// 1. `telemetry_events` SURVIVES [AppDatabase.wipeAllData]. That wipe fires
///    when a different SK signs into a shared device, so a telemetry row
///    caught by it would be destroyed along with the outgoing SK's data —
///    losing any events still queued for upload, and making a
///    report for a past date range impossible. The exclusion is intentional
///    and load-bearing, so it needs a positive assertion: the pre-existing
///    wipe tests iterate `allTablesForTesting` and would simply skip a table
///    that isn't in the list, i.e. they cannot catch a regression here.
///
/// 2. The v41 → v42 migration creates the table on an existing install without
///    disturbing data already on the device.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/telemetry_dao.dart';
import 'package:uhis_next/core/telemetry/value_audit_dao.dart';
import 'package:uhis_next/core/telemetry/value_audit_entry.dart';
import 'package:uhis_next/core/telemetry/telemetry_event.dart';

Future<AppDatabase> _openInMemoryDb() async {
  final rawDb = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppDatabase.schemaVersion,
      onCreate: AppDatabase.createSchema,
    ),
  );
  return AppDatabase.forTesting(rawDb);
}

TelemetryEvent _event(String id) => TelemetryEvent(
      id: id,
      eventType: TelemetryEventType.visitCompleted,
      occurredAt: DateTime(2026, 9, 4).millisecondsSinceEpoch,
      visitUuid: 'visit-$id',
      skUserId: 'sk-1',
      appVersion: '1.0.6',
      appBuild: 6,
      payloadVersion: kTelemetryPayloadVersion,
      payload: const {'scribeUsed': true},
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;

  setUp(() async {
    db = await _openInMemoryDb();
  });

  tearDown(() async {
    await db.close();
  });

  group('wipeAllData exclusion', () {
    test('telemetry rows survive a wipe that empties every other table',
        () async {
      final dao = TelemetryDao(db);
      await dao.insert(_event('t1'));
      await dao.insert(_event('t2'));
      // Two representative patient-data tables that MUST be cleared.
      await db.db.insert(AppDatabase.tableHouseholds, {'fhir_id': 'hh-1'});
      await db.db.insert(AppDatabase.tableEvalLog, {
        'id': 'ev-1',
        'encounter_id': 'enc-1',
        'patient_id': 'p-1',
        'member_id': 'm-1',
        'captured_at': 1,
        'activated_programmes': '[]',
        'symptoms': '[]',
        'field_values': '{}',
        'cds_alerts': '[]',
        'patient_context_json': '{}',
        'upload_status': 'pending',
      });

      await db.wipeAllData();

      expect((await dao.counts()).total, 2,
          reason: 'telemetry must outlive a different-SK login to allow past-date '
              'reports — see the _allTables comment in app_database.dart');
      expect(
        await db.db.query(AppDatabase.tableHouseholds),
        isEmpty,
        reason: 'patient data must still be wiped',
      );
      expect(await db.db.query(AppDatabase.tableEvalLog), isEmpty);
    });

    test('the telemetry table is not in the wipe list', () async {
      expect(
        AppDatabase.allTablesForTesting,
        isNot(contains(AppDatabase.tableTelemetryEvents)),
      );
    });

    test('every other table declared in the schema IS in the wipe list',
        () async {
      // Catches the opposite mistake: a future table quietly skipping the wipe
      // by omission rather than by the deliberate decision made for telemetry.
      final schemaTables = (await db.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
      ))
          .map((r) => r['name'] as String)
          .toSet();

      final notWiped = schemaTables
          .difference(AppDatabase.allTablesForTesting.toSet())
          .difference({AppDatabase.tableTelemetryEvents});

      expect(notWiped, isEmpty,
          reason: 'these tables are neither wiped nor the documented '
              'telemetry exception');
    });
  });

  group('v41 → v42 migration', () {
    test('creates the table on an existing install and preserves other data',
        () async {
      // Simulate a device that pre-dates v42: drop the table, leave real data
      // behind, then drive the documented public migration entry point.
      await db.db.execute(
          'DROP TABLE IF EXISTS ${AppDatabase.tableTelemetryEvents}');
      await db.db.insert(AppDatabase.tableHouseholds, {'fhir_id': 'hh-keep'});

      await AppDatabase.onUpgrade(db.db, 41, AppDatabase.schemaVersion);

      // Table now exists and is writable.
      final dao = TelemetryDao(db);
      await dao.insert(_event('post-migration'));
      expect((await dao.counts()).total, 1);
      // Pre-existing data untouched.
      expect(await db.db.query(AppDatabase.tableHouseholds), hasLength(1));
    });

    test('re-running the migration is a no-op and keeps existing rows',
        () async {
      final dao = TelemetryDao(db);
      await dao.insert(_event('t1'));

      await AppDatabase.onUpgrade(db.db, 41, AppDatabase.schemaVersion);

      expect((await dao.counts()).total, 1);
    });
  });

  group('value audit is the opposite case — PHI, so it IS wiped', () {
    test('the value-audit table is in the wipe list', () async {
      // The pair of assertions in this file IS the privacy boundary: telemetry
      // holds ids and counts and survives, value audit holds clinical values
      // and does not. Asserting only the exclusion would let the PHI table
      // quietly join it.
      expect(
        AppDatabase.allTablesForTesting,
        contains(AppDatabase.tableAiValueAudit),
        reason: 'clinical values must not outlive an SK handover',
      );
    });

    test('value-audit rows are destroyed by a wipe', () async {
      final db = await _openInMemoryDb();
      addTearDown(db.close);
      final dao = ValueAuditDao(db);

      await dao.insertAll([
        const ValueAuditEntry(
          id: 'a1',
          visitUuid: 'v1',
          fieldId: 'systolic',
          aiValue: '160',
          finalValue: '140',
          occurredAt: 1788940800000,
        ),
      ]);
      expect((await dao.counts()).total, 1);

      await db.wipeAllData();

      expect((await dao.counts()).total, 0,
          reason: 'a different SK signing in must not inherit these values');
    });
  });
}
