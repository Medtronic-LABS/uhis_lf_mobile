/// Field-provenance classification — the buckets the telemetry report counts.
///
/// This is the layer that had no tests and shipped wrong: a hand ground-truth
/// run reported 0 corrections for 2 made, and 16 manual entries for 10 typed.
/// Both causes are pinned here.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/features/scribe/models/ai_extracted_field.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

import '../../../helpers/fake_form_deps.dart';

/// Numeric, extractable field defs — only fields with an extractable widget
/// hint reach the classifier.
Map<String, FieldDef> _defs(List<String> ids, {String programme = 'ncd'}) => {
      for (final id in ids)
        id: FieldDef.fromJson(id, {
          'label': id,
          'widgetHint': 'EditText',
          'programmes': [
            {'id': programme}
          ],
        }),
    };

void main() {
  late FakeAssessmentDraftDao draftDao;
  late UnifiedFormNotifier notifier;
  late Map<String, FieldDef> defs;

  setUp(() {
    draftDao = FakeAssessmentDraftDao();
    notifier = buildTestNotifier(draftDao: draftDao);
  });

  /// Installs [ids] as the notifier's field library and keeps a local copy —
  /// `fieldDefs` is a setter with no getter.
  void useDefs(List<String> ids) {
    defs = _defs(ids);
    notifier.fieldDefs = defs;
  }

  AIExtractedField ai(String id, dynamic value) => AIExtractedField(
        fieldId: id,
        value: value,
        confidence: 1.0,
        source: FieldSource.aiPending,
      );

  group('rule 1 — AI placed, SK edited => corrected', () {
    test('editing an AI-filled field counts as a correction', () {
      useDefs(['weight']);
      notifier.applyAiPrefill([ai('weight', 60)],
          fieldDefs: defs);

      notifier.updateField('weight', 65);

      final b = notifier.classifyFieldProvenance();
      expect(b.aiCorrected, contains('weight'));
      expect(b.manual, isNot(contains('weight')));
      expect(b.aiAcceptedUnchanged, isNot(contains('weight')));
    });

    test('an untouched AI value stays unchanged, not corrected', () {
      useDefs(['weight']);
      notifier.applyAiPrefill([ai('weight', 60)],
          fieldDefs: defs);

      final b = notifier.classifyFieldProvenance();
      expect(b.aiAcceptedUnchanged, contains('weight'));
      expect(b.aiCorrected, isEmpty);
    });

    test('REGRESSION: editing an AI-filled field TWICE stays a correction', () {
      // A device run showed `temperature` edited 12 times landing in `manual`.
      // The transition only recognised `aiPending`, so the FIRST edit set
      // `aiModified` correctly and every edit after it saw a non-aiPending
      // source and downgraded to `manual` — losing the correction.
      useDefs(['weight']);
      notifier.applyAiPrefill([ai('weight', 60)], fieldDefs: defs);

      notifier.updateField('weight', 65);
      notifier.updateField('weight', 66);
      notifier.updateField('weight', 67);

      final b = notifier.classifyFieldProvenance();
      expect(b.aiCorrected, contains('weight'),
          reason: 'still AI-placed-then-SK-changed, however many edits');
      expect(b.manual, isNot(contains('weight')));
    });

    test('REGRESSION: editing a MIRROR of an AI value is still a correction',
        () {
      // The bug: updateField calls the glucose/BP mirror helpers, which write
      // aliases directly without a source. A null source made updateField
      // stamp `manual` instead of `aiModified`, so the correction vanished.
      useDefs(['glucose', 'bloodSugarRandom']);
      notifier.applyAiPrefill([ai('glucose', 7.2)],
          fieldDefs: defs);

      // The SK edits the other programme's name for the same reading.
      notifier.updateField('bloodSugarRandom', 8.1);

      final b = notifier.classifyFieldProvenance();
      final glucoseGroup = {...b.aiCorrected, ...b.manual};
      expect(b.aiCorrected, isNotEmpty,
          reason: 'editing a mirrored AI value must count as a correction');
      expect(glucoseGroup.length, 1,
          reason: 'one clinical value must be classified once, not per alias');
    });
  });

  group('rule 2 — prefilled is neither manual nor AI', () {
    test('a preloaded value is prefilled, not manual', () {
      useDefs(['height']);
      // Simulates preloadBiometrics: a prior visit's height.
      notifier.applyPrefilledForTesting('height', 162);

      final b = notifier.classifyFieldProvenance();
      expect(b.prefilled, contains('height'));
      expect(b.manual, isNot(contains('height')),
          reason: 'a preloaded height is not SK effort');
    });

    test('the SK typing over a prefilled value makes it manual', () {
      useDefs(['height']);
      notifier.applyPrefilledForTesting('height', 162);

      notifier.updateField('height', 165);

      final b = notifier.classifyFieldProvenance();
      expect(b.manual, contains('height'));
      expect(b.prefilled, isEmpty);
    });
  });

  group('rule 3 — SK-typed fields AI never touched are manual', () {
    test('a typed value with no AI involvement is manual', () {
      useDefs(['pulse']);
      notifier.updateField('pulse', 78);

      final b = notifier.classifyFieldProvenance();
      expect(b.manual, contains('pulse'));
      expect(b.aiCorrected, isEmpty);
      expect(b.aiAcceptedUnchanged, isEmpty);
    });

    test('an unfilled field is empty, not manual', () {
      useDefs(['pulse']);
      final b = notifier.classifyFieldProvenance();
      expect(b.empty, contains('pulse'));
      expect(b.manual, isEmpty);
    });
  });

  group('AI overridden — the SK-typed-first case', () {
    test('AI proposing a value the SK already filled is recorded', () {
      useDefs(['weight']);
      notifier.updateField('weight', 60);

      // AI now disagrees; applyAiPrefill refuses to overwrite the SK.
      notifier.applyAiPrefill([ai('weight', 72)],
          fieldDefs: defs);

      expect(notifier.aiOverriddenFieldIds, contains('weight'));
      final b = notifier.classifyFieldProvenance();
      // The SK's value stands, so the field itself is still manual.
      expect(b.manual, contains('weight'));
      expect(b.aiCorrected, isEmpty);
    });
  });

  group('blood pressure — three values, not one', () {
    test('each BP box counts separately and the container does not count', () {
      // A device run counted a whole BP reading as ONE manual field, because
      // systolic/diastolic/pulse were grouped as aliases. They are three
      // distinct measurements and the SK filled three boxes.
      useDefs(['systolic', 'diastolic', 'pulse']);
      notifier.updateField('systolic', 120);
      notifier.updateField('diastolic', 80);
      notifier.updateField('pulse', 72);

      final b = notifier.classifyFieldProvenance();
      expect(b.manual, containsAll(['systolic', 'diastolic', 'pulse']));
      expect(b.manual, isNot(contains('bpLogDetails')),
          reason: 'the container is not a field the SK sees');
    });

    test('editing systolic says nothing about diastolic', () {
      useDefs(['systolic', 'diastolic']);
      notifier.applyAiPrefill([ai('systolic', 120), ai('diastolic', 80)],
          fieldDefs: defs);

      notifier.updateField('systolic', 130);

      final b = notifier.classifyFieldProvenance();
      expect(b.aiCorrected, contains('systolic'));
      expect(b.aiAcceptedUnchanged, contains('diastolic'),
          reason: 'diastolic was never touched');
    });
  });

  group('denominators nest', () {
    test('libraryTotal spans the rendered programmes, not just the active ones',
        () {
      // "Fields rendered" exceeded "Fields in form" on device, which reads as
      // a miscount: activeSections also renders *enrolled* form types, so a
      // combined visit shows sections the active list does not name.
      notifier.fieldDefs = {
        ..._defs(['systolic'], programme: 'ncd'),
        ..._defs(['eyeTestOutcome', 'referPlace'], programme: 'eye_care'),
      };
      notifier.setRenderedFieldStats(
        visibleFieldIds: {'systolic'},
        renderedTotal: 3,
        renderedFormTypes: {'ncd', 'eye_care'},
      );

      final b = notifier.classifyFieldProvenance();
      expect(b.libraryTotal, 3,
          reason: 'must count the eye-care fields the screen rendered');
      expect(b.libraryTotal, greaterThanOrEqualTo(3),
          reason: 'visible <= rendered <= in form must hold');
    });
  });

  group('out-of-programme edits', () {
    test('an edited field outside activeFormTypes still reaches a bucket', () {
      // eyeTestOutcome and referPlace logged a transition on device and then
      // appeared in NO bucket, because the classifier only walked the active
      // programmes. An edit must never vanish from the report.
      notifier.fieldDefs = _defs(['eyeTestOutcome'], programme: 'eye_care');

      notifier.updateField('eyeTestOutcome', 'presbyopia');

      final b = notifier.classifyFieldProvenance();
      expect(b.manual, contains('eyeTestOutcome'));
      // ...but it is not a capture opportunity, so it must not move the rate.
      expect(b.targetIds, isNot(contains('eyeTestOutcome')));
    });
  });

  _draftRoundTripTests();

  group('derived values', () {
    test('a computed value is its own bucket, not manual', () {
      useDefs(['followUpVisit']);
      notifier.applyDerivedForTesting('followUpVisit', '2026-10-06');

      final b = notifier.classifyFieldProvenance();
      expect(b.derived, contains('followUpVisit'));
      expect(b.manual, isNot(contains('followUpVisit')));
    });

    test('bmi is excluded from every bucket', () {
      // _extractionTargets drops `bmi` deliberately — it is computed from
      // height/weight and never spoken, so it is not a capture opportunity.
      useDefs(['height', 'weight', 'bmi']);
      notifier.updateField('height', 160);
      notifier.updateField('weight', 64);

      final b = notifier.classifyFieldProvenance();
      final everywhere = {
        ...b.aiCorrected, ...b.aiAcceptedUnchanged, ...b.manual,
        ...b.prefilled, ...b.derived, ...b.empty,
      };
      expect(everywhere, isNot(contains('bmi')));
      expect(b.manual, containsAll(['height', 'weight']));
    });
  });
}

/// The visit that exposed this ran ~30 minutes and changed programme
/// selection mid-way, which disposes the form screen and builds a NEW
/// notifier. Values survive via the draft; provenance survives only if the
/// draft round-trips it. That link was never tested.
void _draftRoundTripTests() {
  test('a correction survives a notifier rebuild via the draft', () async {
    final draftDao = FakeAssessmentDraftDao();
    final first = buildTestNotifier(draftDao: draftDao);
    final defs = _defs(['temperature']);
    first.fieldDefs = defs;

    first.applyAiPrefill([
      AIExtractedField(
        fieldId: 'temperature',
        value: 102,
        confidence: 1.0,
        source: FieldSource.aiPending,
      )
    ], fieldDefs: defs);
    first.updateField('temperature', 100);
    expect(first.classifyFieldProvenance().aiCorrected, contains('temperature'),
        reason: 'sanity: the flip works before any rebuild');
    await pumpMicrotasks();
    // dispose() cancels the debounce and persists immediately — the same path
    // the real screen takes when programme selection changes.
    first.dispose();
    await pumpMicrotasks();

    // Programme selection changed -> new notifier, same encounter.
    final rebuilt = buildTestNotifier(draftDao: draftDao);
    rebuilt.fieldDefs = defs;
    await rebuilt.loadDraft();

    final b = rebuilt.classifyFieldProvenance();
    expect(b.aiCorrected, contains('temperature'),
        reason: 'the correction must survive the rebuild');
    expect(b.manual, isNot(contains('temperature')));
  });

  test('an AI-overridden field survives a notifier rebuild too', () async {
    // Corrections survived a rebuild but overrides did not: the set was held
    // in memory only, so changing programme selection mid-visit reset the
    // disagreement count to zero.
    final draftDao = FakeAssessmentDraftDao();
    final first = buildTestNotifier(draftDao: draftDao);
    final defs = _defs(['weight']);
    first.fieldDefs = defs;

    first.updateField('weight', 60);
    first.applyAiPrefill([
      AIExtractedField(
        fieldId: 'weight',
        value: 72,
        confidence: 1.0,
        source: FieldSource.aiPending,
      )
    ], fieldDefs: defs);
    expect(first.aiOverriddenFieldIds, contains('weight'));
    await pumpMicrotasks();
    first.dispose();
    await pumpMicrotasks();

    final rebuilt = buildTestNotifier(draftDao: draftDao);
    rebuilt.fieldDefs = defs;
    await rebuilt.loadDraft();

    expect(rebuilt.aiOverriddenFieldIds, contains('weight'),
        reason: 'the disagreement must not be lost to a rebuild');
  });

  test('clearing a field drops it from the AI-overridden set', () {
    // Now that the set is persisted, a value cleared by the hidden-dependent
    // or pregnancy-outcome paths must not keep reporting as a disagreement.
    final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
    final defs = _defs(['weight']);
    n.fieldDefs = defs;

    n.updateField('weight', 60);
    n.applyAiPrefill([
      AIExtractedField(
        fieldId: 'weight',
        value: 72,
        confidence: 1.0,
        source: FieldSource.aiPending,
      )
    ], fieldDefs: defs);
    expect(n.aiOverriddenFieldIds, contains('weight'));

    n.clearPregnancyOutcomeFieldsForTesting({'weight'});

    expect(n.aiOverriddenFieldIds, isNot(contains('weight')));
    expect(n.classifyFieldProvenance().manual, isNot(contains('weight')));
  });

  group('scribe span and outcome', () {
    test('widens the span across several sessions rather than replacing it',
        () {
      // An SK can dictate, review, then dictate again. The report means "when
      // was AI listening for this visit", not "the last time it was".
      final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
      n.markScribeSpan(startedAtMs: 3000, endedAtMs: 4000);
      n.markScribeSpan(startedAtMs: 1000, endedAtMs: 2000);
      n.markScribeSpan(startedAtMs: 5000, endedAtMs: 6000);

      expect(n.scribeStartedAtMsForTesting, 1000, reason: 'earliest start');
      expect(n.scribeEndedAtMsForTesting, 6000, reason: 'latest end');
    });

    test('a fill without timing cannot clear a span already captured', () {
      // An older banner, or a path that never recorded, reports nulls. Those
      // must not erase a real measurement.
      final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
      n.markScribeSpan(startedAtMs: 1000, endedAtMs: 2000);
      n.markScribeSpan(startedAtMs: null, endedAtMs: null);

      expect(n.scribeStartedAtMsForTesting, 1000);
      expect(n.scribeEndedAtMsForTesting, 2000);
    });

    test('outcome is null when AI Scribe never ran', () {
      final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
      expect(n.asrOutcome, isNull);
      expect(n.asrFailureReasons, isNull);
    });

    test('outcome is success when every proposal applied', () {
      final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
      final defs = _defs(['weight']);
      n.fieldDefs = defs;
      n.applyAiPrefill([
        AIExtractedField(
          fieldId: 'weight',
          value: 60,
          confidence: 1.0,
          source: FieldSource.aiPending,
        )
      ], fieldDefs: defs);

      expect(n.asrOutcome, 'success');
      expect(n.asrFailureReasons, isNull);
    });

    test('outcome is partial when some proposals were dropped', () {
      final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
      final defs = _defs(['weight']);
      n.fieldDefs = defs;
      n.applyAiPrefill([
        AIExtractedField(
          fieldId: 'weight',
          value: 60,
          confidence: 1.0,
          source: FieldSource.aiPending,
        ),
        // Not in fieldDefs — rejected as an unsupported field.
        AIExtractedField(
          fieldId: 'notAField',
          value: 1,
          confidence: 1.0,
          source: FieldSource.aiPending,
        ),
      ], fieldDefs: defs);

      expect(n.asrOutcome, 'partial');
      expect(n.asrFailureReasons, contains('unsupported_field'));
    });

    test('outcome is failed when AI ran and nothing stuck', () {
      // Distinct from success-with-nothing-proposed: a bool flag would report
      // both as the same non-event, which is the whole point of the metric.
      final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
      final defs = _defs(['weight']);
      n.fieldDefs = defs;
      n.applyAiPrefill([
        AIExtractedField(
          fieldId: 'notAField',
          value: 1,
          confidence: 1.0,
          source: FieldSource.aiPending,
        ),
      ], fieldDefs: defs);

      expect(n.asrOutcome, 'failed');
    });

    test('failure reasons carry categories only, never field ids', () {
      // These travel to a server and into a report; a field id here would be
      // a quiet widening of what telemetry holds.
      final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
      final defs = _defs(['weight']);
      n.fieldDefs = defs;
      n.applyAiPrefill([
        AIExtractedField(
          fieldId: 'secretFieldName',
          value: 1,
          confidence: 1.0,
          source: FieldSource.aiPending,
        ),
      ], fieldDefs: defs);

      expect(n.asrFailureReasons!.keys, isNot(contains('secretFieldName')));
      expect(n.asrFailureReasons!.keys, everyElement(isNot(contains('Field'))));
    });
  });

  group('value-audit capture is gated off by default', () {
    // AppConfig.valueAuditEnabled is a compile-time --dart-define and cannot
    // be toggled at runtime, so what these tests pin is the DEFAULT: a build
    // without the flag never holds a clinical value, not even in memory. That
    // is the property the PHI argument rests on — if capture ran by default,
    // every build would be collecting values.
    test('editing an AI-filled value captures nothing without the flag', () {
      final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
      final defs = _defs(['systolic']);
      n.fieldDefs = defs;

      n.applyAiPrefill([
        AIExtractedField(
          fieldId: 'systolic',
          value: 160,
          confidence: 1.0,
          source: FieldSource.aiPending,
        )
      ], fieldDefs: defs);
      n.updateField('systolic', 140);

      expect(n.aiProposedValuesForTesting, isEmpty,
          reason: 'a build without VALUE_AUDIT must capture no values');
      // The non-PHI provenance record still works — the correction is counted,
      // only the values are absent.
      expect(n.classifyFieldProvenance().aiCorrected, contains('systolic'));
    });

    test('the capture map is never populated with a manual entry', () {
      final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
      final defs = _defs(['systolic']);
      n.fieldDefs = defs;

      n.updateField('systolic', 140);

      expect(n.aiProposedValuesForTesting, isEmpty,
          reason: 'nothing to audit when AI never proposed a value');
    });
  });
}
