import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/analytics/analytics.dart';
import 'package:uhis_next/core/analytics/analytics_events.dart';
import 'package:uhis_next/core/analytics/visit_analytics.dart';

class _Sink implements AnalyticsSink {
  final events = <(String, Map<String, Object>)>[];

  @override
  Future<void> logEvent(String name, Map<String, Object> params) async =>
      events.add((name, params));
  @override
  Future<void> logScreen(String screenName, String? screenClass) async {}
  @override
  Future<void> setUserId(String? id) async {}
  @override
  Future<void> setUserProperty(String name, String? value) async {}

  List<Map<String, Object>> named(String name) =>
      [for (final e in events) if (e.$1 == name) e.$2];
}

void main() {
  late _Sink sink;
  late int now;
  int clock() => now;

  setUp(() {
    sink = _Sink();
    Analytics.sink = sink;
    GaVisit.resetForTesting();
    now = 1000;
  });
  tearDown(() => Analytics.sink = null);

  group('GaVisit', () {
    test('forward steps report completion with active time', () {
      final v = GaVisit.start('enc-1', clock: clock)..enterStep(1);
      now = 6000;
      v.enterStep(2); // step 1: 5 s
      now = 16000;
      v.enterStep(3); // step 2: 10 s
      now = 19000;
      v.complete(referred: true);

      final steps = sink.named(AnalyticsEvent.visitStepCompleted);
      expect([for (final s in steps) s[AnalyticsParam.step]], [1, 2, 3]);
      expect(steps[0][AnalyticsParam.activeMs], 5000);
      expect(steps[1][AnalyticsParam.activeMs], 10000);
      expect(steps[2][AnalyticsParam.activeMs], 3000);

      final done = sink.named(AnalyticsEvent.visitCompleted).single;
      expect(done[AnalyticsParam.durationMs], 18000);
      expect(done[AnalyticsParam.activeMs], 18000);
      expect(done[AnalyticsParam.referred], 'true');
      expect(done[AnalyticsParam.visitId], v.visitId);
      expect(GaVisit.of('enc-1'), isNull, reason: 'closed visits unregister');
    });

    test('background and teleconsult pause the active clock', () {
      final v = GaVisit.start('enc-1', clock: clock)..enterStep(3);
      now = 3000;
      v.pause(GaVisitPause.teleconsult);
      now = 10000;
      v.pause(GaVisitPause.background);
      now = 12000;
      v.resume(GaVisitPause.teleconsult); // still backgrounded
      now = 14000;
      v.resume(GaVisitPause.background);
      now = 15000;
      v.complete();
      final step3 = sink.named(AnalyticsEvent.visitStepCompleted).single;
      expect(step3[AnalyticsParam.activeMs], 2000 + 1000);
    });

    test('going back reports step_back and a revisit accumulates', () {
      final v = GaVisit.start('enc-1', clock: clock)..enterStep(1);
      now = 2000;
      v.enterStep(2);
      now = 3000;
      v.enterStep(1);
      now = 5000;
      v.enterStep(2);
      final back = sink.named(AnalyticsEvent.visitStepBack).single;
      expect(back[AnalyticsParam.fromStep], 2);
      expect(back[AnalyticsParam.toStep], 1);
      final step1 = sink.named(AnalyticsEvent.visitStepCompleted);
      expect(step1.length, 2);
      expect(step1.last[AnalyticsParam.activeMs], 1000 + 2000);
      expect(step1.last[AnalyticsParam.revisit], 'true');
    });

    test('abandon reports last step; reopening abandons the old visit', () {
      final first = GaVisit.start('enc-1', clock: clock)..enterStep(1);
      now = 2000;
      first.enterStep(2);
      final second = GaVisit.start('enc-1', clock: clock);
      final abandoned = sink.named(AnalyticsEvent.visitAbandoned).single;
      expect(abandoned[AnalyticsParam.lastStep], 2);
      expect(abandoned[AnalyticsParam.visitId], first.visitId);
      expect(second.visitId, isNot(first.visitId));
      expect(GaVisit.idFor('enc-1'), second.visitId);
    });

    test('step scribe duration rides on its step event', () {
      final v = GaVisit.start('enc-1', clock: clock)..enterStep(1);
      v.markScribeSpan(1, startedAtMs: 1500, endedAtMs: 4500);
      now = 5000;
      v.enterStep(2);
      final step1 = sink.named(AnalyticsEvent.visitStepCompleted).single;
      expect(step1[AnalyticsParam.scribeSpanMs], 3000);
    });
  });

  test('mic sessions add up per step, in seconds', () {
    final v = GaVisit.start('enc-1', clock: clock)..enterStep(1);
    now = 2000;
    v.enterStep(2);
    v.addMicSession(2, 20000); // 20 s
    v.addMicSession(2, 60400); // ~1 min
    now = 200000;
    v.enterStep(3);
    final step2 = sink.named(AnalyticsEvent.visitStepCompleted)
        .firstWhere((e) => e[AnalyticsParam.step] == 2);
    expect(step2[AnalyticsParam.micSecTotal], 80);
    expect(step2[AnalyticsParam.micSessions], 2);
    final step1 = sink.named(AnalyticsEvent.visitStepCompleted)
        .firstWhere((e) => e[AnalyticsParam.step] == 1);
    expect(step1.containsKey(AnalyticsParam.micSecTotal), isFalse);
  });

  test('scribe_used is per step', () {
    final v = GaVisit.start('enc-1', clock: clock)..enterStep(1);
    now = 2000;
    v.enterStep(2);
    v.markScribeUsed(step: 2);
    now = 3000;
    v.enterStep(3);
    final steps = sink.named(AnalyticsEvent.visitStepCompleted);
    expect(steps[0][AnalyticsParam.scribeUsed], 'false');
    expect(steps[1][AnalyticsParam.scribeUsed], 'true');
  });

  test('field_source: the example visit names the 7 non-capture fields', () {
    // From a real NCD visit's in-house row.
    const capture = {
      'diastolic', 'glucose', 'glucoseType', 'hasSymptoms',
      'isBeforeDiabetesDiagnosis', 'isBeforeHtnDiagnosis', 'isRegularSmoker',
      'medicationFrequencyBg', 'ncdSymptoms', 'pulse', 'systolic', 'weight',
    };
    final list = fieldSourcesOutsideCapture(
      capture: capture,
      manual: {
        'isBeforeHtnDiagnosis', 'medicationFrequencyBg', 'hasSymptoms',
        'ncdSymptoms', '_triageSymptoms', 'eyeTestOutcome',
      },
      prefilled: {'weight', 'height'},
      derived: const {},
      empty: {
        'medicationFrequencyBp', 'newWorseningSymptoms', 'compliance',
        'hba1c', 'ncdSymptomsMedication',
      },
    );
    expect({for (final f in list) f.field: f.source}, {
      'eyeTestOutcome': 'manual',
      'height': 'prefilled',
      'compliance': 'empty',
      'hba1c': 'empty',
      'medicationFrequencyBp': 'empty',
      'ncdSymptomsMedication': 'empty',
      'newWorseningSymptoms': 'empty',
    });
  });

  test('EPI vaccine saves map to the shared outcomes', () {
    expect(epiOutcome('correct'), AiOutcome.kept);
    expect(epiOutcome('date_fixed'), AiOutcome.edited);
    expect(epiOutcome('wrongly_marked'), AiOutcome.rejected);
    expect(epiOutcome('missed'), AiOutcome.missed);
  });

  group('aiFieldOutcomes', () {
    List<AiFieldOutcome> build({
      bool scribeUsed = true,
      bool scanUsed = false,
    }) =>
        aiFieldOutcomes(
          scribeCapture: {'systolic', 'diastolic', 'weight', 'glucose', 'height'},
          aiKept: {'systolic', 'diastolic', 'weight'},
          aiEdited: {'glucose'},
          aiRejected: {'pulse'},
          scribeUsed: scribeUsed,
          scanTargets: {'weight', 'height', 'systolic'},
          scanKept: {'weight'},
          scanEdited: const {},
          scanRejected: {'systolic'},
          scanUsed: scanUsed,
          filledBy: (f) => f == 'height' ? 'manual' : 'empty',
        );

    String outcomeOf(List<AiFieldOutcome> list, String feature, String field) =>
        list.firstWhere((o) => o.feature == feature && o.field == field).outcome;

    test('scribe: kept, edited, rejected and missed', () {
      final list = build();
      expect(outcomeOf(list, AiFeature.scribe, 'systolic'), AiOutcome.kept);
      expect(outcomeOf(list, AiFeature.scribe, 'glucose'), AiOutcome.edited);
      expect(outcomeOf(list, AiFeature.scribe, 'pulse'), AiOutcome.rejected);
      final missed = list.firstWhere((o) => o.field == 'height');
      expect(missed.outcome, AiOutcome.missed);
      expect(missed.filledBy, 'manual');
      expect(list.where((o) => o.feature == AiFeature.cardScan), isEmpty);
    });

    test('card scan: kept, rejected and missed when a scan was applied', () {
      final list = build(scribeUsed: false, scanUsed: true);
      expect(outcomeOf(list, AiFeature.cardScan, 'weight'), AiOutcome.kept);
      expect(outcomeOf(list, AiFeature.cardScan, 'systolic'), AiOutcome.rejected);
      expect(outcomeOf(list, AiFeature.cardScan, 'height'), AiOutcome.missed);
      expect(list.where((o) => o.feature == AiFeature.scribe), isEmpty);
    });

    test('nothing is sent when neither AI feature was used', () {
      expect(build(scribeUsed: false), isEmpty);
    });
  });
}
