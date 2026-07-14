/// Unit tests for the realtime-ASR auto-fill safety gate in
/// [UnifiedFormNotifier] — the guard between the AI service and the form.
///
/// Covers:
///  1. applyAiPrefill applies a valid value and marks it aiPending.
///  2. SK-typed (manual) values are never overwritten by AI.
///  3. SK-edited AI values (aiModified) are never overwritten by AI.
///  4. AI-over-AI refresh of aiPending values IS allowed.
///  5. Enum validation: bad value rejected + reported; display name → id.
///  6. dialogCheckbox list validation (one bad entry rejects the set).
///  7. bpLogDetails shape validation.
///  8. Draft persistence round-trips fieldSources (restore keeps aiPending).
///  9. assessmentTypeFor mapper: anc > ncd priority, pnc → null.
/// 10. updateField flips aiPending → aiModified.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/features/scribe/form_field_schema_builder.dart';
import 'package:uhis_next/features/scribe/models/ai_extracted_field.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

import '../../../helpers/fake_form_deps.dart';

// ── Canonical-style field defs (mirror field_library.json shapes) ─────────────

Map<String, FieldDef> _fieldDefs() => {
      'weight': FieldDef.fromJson('weight', {
        'label': 'Weight',
        'widgetHint': 'EditText',
        'programmes': [
          {'id': 'ncd'}
        ],
      }),
      'glucoseType': FieldDef.fromJson('glucoseType', {
        'label': 'Glucose Test Type',
        'widgetHint': 'BloodGlucoseEntry',
        'optionsList': [
          {'id': 'fbs', 'name': 'Fasting'},
          {'id': 'rbs', 'name': 'Random'},
        ],
        'programmes': [
          {'id': 'ncd'}
        ],
      }),
      'isRegularSmoker': FieldDef.fromJson('isRegularSmoker', {
        'label': 'Regular Smoker',
        'widgetHint': 'SingleSelectionView',
        'optionsList': [
          {'id': true, 'name': 'Yes'},
          {'id': false, 'name': 'No'},
        ],
        'programmes': [
          {'id': 'ncd'}
        ],
      }),
      'postpartumDangerSigns': FieldDef.fromJson('postpartumDangerSigns', {
        'label': 'Postpartum Danger Signs',
        'widgetHint': 'DialogCheckbox',
        'optionsList': [
          {'id': 1, 'name': 'Heavy vaginal bleeding'},
          {'id': 2, 'name': 'Fever'},
          {'id': 3, 'name': 'Severe headache'},
        ],
        'programmes': [
          {'id': 'pncMother'}
        ],
      }),
      'bpLogDetails': FieldDef.fromJson('bpLogDetails', {
        'label': 'BP Readings',
        'widgetHint': 'BP',
        'programmes': [
          {'id': 'ncd'}
        ],
      }),
    };

AIExtractedField _ai(String fieldId, dynamic value, {String? segment}) =>
    AIExtractedField(
      fieldId: fieldId,
      value: value,
      confidence: 1.0,
      sourceSegment: segment,
    );

void main() {
  late FakeAssessmentDraftDao draftDao;
  late UnifiedFormNotifier notifier;

  setUp(() {
    draftDao = FakeAssessmentDraftDao();
    notifier = buildTestNotifier(draftDao: draftDao);
  });

  // updateField()/applyAiPrefill() schedule a debounced autosave Timer;
  // dispose() flushes-or-cancels it so it can't fire after the test (and
  // its FakeAsync zone) has already completed.
  tearDown(() => notifier.dispose());

  group('applyAiPrefill — apply + provenance', () {
    test('valid numeric value applies and is marked aiPending', () {
      final rejected = notifier.applyAiPrefill(
        [_ai('weight', 72, segment: 'ওজন ৭২ কেজি')],
        fieldDefs: _fieldDefs(),
      );

      expect(rejected, isEmpty);
      expect(notifier.data.getValue('weight'), 72);
      expect(notifier.fieldSource('weight'), FieldSource.aiPending);
      expect(notifier.fieldSourceSegment('weight'), 'ওজন ৭২ কেজি');
    });

    test('numeric string is coerced to num', () {
      notifier.applyAiPrefill(
        [_ai('weight', '72.5')],
        fieldDefs: _fieldDefs(),
      );
      expect(notifier.data.getValue('weight'), 72.5);
    });
  });

  group('applyAiPrefill — SK always wins', () {
    test('manual value is never overwritten', () {
      notifier.updateField('weight', 68);

      final rejected = notifier.applyAiPrefill(
        [_ai('weight', 99)],
        fieldDefs: _fieldDefs(),
      );

      expect(rejected, isEmpty); // skipped silently, not an error
      expect(notifier.data.getValue('weight'), 68);
      expect(notifier.fieldSource('weight'), FieldSource.manual);
    });

    test('aiModified value is never overwritten', () {
      notifier.applyAiPrefill([_ai('weight', 70)], fieldDefs: _fieldDefs());
      notifier.updateField('weight', 71); // SK edits the AI fill
      expect(notifier.fieldSource('weight'), FieldSource.aiModified);

      notifier.applyAiPrefill([_ai('weight', 99)], fieldDefs: _fieldDefs());
      expect(notifier.data.getValue('weight'), 71);
    });

    test('AI-over-AI refresh of aiPending IS allowed', () {
      notifier.applyAiPrefill([_ai('weight', 70)], fieldDefs: _fieldDefs());
      notifier.applyAiPrefill([_ai('weight', 72)], fieldDefs: _fieldDefs());

      expect(notifier.data.getValue('weight'), 72);
      expect(notifier.fieldSource('weight'), FieldSource.aiPending);
    });
  });

  group('applyAiPrefill — schema validation', () {
    test('invalid enum value rejected and reported', () {
      final rejected = notifier.applyAiPrefill(
        [_ai('glucoseType', 'postprandial')],
        fieldDefs: _fieldDefs(),
      );

      expect(rejected, hasLength(1));
      expect(rejected.single, contains('Glucose Test Type'));
      expect(notifier.data.getValue('glucoseType'), isNull);
      expect(notifier.fieldSource('glucoseType'), isNull);
    });

    test('enum display name maps to option id', () {
      notifier.applyAiPrefill(
        [_ai('glucoseType', 'Fasting')],
        fieldDefs: _fieldDefs(),
      );
      expect(notifier.data.getValue('glucoseType'), 'fbs');
    });

    test('boolean-id enum accepts stringified id', () {
      notifier.applyAiPrefill(
        [_ai('isRegularSmoker', 'true')],
        fieldDefs: _fieldDefs(),
      );
      expect(notifier.data.getValue('isRegularSmoker'), 'true');
    });

    test('unknown fieldId rejected and reported', () {
      final rejected = notifier.applyAiPrefill(
        [_ai('notARealField', 42)],
        fieldDefs: _fieldDefs(),
      );
      expect(rejected.single, contains('unknown field'));
    });

    test('dialogCheckbox: display names map to ids', () {
      notifier.applyAiPrefill(
        [
          _ai('postpartumDangerSigns', ['Fever', 'Severe headache'])
        ],
        fieldDefs: _fieldDefs(),
      );
      expect(notifier.data.getValue('postpartumDangerSigns'), ['2', '3']);
    });

    test('dialogCheckbox: one bad entry rejects the whole set', () {
      final rejected = notifier.applyAiPrefill(
        [
          _ai('postpartumDangerSigns', ['Fever', 'Not a danger sign'])
        ],
        fieldDefs: _fieldDefs(),
      );
      expect(rejected, hasLength(1));
      expect(notifier.data.getValue('postpartumDangerSigns'), isNull);
    });

    test('bpLogDetails: valid readings pass, junk rejected', () {
      notifier.applyAiPrefill(
        [
          _ai('bpLogDetails', [
            {'systolic': 160, 'diastolic': 90}
          ])
        ],
        fieldDefs: _fieldDefs(),
      );
      expect(
        notifier.data.getValue('bpLogDetails'),
        [
          {'systolic': 160, 'diastolic': 90}
        ],
      );

      final rejected = notifier.applyAiPrefill(
        [
          _ai('bpLogDetails', ['not-a-reading'])
        ],
        fieldDefs: _fieldDefs(),
      );
      expect(rejected, hasLength(1));
    });
  });

  group('draft persistence of provenance', () {
    test('fieldSources round-trip through the draft row', () async {
      notifier.applyAiPrefill(
        [_ai('weight', 72, segment: 'ওজন ৭২')],
        fieldDefs: _fieldDefs(),
      );
      notifier.updateField('glucoseType', 'fbs'); // manual entry
      // Autosave is debounced (~400ms) — wait it out rather than pumping
      // microtasks, since the write hasn't been scheduled yet at that point.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final saved = draftDao.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.fieldSources, isNotNull);

      // Fresh notifier restores from the same draft row.
      final restoredDao = FakeAssessmentDraftDao()..seed(saved);
      final restored = buildTestNotifier(draftDao: restoredDao);
      await restored.loadDraft();

      expect(restored.fieldSource('weight'), FieldSource.aiPending);
      expect(restored.fieldSourceSegment('weight'), 'ওজন ৭২');
      expect(restored.fieldSource('glucoseType'), FieldSource.manual);

      // Restored AI-pending field still cannot be beaten by manual… but a
      // restored manual field still blocks AI.
      restored.applyAiPrefill(
        [_ai('glucoseType', 'rbs')],
        fieldDefs: _fieldDefs(),
      );
      expect(restored.data.getValue('glucoseType'), 'fbs');
    });
  });

  group('assessmentTypeFor mapper', () {
    test('ncd-only visit → ncd', () {
      expect(FormFieldSchemaBuilder.assessmentTypeFor(['ncd']), 'ncd');
    });

    test('anc outranks ncd in combined visits', () {
      expect(
          FormFieldSchemaBuilder.assessmentTypeFor(['ncd', 'anc']), 'anc');
    });

    test('pnc (any expansion) disables auto-fill', () {
      expect(FormFieldSchemaBuilder.assessmentTypeFor(['pnc']), isNull);
      expect(
        FormFieldSchemaBuilder.assessmentTypeFor(
            ['pncMother', 'pncChild', 'ncd']),
        isNull,
      );
    });

    test('unsupported programmes → null', () {
      expect(FormFieldSchemaBuilder.assessmentTypeFor(['tb']), isNull);
      expect(FormFieldSchemaBuilder.assessmentTypeFor([]), isNull);
    });
  });
}
