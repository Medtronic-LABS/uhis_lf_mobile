/// Unit tests for Phase S4 AI Scribe pre-fill and triage pre-tick hooks.
///
/// Tests:
///  1. applyScribePrefill populates isScribePreFilled for fields above floor.
///  2. applyScribePrefill skips fields below confidence floor.
///  3. applyScribePrefill does NOT overwrite a field in _skEnteredFields.
///  4. markFieldTouched removes field from isScribePreFilled.
///  5. Race invariant: late-arriving scribe result skips SK-entered fields.
///  6. applyScribeTriageResult pre-ticks codes ≥ floor; skips below-floor.
///  7. SectionRegistry.toScribeSchema deduplicates and maps types correctly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/scribe/form_field_schema_builder.dart';
import 'package:uhis_next/features/scribe/models/ai_extracted_field.dart';
import 'package:uhis_next/features/visit/composer/section_registry.dart';
import 'package:uhis_next/features/visit/composer/sectioned_assessment_screen.dart';
import 'package:uhis_next/features/visit/pathway/pathway_engine.dart';
import 'package:uhis_next/features/visit/triage/patient_context_builder.dart';
import 'package:uhis_next/features/visit/triage/triage_view_model.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Minimal patient context with no pre-ticks (blank slate for scribe tests).
PatientContext _blankContext({String patientId = 'test-patient'}) =>
    PatientContext(
      patientId: patientId,
      ageMonths: 360,
      sex: Sex.female,
      isPregnant: false,
      knownConditions: {},
      activeProgrammes: {},
    );

/// Build a [FormPrefillResult] from a map of fieldId → {value, confidence}.
FormPrefillResult _prefillResult(
  Map<String, ({dynamic value, double confidence})> fields, {
  List<String> unmapped = const [],
}) => FormPrefillResult(
  fields: fields.entries
      .map(
        (e) => AIExtractedField(
          fieldId: e.key,
          value: e.value.value,
          confidence: e.value.confidence,
        ),
      )
      .toList(),
  unmappedFindings: unmapped,
);

/// Build a [TriageExtractionResult] from a map of code → confidence.
TriageExtractionResult _triageResult(Map<String, double> codeConfidences) =>
    TriageExtractionResult(
      symptomCodes: codeConfidences.entries
          .map(
            (e) => AIExtractedField(
              fieldId: e.key,
              value: true,
              confidence: e.value,
            ),
          )
          .toList(),
    );

/// Build an [ActivatedPathway] for [programme].
ActivatedPathway _pathway(Programme programme) => ActivatedPathway(
  programme: programme,
  priority: 10,
  confidence: 1.0,
  trigger: PathwayTrigger.rule,
  rationaleKey: 'test',
);

/// Open an in-memory [AppDatabase] via sqflite_ffi.
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

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ── S4.4 SectionedAssessmentViewModel.applyScribePrefill ─────────────────

  group('SectionedAssessmentViewModel.applyScribePrefill', () {
    late AppDatabase db;
    late SectionedAssessmentViewModel vm;

    setUp(() async {
      db = await _openInMemoryDb();
      vm = SectionedAssessmentViewModel(
        pathways: [_pathway(Programme.imci)],
        encounterId: 'enc-1',
        patientId: 'pat-1',
        householdMemberLocalId: 1,
        draftDao: AssessmentDraftDao(db),
      );
    });

    tearDown(() async {
      vm.dispose();
      await db.close();
    });

    // Test 1 ─────────────────────────────────────────────────────────────────
    test('Test 1 — applyScribePrefill populates isScribePreFilled for fields '
        'above confidence floor (default 0.6)', () {
      vm.applyScribePrefill(
        _prefillResult({
          'temperature': (value: 37.2, confidence: 0.85),
          'hasCough': (value: true, confidence: 0.75),
        }),
      );

      expect(vm.isScribePreFilled('temperature'), isTrue);
      expect(vm.isScribePreFilled('hasCough'), isTrue);
      expect(vm.fieldValues['temperature'], equals(37.2));
      expect(vm.fieldValues['hasCough'], isTrue);
    });

    // Test 2 ─────────────────────────────────────────────────────────────────
    test('Test 2 — applyScribePrefill skips fields below confidence floor', () {
      vm.applyScribePrefill(
        _prefillResult({
          'temperature': (value: 37.5, confidence: 0.9),
          'hasFever': (value: true, confidence: 0.3), // below floor of 0.6
        }),
      );

      expect(vm.isScribePreFilled('temperature'), isTrue);
      expect(
        vm.isScribePreFilled('hasFever'),
        isFalse,
        reason: 'Confidence 0.3 < floor 0.6 — must be skipped',
      );
      expect(vm.fieldValues.containsKey('hasFever'), isFalse);
    });

    // Test 3 ─────────────────────────────────────────────────────────────────
    test('Test 3 — applyScribePrefill does NOT overwrite a field already '
        'touched by the SK', () {
      // SK sets temperature manually first.
      vm.setFieldValue('temperature', 38.1);
      vm.markFieldTouched('temperature');

      // Scribe arrives with a different value.
      vm.applyScribePrefill(
        _prefillResult({'temperature': (value: 36.6, confidence: 0.95)}),
      );

      // SK value wins.
      expect(
        vm.fieldValues['temperature'],
        equals(38.1),
        reason: 'SK-entered field must never be overwritten by scribe',
      );
      expect(vm.isScribePreFilled('temperature'), isFalse);
    });

    // Test 4 ─────────────────────────────────────────────────────────────────
    test('Test 4 — markFieldTouched removes field from isScribePreFilled', () {
      vm.applyScribePrefill(
        _prefillResult({'hasCough': (value: true, confidence: 0.8)}),
      );
      expect(vm.isScribePreFilled('hasCough'), isTrue);

      vm.markFieldTouched('hasCough');

      expect(
        vm.isScribePreFilled('hasCough'),
        isFalse,
        reason: 'After SK touches the field the pre-fill badge must clear',
      );
    });

    // Test 5 ─────────────────────────────────────────────────────────────────
    test('Test 5 — Race invariant: late-arriving scribe result still skips '
        'SK-entered fields', () {
      // SK fills temperature before scribe result arrives.
      vm.setFieldValue('temperature', 38.0);
      vm.markFieldTouched('temperature');

      // Delayed scribe result arrives later.
      vm.applyScribePrefill(
        _prefillResult({
          'temperature': (value: 36.5, confidence: 0.9),
          'hasCough': (value: true, confidence: 0.8),
        }),
      );

      expect(
        vm.fieldValues['temperature'],
        equals(38.0),
        reason: 'Race invariant: SK-entered field is never overwritten',
      );
      expect(vm.isScribePreFilled('hasCough'), isTrue);
      expect(vm.fieldValues['hasCough'], isTrue);
    });
  });

  // ── S4.3 TriageViewModel.applyScribeTriageResult ──────────────────────────

  group('TriageViewModel.applyScribeTriageResult', () {
    late TriageViewModel vm;

    setUp(() {
      vm = TriageViewModel(patientContext: _blankContext());
    });

    tearDown(() => vm.dispose());

    // Test 6 ─────────────────────────────────────────────────────────────────
    test('Test 6 — applyScribeTriageResult pre-ticks codes ≥ confidence floor '
        'when the code is in the AI Scribe vocab; skips below-floor codes and '
        'codes outside the vocab', () {
      vm.applyScribeTriageResult(
        _triageResult({
          'fever': 0.85, // in vocab → kept
          'abdominal_pain': 0.90, // in vocab → kept
          'heavy_bleeding': 0.95, // in vocab → kept (vocab is source of truth)
          'cough': 0.95, // NOT in AI triage vocab → skip
          'diarrhea': 0.50, // below floor → skip
        }),
      );

      expect(vm.isScribePreTick('fever'), isTrue);
      expect(
        vm.isSelected('fever'),
        isTrue,
        reason: 'Pre-ticked codes are also selected',
      );

      expect(vm.isScribePreTick('abdominal_pain'), isTrue);
      expect(vm.isSelected('abdominal_pain'), isTrue);

      expect(
        vm.isScribePreTick('heavy_bleeding'),
        isTrue,
        reason: 'heavy_bleeding is in AiScribeTriageVocab — Step 1 source of '
            'truth — and must be surfaced as a chip',
      );
      expect(vm.isSelected('heavy_bleeding'), isTrue);

      expect(
        vm.isScribePreTick('cough'),
        isFalse,
        reason: 'Cough is outside the constrained 32-code scribe vocabulary',
      );
      expect(vm.isSelected('cough'), isFalse);

      expect(
        vm.isScribePreTick('diarrhea'),
        isFalse,
        reason: 'Confidence 0.50 < floor 0.70',
      );
      expect(vm.isSelected('diarrhea'), isFalse);
    });

    test(
      'Test 6b — SK can freely untick a scribe-pre-ticked symptom without alert',
      () {
        vm.applyScribeTriageResult(_triageResult({'fever': 0.9}));
        expect(vm.isSelected('fever'), isTrue);

        vm.toggleSymptom('fever'); // SK unticks

        expect(
          vm.isSelected('fever'),
          isFalse,
          reason: 'SK untick must be respected with no guard or alert',
        );
      },
    );
  });

  // ── S4.1 SectionRegistry.toScribeSchema ──────────────────────────────────

  group('SectionRegistry.toScribeSchema', () {
    // Test 7 ─────────────────────────────────────────────────────────────────
    test(
      'Test 7 — toScribeSchema([vitals, symptom-detail]) returns deduplicated '
      'field list with correct type mappings',
      () {
        final vitals = SectionRegistry.byId('vitals')!;
        final symptomDetail = SectionRegistry.byId('symptom-detail')!;

        final schema = SectionRegistry.toScribeSchema([vitals, symptomDetail]);

        // Every fieldId appears exactly once.
        final ids = schema.map((s) => s.fieldId).toList();
        expect(
          ids.toSet().length,
          equals(ids.length),
          reason: 'No duplicate fieldIds in schema',
        );

        // temperature → decimal (doubleField)
        final tempSchema = schema.firstWhere((s) => s.fieldId == 'temperature');
        expect(
          tempSchema.type,
          equals(FieldType.decimal),
          reason: 'doubleField maps to FieldType.decimal',
        );

        // hasCough → boolean (booleanField)
        final coughSchema = schema.firstWhere((s) => s.fieldId == 'hasCough');
        expect(
          coughSchema.type,
          equals(FieldType.boolean),
          reason: 'booleanField maps to FieldType.boolean',
        );

        // All expected fieldIds present.
        expect(
          ids,
          containsAll([
            'temperature',
            'breathsPerMinute',
            'weightKg',
            'muacCm',
            'spo2',
            'hasCough',
            'coughDays',
            'hasFever',
            'feverDays',
            'hasDiarrhea',
          ]),
        );
      },
    );

    test(
      'rdtResult (selectField) maps to FieldType.enumType with allowedValues',
      () {
        final iccmClassify = SectionRegistry.byId('iccm-classify')!;
        final schema = SectionRegistry.toScribeSchema([iccmClassify]);

        final rdtSchema = schema.firstWhere((s) => s.fieldId == 'rdtResult');
        expect(rdtSchema.type, equals(FieldType.enumType));
        expect(
          rdtSchema.allowedValues,
          containsAll(['positive', 'negative', 'not_done']),
        );
      },
    );

    test('ncdSymptoms (multiSelectField) maps to FieldType.enumType', () {
      final ncdHtn = SectionRegistry.byId('ncd-htn')!;
      final schema = SectionRegistry.toScribeSchema([ncdHtn]);

      final symptomsSchema = schema.firstWhere(
        (s) => s.fieldId == 'ncdSymptoms',
      );
      expect(symptomsSchema.type, equals(FieldType.enumType));
    });

    test(
      'toScribeSchema deduplicates shared fields across overlapping sections',
      () {
        // hasCough appears in both symptom-detail AND tb-screen-detail.
        final symptomDetail = SectionRegistry.byId('symptom-detail')!;
        final tbDetail = SectionRegistry.byId('tb-screen-detail')!;

        final schema = SectionRegistry.toScribeSchema([
          symptomDetail,
          tbDetail,
        ]);

        final hasCoughCount = schema
            .where((s) => s.fieldId == 'hasCough')
            .length;
        expect(
          hasCoughCount,
          equals(1),
          reason: 'hasCough is shared — must appear exactly once',
        );
      },
    );

    test('FormFieldSchemaBuilder.forProgramme delegates to SectionRegistry '
        'and returns non-empty schema with correct types for IMCI', () {
      final schema = FormFieldSchemaBuilder.forProgramme(Programme.imci);
      expect(schema, isNotEmpty);

      final temp = schema.firstWhere(
        (s) => s.fieldId == 'temperature',
        orElse: () =>
            throw TestFailure('temperature field not found in IMCI schema'),
      );
      expect(temp.type, equals(FieldType.decimal));
    });

    test(
      'FormFieldSchemaBuilder.forProgrammes deduplicates across programmes',
      () {
        final schema = FormFieldSchemaBuilder.forProgrammes([
          Programme.imci,
          Programme.tb,
        ]);

        final ids = schema.map((s) => s.fieldId).toList();
        expect(
          ids.toSet().length,
          equals(ids.length),
          reason: 'No duplicate fieldIds when merging IMCI + TB',
        );
      },
    );
  });
}
