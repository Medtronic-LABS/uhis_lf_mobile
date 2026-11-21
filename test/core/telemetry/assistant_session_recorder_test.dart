/// Unit tests for [AssistantSessionRecorder] and its row — one
/// `telemetry_events` row per opening of the patient AI assistant sheet.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/assistant_session_recorder.dart';
import 'package:uhis_next/core/telemetry/telemetry_dao.dart';
import 'package:uhis_next/core/telemetry/telemetry_event.dart';
import 'package:uhis_next/core/telemetry/telemetry_service.dart';
import 'package:uhis_next/features/assistant/assistant_repository.dart';

class _Clock {
  int now = 2000000;
  int call() => now;
  void advance(int ms) => now += ms;
}

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
  group('recorder', () {
    late _Clock clock;
    late AssistantSessionRecorder r;

    setUp(() {
      clock = _Clock();
      r = AssistantSessionRecorder(
        sessionId: 's-1',
        context: 'patient-scoped',
        appLanguage: 'bn',
        clock: clock.call,
      );
    });

    test('a fresh session is in progress with no questions', () {
      final p = r.toPayload();
      expect(p['sessionId'], 's-1');
      expect(p['status'], AssistantSessionStatus.inProgress);
      expect(p['sessionStartTime'], 2000000);
      expect(p['questions'], isEmpty);
      expect(p['totalQuestions'], 0);
      expect(p.containsKey('sessionEndTime'), isFalse);
    });

    test('answered and failed questions, totals over answered only', () {
      r.questionAsked(
          correlator: 'c1',
          source: AssistantQuestionSource.suggested,
          askedAgain: false);
      r.questionAnswered('c1', responseTimeMs: 4200);
      r.questionAsked(
          correlator: 'c2',
          source: AssistantQuestionSource.typed,
          askedAgain: false);
      r.questionFailed('c2',
          responseTimeMs: 15000, reason: AssistantFailureReason.timeout);

      final p = r.toPayload();
      final qs = p['questions'] as List;
      expect(qs[0]['status'], AssistantQuestionStatus.answered);
      expect(qs[0]['responseTimeMs'], 4200);
      expect((qs[0] as Map).containsKey('failureReason'), isFalse);
      expect(qs[1]['status'], AssistantQuestionStatus.failed);
      expect(qs[1]['failureReason'], AssistantFailureReason.timeout);
      expect(p['totalQuestions'], 2);
      expect(p['totalAnswered'], 1);
      expect(p['totalResponseTimeMs'], 4200);
    });

    test('a retry is never counted as asked again', () {
      r.questionAsked(
          correlator: 'c1',
          source: AssistantQuestionSource.retry,
          askedAgain: true);
      r.questionAsked(
          correlator: 'c2',
          source: AssistantQuestionSource.voice,
          askedAgain: true);
      final qs = r.toPayload()['questions'] as List;
      expect(qs[0]['askedAgain'], isFalse);
      expect(qs[1]['askedAgain'], isTrue);
      expect(qs[1]['source'], AssistantQuestionSource.voice);
    });

    test('a question still in flight is pending', () {
      r.questionAsked(
          correlator: 'c1',
          source: AssistantQuestionSource.typed,
          askedAgain: false);
      final q = (r.toPayload()['questions'] as List).single as Map;
      expect(q['status'], AssistantQuestionStatus.pending);
      expect(q.containsKey('responseTimeMs'), isFalse);
    });

    test('background time is excluded from active time', () {
      clock.advance(10000);
      r.pause();
      clock.advance(600000);
      r.resume();
      clock.advance(5000);
      r.complete();

      final p = r.toPayload();
      expect(p['status'], AssistantSessionStatus.completed);
      expect(p['sessionDurationMs'], 615000);
      expect(p['sessionActiveMs'], 15000);
    });

    test('an answer arriving after the sheet closed is still recorded', () {
      r.questionAsked(
          correlator: 'c1',
          source: AssistantQuestionSource.typed,
          askedAgain: false);
      clock.advance(1000);
      r.complete();
      clock.advance(3000);
      r.questionAnswered('c1', responseTimeMs: 4000);

      final p = r.toPayload();
      expect(p['status'], AssistantSessionStatus.completed);
      expect((p['questions'] as List).single['status'],
          AssistantQuestionStatus.answered);
      expect(p['sessionActiveMs'], 1000, reason: 'clock stopped at close');
    });

    test('payload carries no question, answer or patient keys', () {
      r.questionAsked(
          correlator: 'c1',
          source: AssistantQuestionSource.typed,
          askedAgain: false);
      r.questionAnswered('c1', responseTimeMs: 10);
      final flat = r.toPayload().toString();
      for (final banned in const ['patientId', 'question', 'answer']) {
        expect(flat.contains('$banned:'), isFalse, reason: banned);
      }
    });
  });

  test('transport errors map to coarse failure reasons', () {
    DioException e(DioExceptionType t) =>
        DioException(requestOptions: RequestOptions(), type: t);
    expect(assistantFailureReasonOf(e(DioExceptionType.connectionError)),
        AssistantFailureReason.offline);
    expect(assistantFailureReasonOf(e(DioExceptionType.receiveTimeout)),
        AssistantFailureReason.timeout);
    expect(assistantFailureReasonOf(e(DioExceptionType.badResponse)),
        AssistantFailureReason.serverError);
    expect(assistantFailureReasonOf(e(DioExceptionType.cancel)),
        AssistantFailureReason.other);
  });

  group('row', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late AppDatabase db;
    late TelemetryDao dao;
    late TelemetryService service;

    setUp(() async {
      db = await _openInMemoryDb();
      dao = TelemetryDao(db);
      service = TelemetryService(
        dao: dao,
        userIdResolver: () async => 4242,
        tenantIdResolver: () async => 77,
      );
    });

    tearDown(() async => db.close());

    test('one row per session, replaced on every save', () async {
      final s = service.startAssistantSession(
        context: 'patient-scoped',
        appLanguage: 'en',
        deceasedContext: true,
      );
      s.questionAsked(
          correlator: 'c1',
          source: AssistantQuestionSource.typed,
          askedAgain: false);
      s.questionAnswered('c1', responseTimeMs: 900);
      await service.saveAssistantSession(s);
      s.complete();
      await service.saveAssistantSession(s);

      final rows = (await dao.inRange(DateTime(2020), DateTime(2100)))
          .where((e) => e.eventType == TelemetryEventType.assistantSession)
          .toList();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.id, s.sessionId);
      expect(row.visitUuid, isNull);
      expect(row.skUserId, '4242');
      expect(row.capturedTenantId, 77);
      expect(row.payloadVersion, kAssistantSessionPayloadVersion);
      expect(row.payload['status'], AssistantSessionStatus.completed);
      expect(row.payload['deceasedContext'], isTrue);
      expect(row.payload['totalAnswered'], 1);
      expect(telemetryAiFeatureForEvent(row.eventType),
          kTelemetryAiFeatureAssistant);
    });

    test('each opening is its own session', () async {
      final a = service.startAssistantSession(
          context: 'patient-scoped', appLanguage: 'bn');
      final b = service.startAssistantSession(
          context: 'patient-scoped', appLanguage: 'bn');
      await service.saveAssistantSession(null);
      expect(a.sessionId, isNot(b.sessionId));
      final rows = (await dao.inRange(DateTime(2020), DateTime(2100)))
          .where((e) => e.eventType == TelemetryEventType.assistantSession);
      expect(rows, hasLength(2));
    });
  });
}
