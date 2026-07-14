/// Tests for the conditional-visibility engine (`FieldVisibilityRules` +
/// `FormConfig.buildVisibilityRules`) that replaces the previously-discarded
/// `condition`/`visibility`/`compositeGroup` data from `field_library.json`.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_section_rules.dart';

FieldDef _fieldDef(String id, Map<String, dynamic> json) =>
    FieldDef.fromJson(id, json);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FormConfig.load against the real field_library.json', () {
    test('parses the real obstetric-history chain and pncNeonateSigns condition', () async {
      final config = await FormConfig.load(rootBundle);

      final gravida = config.fields['gravida']!;
      final parity = config.fields['parity']!;
      final livingChildren = config.fields['livingChildren']!;
      final ageOfLastChild = config.fields['ageOfLastChild']!;

      expect(gravida.compositeGroup, 'obstetricHistory');
      expect(gravida.compositeRole, 'trigger');
      expect(parity.compositeGroup, 'obstetricHistory');
      expect(parity.compositeRole, 'member');
      expect(livingChildren.compositeRole, 'member');
      expect(ageOfLastChild.compositeRole, 'member');

      // The real condition array on pncNeonateSigns should reveal
      // otherPncNeonateSigns when its value is "Other".
      final rules = config.visibilityRulesByTargetId['otherPncNeonateSigns'];
      expect(rules, isNotNull);
      expect(
        rules!.any((r) => r.driverId == 'pncNeonateSigns' && r.eq == 'Other'),
        isTrue,
      );

      // End-to-end: a first pregnancy hides Parity; a real driver-condition
      // field stays hidden until its trigger value is entered.
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: parity,
          data: const CanonicalVisitData({'gravida': 1}),
          rulesByTargetId: config.visibilityRulesByTargetId,
        ),
        isFalse,
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: config.fields['otherPncNeonateSigns']!,
          data: const CanonicalVisitData({'pncNeonateSigns': 'Other'}),
          rulesByTargetId: config.visibilityRulesByTargetId,
        ),
        isTrue,
      );
    });

    // Regression test: `isBeforeDiabetesDiagnosis` / `glucoseType` /
    // `isBeforeHtnDiagnosis` / `isRegularSmoker` were gated behind a
    // `ncdServiceProvided` condition, but that driver field only exists in
    // the `cataract` form's own section — it's never part of the `ncd`
    // formType's fieldRefs, so in a standalone NCD visit it can never be
    // answered, which made these 4 fields permanently unreachable (empty
    // Diabetes section, missing questions in the Blood Pressure section).
    // Their base `visibility` was changed to "visible" since they're core
    // NCD-programme questions, not gated behind a cataract-only toggle.
    test('core NCD fields (Diabetes + Blood Pressure sections) are visible '
        'without needing the unreachable ncdServiceProvided gate', () async {
      final config = await FormConfig.load(rootBundle);
      const emptyData = CanonicalVisitData();

      for (final id in [
        'isBeforeDiabetesDiagnosis',
        'glucoseType',
        'isBeforeHtnDiagnosis',
        'isRegularSmoker',
      ]) {
        final field = config.fields[id]!;
        expect(
          FieldVisibilityRules.isFieldVisible(
            field: field,
            data: emptyData,
            rulesByTargetId: config.visibilityRulesByTargetId,
          ),
          isTrue,
          reason: '$id should be visible in a standalone NCD visit',
        );
      }

      // medicationFrequencyBg/Bp don't need a base-visibility change — they
      // have their own real, working conditional logic once their immediate
      // driver (now fixed above) becomes answerable.
      final medicationFrequencyBg = config.fields['medicationFrequencyBg']!;
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: medicationFrequencyBg,
          data: emptyData,
          rulesByTargetId: config.visibilityRulesByTargetId,
        ),
        isFalse,
        reason: 'stays hidden until isBeforeDiabetesDiagnosis is answered Yes',
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: medicationFrequencyBg,
          data: const CanonicalVisitData({'isBeforeDiabetesDiagnosis': 'Yes'}),
          rulesByTargetId: config.visibilityRulesByTargetId,
        ),
        isTrue,
        reason: 'reveals once isBeforeDiabetesDiagnosis is answered Yes',
      );
    });

    // Regression test: a broader sweep (prompted by manual testing finding
    // the same bug in pncMother's "Counseling & Education" section after the
    // NCD fix above) found 12 more fields with the identical problem — base
    // visibility "gone" with either no incoming condition at all, or a
    // condition whose driver field is absent from the field's own formType.
    test('pncMother Counseling & Education and pncChild core fields are visible', () async {
      final config = await FormConfig.load(rootBundle);
      const emptyData = CanonicalVisitData();

      for (final id in [
        // pncMother "counselling" section (COUNSELING & EDUCATION) — was
        // rendering completely empty; these are static guidance text /
        // an optional referral dropdown, never meant to be conditional.
        'counsellingMotherCare',
        'motherCare',
        'newbornCare',
        'referralFacility',
        // pncChild's own core assessment questions — zero incoming rules.
        'hrsBreastFed',
        'monthAdditionalFeedGiven',
        'childBreastFeeding',
        'additionalFood24Hrs',
        'receivedVaccine',
        'dewormingMedicine',
        // cataract's computed CVD-risk display — an InformationLabel with
        // no incoming rule, same unreachable-by-default problem.
        'cvdRisk',
        // enrollment's own "Is the patient pregnant?" question.
        'isPregnant',
      ]) {
        final field = config.fields[id];
        expect(field, isNotNull, reason: '$id should exist in field_library.json');
        expect(
          FieldVisibilityRules.isFieldVisible(
            field: field!,
            data: emptyData,
            rulesByTargetId: config.visibilityRulesByTargetId,
          ),
          isTrue,
          reason: '$id should be visible with no prior answers',
        );
      }
    });

    // Belt-and-suspenders: programmatically sweep every field referenced by
    // every actively-rendered formType's own sections and assert none of
    // them are PERMANENTLY unreachable (visibility "gone" with either no
    // incoming rule, or every incoming rule's driver absent from that same
    // formType's own field set). This is exactly the bug class found twice
    // above — this test exists so a future field/condition edit can't
    // silently reintroduce it without a red test.
    test('no field in an actively-rendered formType is permanently unreachable', () async {
      final config = await FormConfig.load(rootBundle);

      // formTypes actually reachable via the visit flow (Programme enum
      // wireTags + the fixed vitals/enrollment forms) — excludes formTypes
      // like pwProfile/household_registration that aren't wired into
      // unified_form_screen.dart at all yet, so their data is inert either way.
      const activeFormTypes = {
        'anc', 'ncd', 'pncMother', 'pncChild', 'pncNeonatal',
        'pregnancyOutcome', 'cataract', 'eye_care', 'family_planning',
        'enrollment',
      };

      final formTypeFields = <String, Set<String>>{};
      for (final entry in config.forms.entries) {
        if (!activeFormTypes.contains(entry.key)) continue;
        final ids = formTypeFields.putIfAbsent(entry.key, () => {});
        for (final section in entry.value) {
          for (final ref in section.fieldRefs) {
            ids.add(ref.id);
          }
        }
      }

      final failures = <String>[];
      for (final formType in activeFormTypes) {
        final ownFields = formTypeFields[formType];
        if (ownFields == null) continue;
        for (final section in config.forms[formType] ?? const []) {
          for (final ref in section.fieldRefs) {
            final field = config.fields[ref.id];
            if (field == null) continue;
            if (field.visibility != 'gone') continue;
            // The obstetric-history composite chain is handled by its own
            // dedicated branch in isFieldVisible, not by incoming rules.
            if (field.compositeGroup == 'obstetricHistory') continue;

            final rules = config.visibilityRulesByTargetId[field.id] ?? const [];
            final reachable = rules.isNotEmpty &&
                rules.any((r) => ownFields.contains(r.driverId));
            if (!reachable) {
              failures.add(
                '$formType/${section.sectionId}/${field.id} '
                '(drivers: ${rules.map((r) => r.driverId).toList()})',
              );
            }
          }
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'Permanently-unreachable fields found:\n${failures.join('\n')}',
      );
    });
  });
  group('FormConfig.buildVisibilityRules', () {
    test('inverts a driver field\'s condition array by targetId', () {
      final fields = {
        'pncNeonateSigns': _fieldDef('pncNeonateSigns', {
          'label': 'Signs',
          'widgetHint': 'SingleSelectionView',
          'condition': [
            {'eq': 'Other', 'targetId': 'otherPncNeonateSigns', 'visibility': 'visible'},
          ],
        }),
        'otherPncNeonateSigns': _fieldDef('otherPncNeonateSigns', {
          'label': 'Other Signs',
          'widgetHint': 'EditText',
          'visibility': 'gone',
        }),
      };

      final rules = FormConfig.buildVisibilityRules(fields);

      expect(rules['otherPncNeonateSigns'], hasLength(1));
      final rule = rules['otherPncNeonateSigns']!.single;
      expect(rule.driverId, 'pncNeonateSigns');
      expect(rule.eq, 'Other');
      expect(rule.visibility, 'visible');
      expect(rules['pncNeonateSigns'], isNull);
    });

    test('a field with no condition array contributes no rules', () {
      final fields = {
        'weight': _fieldDef('weight', {'label': 'Weight', 'widgetHint': 'EditText'}),
      };
      expect(FormConfig.buildVisibilityRules(fields), isEmpty);
    });
  });

  group('FieldVisibilityRules.isFieldVisible — generic condition rules', () {
    final otherSigns = _fieldDef('otherPncNeonateSigns', {
      'label': 'Other Signs',
      'widgetHint': 'EditText',
      'visibility': 'gone',
    });
    final rulesByTargetId = {
      'otherPncNeonateSigns': const [
        FieldVisibilityRule(driverId: 'pncNeonateSigns', eq: 'Other', visibility: 'visible'),
      ],
    };

    test('hidden when the driver field has not been answered', () {
      final visible = FieldVisibilityRules.isFieldVisible(
        field: otherSigns,
        data: const CanonicalVisitData(),
        rulesByTargetId: rulesByTargetId,
      );
      expect(visible, isFalse);
    });

    test('hidden when the driver field does not match the trigger value', () {
      final visible = FieldVisibilityRules.isFieldVisible(
        field: otherSigns,
        data: const CanonicalVisitData({'pncNeonateSigns': 'Fever'}),
        rulesByTargetId: rulesByTargetId,
      );
      expect(visible, isFalse);
    });

    test('visible once the driver field matches the trigger value', () {
      final visible = FieldVisibilityRules.isFieldVisible(
        field: otherSigns,
        data: const CanonicalVisitData({'pncNeonateSigns': 'Other'}),
        rulesByTargetId: rulesByTargetId,
      );
      expect(visible, isTrue);
    });

    test('a hidden-but-mandatory field must not block submission', () {
      final mandatoryHidden = _fieldDef('otherPncNeonateSigns', {
        'label': 'Other Signs',
        'widgetHint': 'EditText',
        'visibility': 'gone',
        'isMandatory': true,
      });
      final visible = FieldVisibilityRules.isFieldVisible(
        field: mandatoryHidden,
        data: const CanonicalVisitData(),
        rulesByTargetId: rulesByTargetId,
      );
      // The caller (unified_form_screen.dart _computeValidationErrors) skips
      // mandatory-checking entirely when isFieldVisible is false — this just
      // confirms the field is correctly reported as not visible.
      expect(visible, isFalse);
    });
  });

  group('FieldVisibilityRules.isFieldVisible — obstetric-history chain', () {
    final gravida = _fieldDef('gravida', {
      'label': 'Gravida',
      'widgetHint': 'EditText',
      'visibility': 'gone',
      'compositeGroup': 'obstetricHistory',
      'compositeRole': 'trigger',
    });
    final parity = _fieldDef('parity', {
      'label': 'Parity',
      'widgetHint': 'EditText',
      'visibility': 'gone',
      'compositeGroup': 'obstetricHistory',
      'compositeRole': 'member',
    });
    final livingChildren = _fieldDef('livingChildren', {
      'label': 'Living Children',
      'widgetHint': 'EditText',
      'visibility': 'gone',
      'compositeGroup': 'obstetricHistory',
      'compositeRole': 'member',
    });
    final ageOfLastChild = _fieldDef('ageOfLastChild', {
      'label': 'Age of last child',
      'widgetHint': 'AgeYMD',
      'visibility': 'gone',
      'compositeGroup': 'obstetricHistory',
      'compositeRole': 'member',
    });

    test('gravida (the trigger) is always visible despite its own "gone" base visibility', () {
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: gravida,
          data: const CanonicalVisitData(),
          rulesByTargetId: const {},
        ),
        isTrue,
      );
    });

    test('parity is hidden for a first pregnancy (gravida == 1)', () {
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: parity,
          data: const CanonicalVisitData({'gravida': 1}),
          rulesByTargetId: const {},
        ),
        isFalse,
      );
    });

    test('parity becomes visible once gravida >= 2', () {
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: parity,
          data: const CanonicalVisitData({'gravida': 2}),
          rulesByTargetId: const {},
        ),
        isTrue,
      );
    });

    test('livingChildren stays hidden until parity >= 1', () {
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: livingChildren,
          data: const CanonicalVisitData({'gravida': 3, 'parity': 0}),
          rulesByTargetId: const {},
        ),
        isFalse,
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: livingChildren,
          data: const CanonicalVisitData({'gravida': 3, 'parity': 1}),
          rulesByTargetId: const {},
        ),
        isTrue,
      );
    });

    test('ageOfLastChild stays hidden until livingChildren >= 1', () {
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: ageOfLastChild,
          data: const CanonicalVisitData({'livingChildren': 0}),
          rulesByTargetId: const {},
        ),
        isFalse,
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: ageOfLastChild,
          data: const CanonicalVisitData({'livingChildren': 1}),
          rulesByTargetId: const {},
        ),
        isTrue,
      );
    });
  });

  group('FieldVisibilityRules.isFieldVisible — base visibility fallback', () {
    test('a field with no rule and no composite group falls back to its own visibility', () {
      final alwaysVisible = _fieldDef('weight', {
        'label': 'Weight',
        'widgetHint': 'EditText',
        'visibility': 'visible',
      });
      final alwaysHidden = _fieldDef('someLegacyField', {
        'label': 'Legacy',
        'widgetHint': 'EditText',
        'visibility': 'gone',
      });

      expect(
        FieldVisibilityRules.isFieldVisible(
          field: alwaysVisible,
          data: const CanonicalVisitData(),
          rulesByTargetId: const {},
        ),
        isTrue,
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: alwaysHidden,
          data: const CanonicalVisitData(),
          rulesByTargetId: const {},
        ),
        isFalse,
      );
    });

    test('a field with no visibility key in the JSON defaults to visible', () {
      final noVisibilityKey = _fieldDef('systolic', {
        'label': 'Systolic',
        'widgetHint': 'EditText',
      });
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: noVisibilityKey,
          data: const CanonicalVisitData(),
          rulesByTargetId: const {},
        ),
        isTrue,
      );
    });
  });
}
