library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/visit_content_dao.dart';
import 'package:uhis_next/core/telemetry/visit_content_entry.dart';
import 'package:uhis_next/core/telemetry/visit_content_service.dart';

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

void main() {
  late AppDatabase db;
  late VisitContentDao dao;
  late VisitContentService service;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await _openInMemoryDb();
    dao = VisitContentDao(db);
    service = VisitContentService(
      dao: dao,
      userIdResolver: () async => 373,
      tenantIdResolver: () async => 12,
    );
  });

  tearDown(() async => db.close());

  test('recordTranscript stores text locally', () async {
    await service.recordTranscript(
      visitUuid: 'visit-1',
      patientId: 'patient-1',
      transcript: 'patient reports headache',
    );
    final row = await dao.byVisitUuid('visit-1');
    expect(row?.transcript, 'patient reports headache');
    expect(row?.transcriptCapturedAt, isNotNull);
  });

  test('transcript added after upload is re-queued as pending', () async {
    await service.recordSummaryCompleted(
      visitUuid: 'visit-1',
      patientId: 'patient-1',
      whatsappSummary: 'Take your meds',
      referralRecommendation: 'Visit clinic',
    );
    await dao.markUploaded([(await dao.byVisitUuid('visit-1'))!.id]);

    await service.recordTranscript(
      visitUuid: 'visit-1',
      patientId: 'patient-1',
      transcript: 'spoken words',
    );

    final row = await dao.byVisitUuid('visit-1');
    expect(row?.transcript, 'spoken words');
    expect(row?.uploadStatus, VisitContentUploadStatus.pending);
    expect((await dao.pending()).length, 1);
  });
}
