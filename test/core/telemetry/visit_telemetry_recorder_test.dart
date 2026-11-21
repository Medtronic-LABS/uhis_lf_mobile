/// Unit tests for [VisitTelemetryRecorder] — the state behind the
/// one-row-per-visit telemetry event.
///
/// A fake clock drives every test, so the timing rules (active time pauses
/// in the background, a revisit adds instead of resetting, the Sukhee screen
/// is not Step 3 time) are checked to the millisecond.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/telemetry/visit_telemetry_recorder.dart';

class _Clock {
  int now = 1000000;
  int call() => now;
  void advance(int ms) => now += ms;
}

void main() {
  late _Clock clock;
  late VisitTelemetryRecorder r;

  setUp(() {
    clock = _Clock();
    r = VisitTelemetryRecorder(visitUuid: 'v-1', clock: clock.call);
  });

  test('a fresh visit is in progress on step 1 with no step blocks', () {
    r.enterStep(1);
    final p = r.toPayload();
    expect(p['status'], VisitTelemetryStatus.inProgress);
    expect(p['lastStep'], 1);
    expect(p['visitStartTime'], 1000000);
    expect(p.containsKey('visitEndTime'), isFalse);
    expect(p.containsKey('step1'), isFalse);
    expect(p.containsKey('fields'), isFalse);
  });

  test('a forward move finishes the step and is a save point', () {
    expect(r.enterStep(1), isFalse, reason: 'first entry is not a save');
    clock.advance(5000);
    expect(r.enterStep(2), isTrue);
    expect(r.enterStep(2), isFalse, reason: 'same step is a no-op');

    final step1 = r.toPayload()['step1'] as Map;
    expect(step1['startTime'], 1000000);
    expect(step1['endTime'], 1005000);
    expect(step1['activeMs'], 5000);
    expect(r.lastStep, 2);
  });

  test('backgrounding pauses active time but not wall-clock time', () {
    r.enterStep(1);
    clock.advance(3000);
    r.pause(VisitTelemetryPause.background);
    clock.advance(60000);
    r.resume(VisitTelemetryPause.background);
    clock.advance(2000);
    r.enterStep(2);

    final step1 = r.toPayload()['step1'] as Map;
    expect(step1['activeMs'], 5000);
    expect(step1['endTime'] - step1['startTime'], 65000);
  });

  test('going back to step 1 adds to its time instead of resetting it', () {
    r.enterStep(1);
    clock.advance(4000);
    r.enterStep(2);
    clock.advance(1000);
    expect(r.enterStep(1), isFalse, reason: 'backward is not a save');
    clock.advance(6000);
    r.enterStep(2);

    final p = r.toPayload();
    final step1 = p['step1'] as Map;
    expect(step1['activeMs'], 10000);
    expect(step1['startTime'], 1000000);
    expect(step1['endTime'], 1011000,
        reason: 'ends when the SK last moved on, not the first time');
    expect(step1['endTime'] - step1['startTime'],
        greaterThanOrEqualTo(step1['activeMs']));
    expect(p['visitActiveMs'], 11000);
  });

  test('overlapping pauses resume only when all are lifted', () {
    r.enterStep(3);
    r.pause(VisitTelemetryPause.teleconsult);
    r.pause(VisitTelemetryPause.background);
    clock.advance(10000);
    r.resume(VisitTelemetryPause.background);
    clock.advance(10000);
    r.resume(VisitTelemetryPause.teleconsult);
    clock.advance(1000);
    r.complete();

    expect((r.toPayload()['step3'] as Map)['activeMs'], 1000);
  });

  test('complete closes the visit and writes the current step', () {
    r.enterStep(1);
    clock.advance(1000);
    r.enterStep(2);
    clock.advance(2000);
    r.enterStep(3);
    clock.advance(3000);
    r.complete(referralRecommended: true);

    final p = r.toPayload();
    expect(p['status'], VisitTelemetryStatus.completed);
    expect(p['lastStep'], 3);
    expect(p['visitEndTime'], 1006000);
    expect(p['visitDurationMs'], 6000);
    expect(p['visitActiveMs'], 6000);
    expect((p['step3'] as Map)['endTime'], 1006000);
    expect((p['step3'] as Map)['referralRecommended'], isTrue);
    expect(r.isOpen, isFalse);
  });

  test('abandon keeps finished steps only and stops the clock', () {
    r.enterStep(1);
    clock.advance(1000);
    r.enterStep(2);
    clock.advance(500);
    r.abandon();
    clock.advance(99999);

    final p = r.toPayload();
    expect(p['status'], VisitTelemetryStatus.abandoned);
    expect(p['lastStep'], 2);
    expect(p.containsKey('step1'), isTrue);
    expect(p.containsKey('step2'), isFalse);
    expect(p['visitActiveMs'], 1500);
    expect(p['visitDurationMs'], 1500);
  });

  test('leaving on step 3 still writes step 3, Sukhee and shares included',
      () {
    r.enterStep(1);
    r.enterStep(2);
    r.enterStep(3);
    r.markShukiStarted();
    clock.advance(60000);
    r.markShukiEnded();
    r.addShare(
      channel: 'sms',
      surface: 'visitFlow',
      hasMessage: true,
      launched: true,
    );
    clock.advance(1000);
    r.abandon();

    final p = r.toPayload();
    expect(p['status'], VisitTelemetryStatus.abandoned);
    final s3 = p['step3'] as Map;
    expect(s3['endTime'], p['visitEndTime']);
    expect(s3['isShukiUsed'], isTrue);
    expect(s3['shukiDurationMs'], 60000);
    expect(s3['communicationShares'], hasLength(1));
    expect(s3.containsKey('referralRecommended'), isFalse,
        reason: 'only known at Done');
  });

  test('nothing changes after the visit is closed', () {
    r.enterStep(1);
    r.abandon();
    r.complete();
    expect(r.status, VisitTelemetryStatus.abandoned);
    expect(r.enterStep(2), isFalse);
  });

  group('step 1', () {
    test('splits symptoms into manual, scribe and deselected', () {
      r.enterStep(1);
      r.recordStep1Symptoms(
        selected: {'headache', 'blurred_vision', 'swelling'},
        scribeAdded: {'headache', 'blurred_vision', 'fever'},
        scribeDeselected: {'fever'},
      );
      r.markStep1ScribeSpan(startedAtMs: 1000, endedAtMs: 31000);
      r.markStep1ScribeSpan(startedAtMs: 5000, endedAtMs: 46000);
      r.enterStep(2);

      final s = r.toPayload()['step1'] as Map;
      expect(s['symptomsManual'], ['swelling']);
      expect(s['symptomsScribe'], ['blurred_vision', 'headache']);
      expect(s['symptomsDeselected'], ['fever']);
      expect(s['inputMode'], VisitTelemetryInputMode.mixed);
      expect(s['scribeUsed'], isTrue);
      expect(s['scribeDurationMs'], 45000);
    });

    test('manual-only step 1', () {
      r.enterStep(1);
      r.recordStep1Symptoms(
        selected: {'headache'},
        scribeAdded: const {},
        scribeDeselected: const {},
      );
      r.enterStep(2);

      final s = r.toPayload()['step1'] as Map;
      expect(s['inputMode'], VisitTelemetryInputMode.manual);
      expect(s['scribeUsed'], isFalse);
      expect(s['scribeDurationMs'], 0);
    });
  });

  group('step 2', () {
    final existing = {
      'programmes': ['anc'],
      'scribeUsed': true,
      'scanUsed': false,
      'durationMs': 373000,
      'fields': {
        'aiFilled': ['systolic'],
        'manual': ['weight'],
      },
      'denominators': {'libraryTotal': 42},
      'scribeStartedAt': 2000,
      'scribeEndedAt': 102000,
      'outcome': 'success',
    };

    test('carries the visit_completed payload verbatim at the top level', () {
      r.enterStep(1);
      r.setProgrammes(['anc', 'ncd']);
      r.enterStep(2);
      r.recordStep2VisitCompleted(existing);
      r.enterStep(3);

      final p = r.toPayload();
      for (final key in existing.keys) {
        expect(p[key], existing[key], reason: key);
      }
      expect(p['programmes'], ['anc'],
          reason: 'the existing key is never overwritten');
      final s = p['step2'] as Map;
      expect(s['inputMode'], VisitTelemetryInputMode.mixed);
      expect(s['scribeDurationMs'], 100000);
    });

    test('flow programmes stand in when there is no form payload', () {
      r.enterStep(1);
      r.setProgrammes(['epi']);
      r.enterStep(2);
      r.enterStep(3);
      final p = r.toPayload();
      expect(p['programmes'], ['epi']);
      expect(p.containsKey('fields'), isFalse);
      expect((p['step2'] as Map).containsKey('inputMode'), isFalse);
    });

    test('only applied scans count toward scan time; every open is an attempt',
        () {
      r.enterStep(2);
      final cancelled = r.ocrScanOpened();
      clock.advance(20000);
      r.ocrScanClosed(cancelled, applied: false);
      final ok = r.ocrScanOpened();
      clock.advance(105000);
      r.ocrScanClosed(ok, applied: true);
      r.enterStep(3);

      final s = r.toPayload()['step2'] as Map;
      expect(s['ocrScanAttempts'], 2);
      expect(s['ocrScanTimeMs'], 105000);
    });
  });

  group('EPI card scan', () {
    test('an EPI-only visit reports scanUsed and the doses filled by scan', () {
      r.enterStep(1);
      r.setProgrammes(['epi']);
      r.enterStep(2);
      final opened = r.ocrScanOpened();
      clock.advance(30000);
      r.ocrScanClosed(opened, applied: true);
      r.markEpiScanFilled('PENTA_2');
      r.markEpiScanFilled('BCG');
      r.enterStep(3);

      final p = r.toPayload();
      expect(p['scanUsed'], isTrue);
      expect((p['fields'] as Map)['scanFilled'], ['BCG', 'PENTA_2']);
      expect((p['step2'] as Map)['ocrScanTimeMs'], 30000);
    });

    test('a scan that applied nothing leaves no scan keys', () {
      r.enterStep(2);
      final opened = r.ocrScanOpened();
      r.ocrScanClosed(opened, applied: false);
      r.enterStep(3);
      final p = r.toPayload();
      expect(p.containsKey('scanUsed'), isFalse);
      expect(p.containsKey('fields'), isFalse);
    });

    test('in a combined visit EPI doses never alter the form\'s keys', () {
      r.enterStep(2);
      final opened = r.ocrScanOpened();
      r.ocrScanClosed(opened, applied: true);
      r.markEpiScanFilled('OPV_1');
      r.recordStep2VisitCompleted({
        'scanUsed': false,
        'fields': {
          'manual': ['weight'],
        },
      });
      r.enterStep(3);

      final p = r.toPayload();
      expect(p['scanUsed'], isFalse);
      expect(p['fields'], {
        'manual': ['weight'],
      });
      expect((p['step2'] as Map)['epiScanFilled'], ['OPV_1']);
    });

    test('a form-only visit keeps the form\'s own scan keys untouched', () {
      r.enterStep(2);
      final opened = r.ocrScanOpened();
      r.ocrScanClosed(opened, applied: true);
      r.recordStep2VisitCompleted({
        'scanUsed': false,
        'fields': {'manual': <String>[]},
      });
      r.enterStep(3);
      final p = r.toPayload();
      expect(p['scanUsed'], isFalse);
      expect((p['fields'] as Map).containsKey('scanFilled'), isFalse);
    });
  });

  group('step 3', () {
    test('records message timing, source, shares, vote and Sukhee', () {
      r.enterStep(3);
      r.markWhatsappRequested();
      clock.advance(3000);
      r.markWhatsappReturned(VisitTelemetryMessageSource.online);
      r.addShare(
        channel: 'whatsapp',
        surface: 'visitFlow',
        hasMessage: true,
        launched: true,
      );
      r.isHelpful = 'down';
      r.isHelpful = 'up';
      r.markShukiEnded(); // before start: ignored
      r.markShukiStarted();
      clock.advance(160000);
      r.markShukiEnded();
      clock.advance(5000);
      r.markShukiEnded(); // second end: ignored
      r.complete(referralRecommended: false);

      final s = r.toPayload()['step3'] as Map;
      expect(s['whatsappMessageEndTime'] - s['whatsappMessageStartTime'], 3000);
      expect(s['whatsappMessageSource'], 'online');
      expect((s['communicationShares'] as List).single['channel'], 'whatsapp');
      expect(s['isHelpful'], 'up');
      expect(s['isShukiUsed'], isTrue);
      expect(s['shukiDurationMs'], 160000);
      expect(s['referralRecommended'], isFalse);
    });

    test('no call means isShukiUsed false and no call times', () {
      r.enterStep(3);
      r.complete();
      final s = r.toPayload()['step3'] as Map;
      expect(s['isShukiUsed'], isFalse);
      expect(s.containsKey('shukiStartTime'), isFalse);
      expect(s['communicationShares'], isEmpty);
    });
  });

  test('payload carries no patient-identifying keys', () {
    r.enterStep(1);
    r.enterStep(2);
    r.enterStep(3);
    r.complete();
    final keys = <String>{};
    void collect(Object? v) {
      if (v is Map) {
        for (final e in v.entries) {
          keys.add('${e.key}');
          collect(e.value);
        }
      } else if (v is List) {
        v.forEach(collect);
      }
    }

    collect(r.toPayload());
    for (final banned in const [
      'patientId',
      'memberId',
      'encounterId',
      'transcript',
      'whatsappMessage',
      'referralRecommendationText',
    ]) {
      expect(keys, isNot(contains(banned)), reason: banned);
    }
  });
}
