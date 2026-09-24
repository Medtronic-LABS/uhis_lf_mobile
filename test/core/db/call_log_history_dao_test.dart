import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/call_log_history_dao.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, CallLogHistoryDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, CallLogHistoryDao(app));
  }

  CallLogHistoryRow makeRow({
    String id = 'CL-1',
    int syncSeq = 100,
    String? patientId = 'patient-1',
    DateTime? callDate,
    String? clinicalDataJson,
  }) {
    return CallLogHistoryRow(
      id: id,
      syncSeq: syncSeq,
      patientId: patientId,
      encounterId: 'encounter-1',
      status: 'completed',
      appointmentStatus: 'Completed',
      doctorName: 'Dr. Farzana Kabir',
      doctorSpeciality: 'General Physician',
      doctorFacility: 'DMC',
      reason: 'Fever',
      clinicalDataJson: clinicalDataJson,
      prescriptionLink: '/files/rx.pdf',
      invoiceLink: '/files/inv.pdf',
      callDate: callDate ?? DateTime.fromMillisecondsSinceEpoch(1700000000000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      rawJson: '{"name":"$id"}',
    );
  }

  group('CallLogHistoryDao', () {
    test('getForPatient returns empty list when nothing saved', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      expect(await dao.getForPatient('patient-1'), isEmpty);
    });

    test('upsertMany then getForPatient round-trips every field', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsertMany([makeRow(clinicalDataJson: '{"chiefComplaints":["Fever"]}')]);

      final rows = await dao.getForPatient('patient-1');
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.id, 'CL-1');
      expect(row.syncSeq, 100);
      expect(row.patientId, 'patient-1');
      expect(row.encounterId, 'encounter-1');
      expect(row.status, 'completed');
      expect(row.appointmentStatus, 'Completed');
      expect(row.doctorName, 'Dr. Farzana Kabir');
      expect(row.doctorSpeciality, 'General Physician');
      expect(row.doctorFacility, 'DMC');
      expect(row.reason, 'Fever');
      expect(row.clinicalDataJson, '{"chiefComplaints":["Fever"]}');
      expect(row.prescriptionLink, '/files/rx.pdf');
      expect(row.invoiceLink, '/files/inv.pdf');
      expect(row.hasPrescription, isTrue);
      expect(row.hasInvoice, isTrue);
      expect(row.callDate, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(row.rawJson, '{"name":"CL-1"}');
    });

    test('upsertMany replaces the prior row for the same id (no duplicate rows)', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsertMany([makeRow(id: 'CL-1', syncSeq: 100, patientId: 'patient-1')]);
      await dao.upsertMany([makeRow(id: 'CL-1', syncSeq: 200, patientId: 'patient-1')]);

      final rows = await dao.getForPatient('patient-1');
      expect(rows, hasLength(1));
      expect(rows.single.syncSeq, 200);
    });

    test('upsertMany with empty list is a no-op', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsertMany(const []);

      expect(await dao.getForPatient('patient-1'), isEmpty);
    });

    test('getForPatient orders newest call first and respects limit', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsertMany([
        makeRow(id: 'CL-old', callDate: DateTime.fromMillisecondsSinceEpoch(1000)),
        makeRow(id: 'CL-new', callDate: DateTime.fromMillisecondsSinceEpoch(2000)),
        makeRow(id: 'CL-newest', callDate: DateTime.fromMillisecondsSinceEpoch(3000)),
      ]);

      final rows = await dao.getForPatient('patient-1', limit: 2);
      expect(rows.map((r) => r.id), ['CL-newest', 'CL-new']);
    });

    test('getForPatients batches a lookup across many patients, skipping ones with no rows', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsertMany([
        makeRow(id: 'CL-1', patientId: 'patient-1'),
        makeRow(id: 'CL-2', patientId: 'patient-2'),
      ]);

      final result = await dao.getForPatients(['patient-1', 'patient-2', 'patient-missing']);

      expect(result.keys, {'patient-1', 'patient-2'});
      expect(result['patient-1']!.single.id, 'CL-1');
      expect(result['patient-2']!.single.id, 'CL-2');
    });

    test('getForPatients returns empty map for an empty input list', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      expect(await dao.getForPatients(const []), isEmpty);
    });

    test('getById returns null when nothing saved for that id', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      expect(await dao.getById('CL-missing'), isNull);
    });

    test('getById returns the matching row', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsertMany([makeRow(id: 'CL-1')]);

      final row = await dao.getById('CL-1');
      expect(row, isNotNull);
      expect(row!.id, 'CL-1');
    });
  });

  group('normalizeClinicalData', () {
    test('null input returns null', () {
      expect(normalizeClinicalData(null), isNull);
    });

    test('already-a-string input passes through unchanged', () {
      const raw = '{"chiefComplaints":["Fever"]}';
      expect(normalizeClinicalData(raw), raw);
    });

    test('empty string input returns null', () {
      expect(normalizeClinicalData(''), isNull);
    });

    test('a parsed map is encoded to a canonical JSON string', () {
      final data = {
        'chiefComplaints': ['Fever'],
        'medicine': [
          {'name': 'Paracetamol'}
        ],
      };
      final result = normalizeClinicalData(data);
      expect(result, isA<String>());
      expect(jsonDecode(result!), data);
    });

    test('an empty map returns null', () {
      expect(normalizeClinicalData(<String, dynamic>{}), isNull);
    });

    test('an unexpected type (e.g. int) returns null', () {
      expect(normalizeClinicalData(42), isNull);
    });

    test('round-trips through ShukheeClinicalData-shaped fixture: normalize on write, decode once on read', () {
      final fixture = {
        'chiefComplaints': ['Headache', 'Fever'],
        'diagnosis': ['Viral fever'],
        'medicine': [
          {'name': 'Paracetamol', 'dosage': '500mg', 'frequency': '3x/day'},
        ],
        'mealInstruction': [
          {'name': 'Paracetamol', 'instruction': 'After meal'},
        ],
        'lastVital': {'bloodPressure': '120/80', 'temperature': '98.6'},
        'followUpDay': 7,
      };

      // Write side: whatever shape arrives (here, an already-parsed map, as
      // a wire response might be defensively pre-decoded by a caller).
      final stored = normalizeClinicalData(fixture);
      expect(stored, isA<String>());

      // Read side: exactly one jsonDecode, never re-encoded.
      final decoded = jsonDecode(stored!) as Map<String, dynamic>;
      expect(decoded['chiefComplaints'], ['Headache', 'Fever']);
      expect(decoded['followUpDay'], 7);
      expect((decoded['medicine'] as List).first['name'], 'Paracetamol');
    });
  });
}
