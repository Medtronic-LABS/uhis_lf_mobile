/// Unit tests for [TelemetryReportBuilder] — the aggregation that produces the
/// five reported metric groups.
///
/// Pure input → output, no DB. The cases that matter most are the empty
/// denominators: a rate with nothing to divide by must come back null so the
/// UI can render "—", never a misleading 0%.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/telemetry/telemetry_event.dart';
import 'package:uhis_next/core/telemetry/telemetry_report.dart';

final _from = DateTime(2026, 9, 1);
final _to = DateTime(2026, 9, 7);

int _seq = 0;

TelemetryEvent _visit({
  required bool scribeUsed,
  String skUserId = 'sk-1',
  int? durationMs,
  List<String> aiCorrected = const [],
  List<String> aiAcceptedUnchanged = const [],
  List<String> manual = const [],
  List<String> empty = const [],
  int extractableVisible = 0,
  int renderedTotal = 0,
  int libraryTotal = 0,
}) {
  final payload = VisitCompletedPayload(
    programmes: const ['anc'],
    scribeUsed: scribeUsed,
    durationMs: durationMs,
    aiFilled: [...aiCorrected, ...aiAcceptedUnchanged],
    aiCorrected: aiCorrected,
    aiAcceptedUnchanged: aiAcceptedUnchanged,
    manual: manual,
    empty: empty,
    libraryTotal: libraryTotal,
    renderedTotal: renderedTotal,
    extractableVisible: extractableVisible,
  );
  return TelemetryEvent(
    id: 'v${_seq++}',
    eventType: TelemetryEventType.visitCompleted,
    occurredAt: DateTime(2026, 9, 3).millisecondsSinceEpoch,
    visitUuid: 'visit-${_seq}',
    skUserId: skUserId,
    appVersion: '1.0.6',
    appBuild: 6,
    payloadVersion: kTelemetryPayloadVersion,
    payload: payload.toJson(),
  );
}

TelemetryEvent _share({
  required String channel,
  bool launched = true,
  String surface = TelemetryShareSurface.counselling,
}) =>
    TelemetryEvent(
      id: 's${_seq++}',
      eventType: TelemetryEventType.counsellingShare,
      occurredAt: DateTime(2026, 9, 3).millisecondsSinceEpoch,
      appVersion: '1.0.6',
      appBuild: 6,
      payloadVersion: kTelemetryPayloadVersion,
      payload: CounsellingSharePayload(
        channel: channel,
        surface: surface,
        hasMessage: true,
        launched: launched,
      ).toJson(),
    );

TelemetryReport _build(List<TelemetryEvent> events) =>
    TelemetryReportBuilder.build(from: _from, to: _to, events: events);

void main() {
  setUp(() => _seq = 0);

  group('metric 1 — adoption', () {
    test('splits visits and counts distinct users per cohort', () {
      final report = _build([
        _visit(scribeUsed: true, skUserId: 'sk-a'),
        _visit(scribeUsed: true, skUserId: 'sk-a'),
        _visit(scribeUsed: false, skUserId: 'sk-b'),
        _visit(scribeUsed: false, skUserId: 'sk-c'),
      ]);

      expect(report.visitCount, 4);
      expect(report.scribeVisitCount, 2);
      expect(report.manualVisitCount, 2);
      expect(report.usersUsingScribe, 1);
      expect(report.usersManualOnly, 2);
      expect(report.totalUsers, 3);
    });

    test('an SK who used scribe even once counts as adopting, not manual-only',
        () {
      // The two cohorts must stay disjoint or totalUsers double-counts.
      final report = _build([
        _visit(scribeUsed: true, skUserId: 'sk-a'),
        _visit(scribeUsed: false, skUserId: 'sk-a'),
      ]);

      expect(report.usersUsingScribe, 1);
      expect(report.usersManualOnly, 0);
      expect(report.totalUsers, 1);
      expect(report.scribeVisitCount, 1);
      expect(report.manualVisitCount, 1);
    });

    test('a visit with no user id still counts as a visit', () {
      final report = _build([_visit(scribeUsed: true, skUserId: '')]);
      expect(report.visitCount, 1);
      expect(report.totalUsers, 0);
    });
  });

  group('metric 2 — duration', () {
    test('reports medians per cohort with sample counts', () {
      final report = _build([
        _visit(scribeUsed: true, durationMs: 100),
        _visit(scribeUsed: true, durationMs: 300),
        _visit(scribeUsed: true, durationMs: 200),
        _visit(scribeUsed: false, durationMs: 600),
        _visit(scribeUsed: false, durationMs: 400),
      ]);

      expect(report.scribeMedianDurationMs, 200);
      expect(report.scribeDurationSampleCount, 3);
      // Even count → mean of the two middle samples.
      expect(report.manualMedianDurationMs, 500);
      expect(report.manualDurationSampleCount, 2);
    });

    test('median resists a single backgrounded-app outlier', () {
      // Wall-clock duration means one visit left open overnight is inevitable;
      // this is why the report is a median rather than a mean.
      final report = _build([
        _visit(scribeUsed: true, durationMs: 100),
        _visit(scribeUsed: true, durationMs: 120),
        _visit(scribeUsed: true, durationMs: 40000000),
      ]);

      expect(report.scribeMedianDurationMs, 120);
    });

    test('null median when no visit carried a duration', () {
      final report = _build([_visit(scribeUsed: true)]);
      expect(report.scribeMedianDurationMs, isNull);
      expect(report.scribeDurationSampleCount, 0);
    });
  });

  group('metric 3 — fields captured and capture rate', () {
    test('totals, per-visit average and rate against visible fields', () {
      final report = _build([
        _visit(
          scribeUsed: true,
          aiAcceptedUnchanged: ['systolic', 'diastolic'],
          extractableVisible: 10,
          renderedTotal: 24,
          libraryTotal: 33,
        ),
        _visit(
          scribeUsed: true,
          aiAcceptedUnchanged: ['weight'],
          aiCorrected: ['hemoglobin'],
          extractableVisible: 10,
          renderedTotal: 24,
          libraryTotal: 33,
        ),
      ]);

      expect(report.totalAiFields, 4);
      expect(report.avgAiFieldsPerScribeVisit, 2.0);
      expect(report.totalExtractableVisible, 20);
      expect(report.captureRatePct, 20.0);
      // All three denominators surfaced so the definition can change later.
      expect(report.totalRendered, 48);
      expect(report.totalLibrary, 66);
    });

    test('average is over scribe visits only, not diluted by manual ones', () {
      final report = _build([
        _visit(scribeUsed: true, aiAcceptedUnchanged: ['a', 'b']),
        _visit(scribeUsed: false, manual: ['c']),
      ]);

      expect(report.avgAiFieldsPerScribeVisit, 2.0);
    });

    test('capture rate is null, not zero, with no visible fields', () {
      final report = _build([_visit(scribeUsed: false, manual: ['a'])]);
      expect(report.captureRatePct, isNull);
      expect(report.avgAiFieldsPerScribeVisit, isNull);
    });
  });

  group('metric 4 — correction rate', () {
    test('rate is corrected over filled', () {
      final report = _build([
        _visit(
          scribeUsed: true,
          aiCorrected: ['weight'],
          aiAcceptedUnchanged: ['systolic', 'diastolic', 'pulse'],
        ),
      ]);

      expect(report.aiFilledTotal, 4);
      expect(report.aiCorrectedTotal, 1);
      expect(report.aiAcceptedUnchangedTotal, 3);
      expect(report.manualCorrectionRatePct, 25.0);
    });

    test('rate is null when AI filled nothing', () {
      final report = _build([_visit(scribeUsed: false, manual: ['a'])]);
      expect(report.manualCorrectionRatePct, isNull);
    });

    test('per-field accuracy ranks the worst fields first', () {
      final report = _build([
        _visit(scribeUsed: true, aiCorrected: ['hemoglobin'], aiAcceptedUnchanged: ['systolic']),
        _visit(scribeUsed: true, aiCorrected: ['hemoglobin'], aiAcceptedUnchanged: ['systolic']),
        _visit(scribeUsed: true, aiAcceptedUnchanged: ['systolic', 'weight']),
      ]);

      final worst = report.fieldAccuracy.first;
      expect(worst.fieldId, 'hemoglobin');
      expect(worst.filled, 2);
      expect(worst.corrected, 2);
      expect(worst.correctionRatePct, 100.0);

      final systolic =
          report.fieldAccuracy.firstWhere((f) => f.fieldId == 'systolic');
      expect(systolic.filled, 3);
      expect(systolic.corrected, 0);
      expect(systolic.correctionRatePct, 0.0);
    });

    test('a high-volume field outranks a 1-of-1 at the same rate', () {
      final events = <TelemetryEvent>[
        for (var i = 0; i < 10; i++)
          _visit(scribeUsed: true, aiCorrected: ['bulk']),
        _visit(scribeUsed: true, aiCorrected: ['oneoff']),
      ];

      final report = _build(events);

      expect(report.fieldAccuracy.first.fieldId, 'bulk');
    });
  });

  group('metric 5 — counselling share', () {
    test('counts sms and whatsapp separately', () {
      final report = _build([
        _share(channel: TelemetryShareChannel.sms),
        _share(channel: TelemetryShareChannel.sms),
        _share(channel: TelemetryShareChannel.whatsapp),
      ]);

      expect(report.smsComposeOpened, 2);
      expect(report.whatsappComposeOpened, 1);
    });

    test('a tap that never opened a compose sheet is not counted', () {
      final report = _build([
        _share(channel: TelemetryShareChannel.sms, launched: false),
      ]);
      expect(report.smsComposeOpened, 0);
    });

    test('share events do not inflate the visit count', () {
      final report = _build([
        _visit(scribeUsed: true),
        _share(channel: TelemetryShareChannel.sms),
      ]);
      expect(report.visitCount, 1);
    });
  });

  group('share surfaces', () {
    test('Step-3 visit-flow shares count as counselling shares', () {
      // That surface was missed on the first pass, so a real SK tapping
      // "Send SMS" at the end of a visit recorded nothing at all.
      final report = _build([
        _share(channel: TelemetryShareChannel.sms,
            surface: TelemetryShareSurface.visitFlow),
      ]);

      expect(report.smsComposeOpened, 1);
    });

    test('direct patient contact is NOT counted as a counselling share', () {
      // CCE drawer / contact sheet taps are patient contact; counting them
      // here would inflate the counselling metric with unrelated activity.
      final report = _build([
        _share(channel: TelemetryShareChannel.sms,
            surface: TelemetryShareSurface.cceDrawer),
        _share(channel: TelemetryShareChannel.whatsapp,
            surface: TelemetryShareSurface.contactSheet),
      ]);

      expect(report.smsComposeOpened, 0);
      expect(report.whatsappComposeOpened, 0);
      expect(report.contactSmsOpened, 1);
      expect(report.contactWhatsappOpened, 1);
    });

    test('a payload with no surface reads as a counselling share', () {
      // Written before the field existed.
      final legacy = TelemetryEvent(
        id: 'legacy',
        eventType: TelemetryEventType.counsellingShare,
        occurredAt: DateTime(2026, 9, 3).millisecondsSinceEpoch,
        appVersion: '1.0.6',
        appBuild: 6,
        payloadVersion: 1,
        payload: const {
          'channel': 'sms', 'hasMessage': true, 'launched': true,
        },
      );

      expect(_build([legacy]).smsComposeOpened, 1);
    });
  });

  group('empty range', () {
    test('build over no events yields zeros and null rates', () {
      final report = _build(const []);

      expect(report.visitCount, 0);
      expect(report.totalUsers, 0);
      expect(report.captureRatePct, isNull);
      expect(report.manualCorrectionRatePct, isNull);
      expect(report.avgAiFieldsPerScribeVisit, isNull);
      expect(report.scribeMedianDurationMs, isNull);
      expect(report.fieldAccuracy, isEmpty);
      expect(report.smsComposeOpened, 0);
    });

    test('emptyFor matches a build over no events', () {
      final built = _build(const []);
      final empty = TelemetryReport.emptyFor(_from, _to);

      expect(empty.visitCount, built.visitCount);
      expect(empty.captureRatePct, built.captureRatePct);
      expect(empty.fieldAccuracy, built.fieldAccuracy);
    });
  });

  test('an unknown event type is ignored rather than throwing', () {
    // Forward compatibility: an older build reading rows written by a newer
    // one must not lose the whole range to one unrecognised type.
    final unknown = TelemetryEvent(
      id: 'x',
      eventType: 'something_future',
      occurredAt: DateTime(2026, 9, 3).millisecondsSinceEpoch,
      appVersion: '9.9.9',
      appBuild: 99,
      payloadVersion: 99,
      payload: const {'whatever': true},
    );

    final report = _build([_visit(scribeUsed: true), unknown]);

    expect(report.visitCount, 1);
  });
}
