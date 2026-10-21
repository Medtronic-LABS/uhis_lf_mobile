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

  test('helpfulness vote merges onto the same visit row', () async {
    await service.recordSummaryCompleted(
      visitUuid: 'visit-1',
      patientId: 'patient-1',
      whatsappSummary: 'Reduce salt intake',
    );
    await service.recordHelpfulnessVote(
      visitUuid: 'visit-1',
      patientId: 'patient-1',
      vote: VisitContentHelpfulnessVote.up,
    );
    final row = await dao.byVisitUuid('visit-1');
    expect(row?.whatsappSummary, 'Reduce salt intake');
    expect(row?.helpfulnessVote, VisitContentHelpfulnessVote.up);
    expect(row?.uploadStatus, VisitContentUploadStatus.pending);
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

  test('concurrent captures do not undo one another', () async {
    // Step 3 fires recordSummaryStarted and recordSummaryCompleted with
    // `unawaited` (visit_flow_screen.dart:2634, :2810). Each reads the row,
    // merges, and writes it back, so interleaved they can store back a field
    // the other had just set — dropping a transcript that was captured
    // correctly. The writes are serialized for that reason.
    await Future.wait([
      service.recordTranscript(
        visitUuid: 'v-race',
        patientId: 'p1',
        transcript: 'Blood pressure 110 over 70',
      ),
      service.recordSummaryStarted(visitUuid: 'v-race', patientId: 'p1'),
      service.recordSummaryCompleted(
        visitUuid: 'v-race',
        patientId: 'p1',
        whatsappSummary: 'Take your medicine daily',
      ),
    ]);

    final row = await dao.byVisitUuid('v-race');
    expect(row!.transcript, 'Blood pressure 110 over 70');
    expect(row.whatsappSummary, 'Take your medicine daily');
    expect(row.summaryStartedAt, isNotNull);
  });

  test('a capture point that says nothing keeps the other fields', () async {
    await service.recordTranscript(
      visitUuid: 'v-keep',
      patientId: 'p1',
      transcript: 'transcript text',
    );
    await service.recordSummaryCompleted(
      visitUuid: 'v-keep',
      patientId: 'p1',
      whatsappSummary: 'message text',
    );
    // No referral on this visit — must not blank what is already stored.
    await service.recordSummaryCompleted(
      visitUuid: 'v-keep',
      patientId: 'p1',
      referralRecommendation: 'refer to upazila',
    );

    final row = await dao.byVisitUuid('v-keep');
    expect(row!.transcript, 'transcript text');
    expect(row.whatsappSummary, 'message text');
    expect(row.referralRecommendation, 'refer to upazila');
  });
}
