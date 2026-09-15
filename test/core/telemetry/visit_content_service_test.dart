/// Merge behaviour of [VisitContentService].
///
/// Each capture point in a visit writes the same row — transcript at form
/// submit, then the Step 3 summary timings and texts. These pin the rule that
/// a merge may only ever add, and that concurrent callers cannot undo one
/// another.
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
      userIdResolver: () async => 7,
      tenantIdResolver: () async => 20,
    );
  });

  tearDown(() async => db.db.close());

  test('concurrent captures do not undo one another', () async {
    // The shipped failure: the transcript was captured at submit and fired
    // with `unawaited`, so Step 3's write re-read the row before that write
    // landed and stored back the null transcript it had just read.
    await Future.wait([
      service.recordTranscript(
        visitUuid: 'v1',
        patientId: 'p1',
        transcript: 'Blood pressure 110 over 70',
      ),
      service.recordSummaryStarted(visitUuid: 'v1', patientId: 'p1'),
      service.recordSummaryCompleted(
        visitUuid: 'v1',
        patientId: 'p1',
        whatsappSummary: 'Take your medicine daily',
      ),
    ]);

    final row = await dao.byVisitUuid('v1');
    expect(row!.transcript, 'Blood pressure 110 over 70');
    expect(row.transcriptCapturedAt, isNotNull);
    expect(row.whatsappSummary, 'Take your medicine daily');
    expect(row.summaryStartedAt, isNotNull);
  });

  test('a later empty capture leaves stored content alone', () async {
    await service.recordTranscript(
      visitUuid: 'v1',
      patientId: 'p1',
      transcript: 'the whole consultation',
    );
    // A second visit flow with no live session hands over an empty string.
    await service.recordTranscript(
      visitUuid: 'v1',
      patientId: 'p1',
      transcript: '   ',
    );

    final row = await dao.byVisitUuid('v1');
    expect(row!.transcript, 'the whole consultation');
    expect(row.transcriptCapturedAt, isNotNull);
  });

  test('content captured after a flush is queued again', () async {
    await service.recordSummaryStarted(visitUuid: 'v1', patientId: 'p1');
    final uploaded = await dao.byVisitUuid('v1');
    await dao.markUploaded([uploaded!.id]);
    expect((await dao.pending()), isEmpty);

    // The transcript lands after that upload. Keeping the row's `uploaded`
    // status here would strand it on the device permanently.
    await service.recordTranscript(
      visitUuid: 'v1',
      patientId: 'p1',
      transcript: 'said after the flush',
    );

    final pending = await dao.pending();
    expect(pending, hasLength(1));
    expect(pending.single.transcript, 'said after the flush');
  });

  test('a capture point that says nothing keeps the other fields', () async {
    await service.recordTranscript(
      visitUuid: 'v1',
      patientId: 'p1',
      transcript: 'transcript text',
    );
    await service.recordSummaryCompleted(
      visitUuid: 'v1',
      patientId: 'p1',
      whatsappSummary: 'message text',
    );
    // No referral on this visit — must not blank what is already there.
    await service.recordSummaryCompleted(
      visitUuid: 'v1',
      patientId: 'p1',
      referralRecommendation: 'refer to upazila',
    );

    final row = await dao.byVisitUuid('v1');
    expect(row!.transcript, 'transcript text');
    expect(row.whatsappSummary, 'message text');
    expect(row.referralRecommendation, 'refer to upazila');
  });
}
