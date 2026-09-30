import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/teleconsult_prescription_dao.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, TeleconsultPrescriptionDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, TeleconsultPrescriptionDao(app));
  }

  group('TeleconsultPrescriptionDao', () {
    test('getForVisit returns null when nothing saved for that visit', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      expect(await dao.getForVisit('visit-1'), isNull);
    });

    test('upsert then getForVisit round-trips every field, including bytes', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      final createdAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      await dao.upsert(TeleconsultPrescriptionRow(
        visitId: 'visit-1',
        callLog: 'CL-1',
        doctorName: 'Dr. Farzana Kabir',
        prescriptionBytes: Uint8List.fromList([1, 2, 3]),
        invoiceBytes: Uint8List.fromList([4, 5]),
        createdAt: createdAt,
      ));

      final row = await dao.getForVisit('visit-1');
      expect(row, isNotNull);
      expect(row!.visitId, 'visit-1');
      expect(row.callLog, 'CL-1');
      expect(row.doctorName, 'Dr. Farzana Kabir');
      expect(row.prescriptionBytes, [1, 2, 3]);
      expect(row.invoiceBytes, [4, 5]);
      expect(row.createdAt, createdAt);
      expect(row.hasAnyDocument, isTrue);
    });

    test('upsert replaces the prior row for the same visit id (no duplicate rows)', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(TeleconsultPrescriptionRow(
        visitId: 'visit-1',
        callLog: 'CL-1',
        createdAt: DateTime.now(),
      ));
      await dao.upsert(TeleconsultPrescriptionRow(
        visitId: 'visit-1',
        callLog: 'CL-2',
        prescriptionBytes: Uint8List.fromList([9]),
        createdAt: DateTime.now(),
      ));

      final row = await dao.getForVisit('visit-1');
      expect(row!.callLog, 'CL-2');
      expect(row.prescriptionBytes, [9]);
    });

    test('hasAnyDocument is false when neither prescription nor invoice bytes were saved', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(TeleconsultPrescriptionRow(
        visitId: 'visit-1',
        callLog: 'CL-1',
        createdAt: DateTime.now(),
      ));

      final row = await dao.getForVisit('visit-1');
      expect(row!.hasAnyDocument, isFalse);
    });

    test('getForVisits batches a lookup across many visit ids, skipping ones with no row', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(TeleconsultPrescriptionRow(
        visitId: 'visit-1',
        callLog: 'CL-1',
        prescriptionBytes: Uint8List.fromList([1]),
        createdAt: DateTime.now(),
      ));
      await dao.upsert(TeleconsultPrescriptionRow(
        visitId: 'visit-2',
        callLog: 'CL-2',
        invoiceBytes: Uint8List.fromList([2]),
        createdAt: DateTime.now(),
      ));

      final result = await dao.getForVisits(['visit-1', 'visit-2', 'visit-missing']);

      expect(result.keys, {'visit-1', 'visit-2'});
      expect(result['visit-1']!.prescriptionBytes, [1]);
      expect(result['visit-2']!.invoiceBytes, [2]);
    });

    test('getForVisits returns empty map for an empty input list', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      expect(await dao.getForVisits(const []), isEmpty);
    });
  });
}
