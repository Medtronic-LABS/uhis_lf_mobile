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

      for (final entry in [
        // pncChild keeps isSummary fields on fill (Android CHILDHOOD_VISIT).
        ('hrsBreastFed', 'pncChild'),
        ('monthAdditionalFeedGiven', 'pncChild'),
        ('childBreastFeeding', 'pncChild'),
        ('additionalFood24Hrs', 'pncChild'),
        ('receivedVaccine', 'pncChild'),
        ('dewormingMedicine', 'pncChild'),
        ('cvdRisk', 'cataract'),
        ('isPregnant', 'enrollment'),
        ('referralFacility', 'pncMother'),
      ]) {
        final id = entry.$1;
        final formType = entry.$2;
        final field = config.fields[id];
        expect(field, isNotNull, reason: '$id should exist in field_library.json');
        expect(
          FieldVisibilityRules.isFieldVisible(
            field: field!,
            data: emptyData,
            rulesByTargetId: config.visibilityRulesByTargetId,
            formType: formType,
          ),
          isTrue,
          reason: '$id should be visible with no prior answers',
        );
      }

      // pncMother counselling text is Android isSummary → fill-form-hidden.
      for (final id in ['counsellingMotherCare', 'motherCare', 'newbornCare']) {
        final field = config.fields[id]!;
        expect(
          FieldVisibilityRules.isFieldVisible(
            field: field,
            data: emptyData,
            rulesByTargetId: config.visibilityRulesByTargetId,
            formType: 'pncMother',
          ),
          isFalse,
          reason: '$id is Android isSummary — pncMother fill form hides it',
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
            // Android-gated ANC field — revealed when illness ≠ None.
            if (field.id == 'pregnantWomanOnTreatment') continue;
            // anc / pncMother / pregnancyOutcome isSummary cards are
            // fill-form-hidden by design (Android RMNCH filter).
            if (field.isSummary &&
                const {'anc', 'pncMother', 'pregnancyOutcome'}
                    .contains(formType)) {
              continue;
            }

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

    // Regression test: 23 of the 80 condition entries in field_library.json
    // use `eqList` (multiple acceptable trigger values) instead of a single
    // `eq` — FieldCondition.fromJson previously only read `eq`, so every
    // eqList-only condition parsed as eq: '' and could never match a real
    // driver value. This silently broke 14 fields across pregnancyOutcome,
    // cataract, eye_care, and enrollment (their driver field WAS present and
    // answered, but the match itself could never succeed).
    test('eqList conditions (multiple acceptable trigger values) are honored', () async {
      final config = await FormConfig.load(rootBundle);

      final causeOfDeath = config.fields['causeOfDeath']!;
      final identityValue = config.fields['identityValue']!;

      // timeOfDeath's eqList: ['beforeDelivery', 'within42DaysAfterDelivery', 'duringChildbirth']
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: causeOfDeath,
          data: const CanonicalVisitData({'timeOfDeath': 'duringChildbirth'}),
          rulesByTargetId: config.visibilityRulesByTargetId,
        ),
        isTrue,
        reason: 'duringChildbirth is a member of the eqList',
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: causeOfDeath,
          data: const CanonicalVisitData({'timeOfDeath': 'somethingElse'}),
          rulesByTargetId: config.visibilityRulesByTargetId,
        ),
        isFalse,
        reason: 'a value outside the eqList must not match',
      );

      // identityType's eqList: ['nid', 'brn']
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: identityValue,
          data: const CanonicalVisitData({'identityType': 'brn'}),
          rulesByTargetId: config.visibilityRulesByTargetId,
        ),
        isTrue,
      );
    });

    test('FieldCondition/FieldVisibilityRule.matches — unit coverage', () {
      const eqCondition = FieldVisibilityRule(
        driverId: 'x',
        eq: 'Yes',
        visibility: 'visible',
      );
      expect(eqCondition.matches('Yes'), isTrue);
      expect(eqCondition.matches('No'), isFalse);
      expect(eqCondition.matches(null), isFalse);

      const eqListCondition = FieldVisibilityRule(
        driverId: 'x',
        eqList: ['a', 'b', 'c'],
        visibility: 'visible',
      );
      expect(eqListCondition.matches('b'), isTrue);
      expect(eqListCondition.matches('z'), isFalse);
      expect(eqListCondition.matches(null), isFalse);

      const gteCondition = FieldVisibilityRule(
        driverId: 'x',
        greaterThanOrEqual: 2,
        visibility: 'visible',
      );
      expect(gteCondition.matches('2'), isTrue);
      expect(gteCondition.matches('5'), isTrue);
      expect(gteCondition.matches('1'), isFalse);
      expect(gteCondition.matches('not a number'), isFalse);
      expect(gteCondition.matches(null), isFalse);
    });

    // Regression test: field_library.json also has a 3rd condition variant,
    // `greaterThanOrEqual` (numeric comparison), used by
    // gestationMonthAtAbortion to reveal typeOfAbortion in the pregnancyOutcome
    // form's own "abortion" section. FieldCondition.fromJson previously
    // dropped this key entirely (parsed as eq: null, eqList: []), so the
    // condition could never match, and typeOfAbortion had no other reachable
    // reveal path when filling out the abortion section on its own.
    test('greaterThanOrEqual conditions (numeric threshold) are honored', () async {
      final config = await FormConfig.load(rootBundle);
      final typeOfAbortion = config.fields['typeOfAbortion']!;

      expect(
        FieldVisibilityRules.isFieldVisible(
          field: typeOfAbortion,
          data: const CanonicalVisitData({'gestationMonthAtAbortion': '3'}),
          rulesByTargetId: config.visibilityRulesByTargetId,
        ),
        isTrue,
        reason: 'gestationMonthAtAbortion >= 1 should reveal typeOfAbortion',
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: typeOfAbortion,
          data: const CanonicalVisitData({'gestationMonthAtAbortion': '0'}),
          rulesByTargetId: config.visibilityRulesByTargetId,
        ),
        isFalse,
        reason: 'below the threshold, typeOfAbortion should stay hidden',
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

  // Android AssessmentRMNCHFragment.updateANCConditionalFieldVisibility().
  group('ANC gestational-age / visit-number gates (Android parity)', () {
    bool visible(
      String id, {
      int? ga,
      int? visit,
      CanonicalVisitData data = const CanonicalVisitData(),
    }) {
      return FieldVisibilityRules.isFieldVisible(
        field: _fieldDef(id, {
          'label': id,
          'widgetHint': 'EditText',
          'visibility': 'visible',
        }),
        data: data,
        rulesByTargetId: const {},
        gestationalWeeks: ga,
        ancVisitNumber: visit,
        formType: 'anc',
      );
    }

    test('danger signs: only ≤12 band when GA unknown', () {
      expect(visible('dangerSignsExperienced12'), isTrue);
      expect(visible('dangerSignsExperienced13To27'), isFalse);
      expect(visible('dangerSignsExperienced28To40'), isFalse);
    });

    test('danger signs: trimester bands by GA', () {
      expect(visible('dangerSignsExperienced12', ga: 10), isTrue);
      expect(visible('dangerSignsExperienced13To27', ga: 10), isFalse);

      expect(visible('dangerSignsExperienced12', ga: 20), isFalse);
      expect(visible('dangerSignsExperienced13To27', ga: 20), isTrue);
      expect(visible('dangerSignsExperienced28To40', ga: 20), isFalse);

      expect(visible('dangerSignsExperienced13To27', ga: 30), isFalse);
      expect(visible('dangerSignsExperienced28To40', ga: 30), isTrue);
    });

    test('supplements: folic ≤12; IFA/calcium >12; all when GA null', () {
      expect(visible('folicAcidProvided'), isTrue);
      expect(visible('ifaProvided'), isTrue);
      expect(visible('calciumProvided'), isTrue);

      expect(visible('folicAcidProvided', ga: 8), isTrue);
      expect(visible('ifaProvided', ga: 8), isFalse);
      expect(visible('calciumProvided', ga: 8), isFalse);

      expect(visible('folicAcidProvided', ga: 16), isFalse);
      expect(visible('ifaProvided', ga: 16), isTrue);
      expect(visible('calciumProvided', ga: 16), isTrue);
    });

    test('edema ≥12, fundal ≥24, ultrasound/doctor ANC ≥28', () {
      expect(visible('edema', ga: 8), isFalse);
      expect(visible('edema', ga: 12), isTrue);
      expect(visible('fundalHeight', ga: 20), isFalse);
      expect(visible('fundalHeight', ga: 24), isTrue);
      expect(visible('ultrasound', ga: 27), isFalse);
      expect(visible('ultrasound', ga: 28), isTrue);
      expect(visible('ancFromMedicalDoctor', ga: 28), isTrue);
    });

    test('height / BMI visit-1 gates', () {
      expect(visible('height', visit: 1), isTrue);
      expect(visible('height', visit: 2), isFalse);
      expect(visible('bmi', visit: 1, ga: 8), isTrue);
      expect(visible('bmi', visit: 1, ga: 14), isFalse);
      expect(visible('bmi', visit: 2, ga: 8), isFalse);
    });

    test('previousPregnancyComplications: visit 1 and gravida > 1', () {
      const g2 = CanonicalVisitData({'gravida': 2});
      const g1 = CanonicalVisitData({'gravida': 1});
      expect(visible('previousPregnancyComplications', visit: 1, data: g2),
          isTrue);
      expect(visible('previousPregnancyComplications', visit: 1, data: g1),
          isFalse);
      expect(visible('previousPregnancyComplications', visit: 2, data: g2),
          isFalse);
    });

    test('urineProtein hidden (Android has urinaryAlbumin only)', () {
      expect(visible('urineProtein'), isFalse);
      expect(visible('urinaryAlbumin'), isTrue);
    });
  });

  group('isSummary fields (Android RMNCH summary screen)', () {
    test('hidden on ANC fill form', () {
      final summary = _fieldDef('gapsInAnc', {
        'label': 'Gaps in ANC',
        'isSummary': true,
        'visibility': 'visible',
      });
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: summary,
          data: const CanonicalVisitData(),
          rulesByTargetId: const {},
          formType: 'anc',
        ),
        isFalse,
      );
    });

    test('still visible on NCD fill form (summary flag ≠ hide)', () {
      final ncdSymptom = _fieldDef('ncdSymptoms', {
        'label': 'Select Symptoms',
        'isSummary': true,
        'visibility': 'gone',
      });
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: ncdSymptom,
          data: const CanonicalVisitData({'hasSymptoms': 'Yes'}),
          rulesByTargetId: {
            'ncdSymptoms': [
              const FieldVisibilityRule(
                driverId: 'hasSymptoms',
                eq: 'Yes',
                visibility: 'visible',
              ),
            ],
          },
          formType: 'ncd',
        ),
        isTrue,
      );
    });
  });

  group('NCD symptoms skip (Android BDNCD parity)', () {
    final ncdSymptoms = _fieldDef('ncdSymptoms', {
      'label': 'Select Symptoms',
      'isSummary': true,
      'visibility': 'gone',
    });
    final newWorsening = _fieldDef('newWorseningSymptoms', {
      'label': 'Any new or worsening symptoms',
      'isSummary': true,
      'visibility': 'gone',
    });
    final rules = {
      'ncdSymptoms': [
        const FieldVisibilityRule(
          driverId: 'hasSymptoms',
          eq: 'Yes',
          visibility: 'visible',
        ),
      ],
    };

    test('Yes reveals symptom picker; No keeps it gone', () {
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: ncdSymptoms,
          data: const CanonicalVisitData({'hasSymptoms': 'Yes'}),
          rulesByTargetId: rules,
          formType: 'ncd',
        ),
        isTrue,
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: ncdSymptoms,
          data: const CanonicalVisitData({'hasSymptoms': 'No'}),
          rulesByTargetId: rules,
          formType: 'ncd',
        ),
        isFalse,
      );
    });

    test('newWorsening only when that symptom option is selected', () {
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: newWorsening,
          data: CanonicalVisitData({
            'hasSymptoms': 'Yes',
            'ncdSymptoms': ['Headache'],
          }),
          rulesByTargetId: const {},
          formType: 'ncd',
        ),
        isFalse,
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: newWorsening,
          data: CanonicalVisitData({
            'hasSymptoms': 'Yes',
            'ncdSymptoms': [
              FieldVisibilityRules.ncdAnyNewOrWorseningSymptomOption,
            ],
          }),
          rulesByTargetId: const {},
          formType: 'ncd',
        ),
        isTrue,
      );
    });

    test('NCD height ignores ANC visit-number gate', () {
      final height = _fieldDef('height', {
        'label': 'Height',
        'visibility': 'visible',
      });
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: height,
          data: const CanonicalVisitData(),
          rulesByTargetId: const {},
          formType: 'ncd',
          ancVisitNumber: 3,
          gestationalWeeks: 28,
        ),
        isTrue,
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: height,
          data: const CanonicalVisitData(),
          rulesByTargetId: const {},
          formType: 'anc',
          ancVisitNumber: 3,
          gestationalWeeks: 28,
        ),
        isFalse,
      );
    });
  });

  group('pregnantWomanOnTreatment (Android illness-gated)', () {
    final onTreatment = _fieldDef('pregnantWomanOnTreatment', {
      'label': 'Pregnant woman on treatment for any existing illness',
      'visibility': 'gone',
      'optionsList': [
        {'id': 'none', 'name': 'Not taking any treatment'},
      ],
    });
    final illness = _fieldDef('pregnantWomanExistingIllness', {
      'label': 'Pregnant woman has any existing illness',
      'visibility': 'visible',
      'optionsList': [
        {'id': 'htn', 'name': 'HTN'},
        {'id': 'dm', 'name': 'DM'},
        {'id': 'none', 'name': 'None'},
      ],
    });

    test('hidden when no illness or None selected', () {
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: onTreatment,
          data: const CanonicalVisitData(),
          rulesByTargetId: const {},
          formType: 'anc',
        ),
        isFalse,
      );
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: onTreatment,
          data: const CanonicalVisitData({
            'pregnantWomanExistingIllness': ['none'],
          }),
          rulesByTargetId: const {},
          formType: 'anc',
        ),
        isFalse,
      );
    });

    test('visible when a real illness is selected', () {
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: onTreatment,
          data: const CanonicalVisitData({
            'pregnantWomanExistingIllness': ['htn', 'dm'],
          }),
          rulesByTargetId: const {},
          formType: 'anc',
        ),
        isTrue,
      );
    });

    test('options = selected illnesses + not taking treatment', () {
      final opts = FieldVisibilityRules.ancOnTreatmentOptions(
        illnessField: illness,
        onTreatmentField: onTreatment,
        data: const CanonicalVisitData({
          'pregnantWomanExistingIllness': ['htn'],
        }),
      );
      expect(opts.map((o) => o.id).toList(), ['htn', 'none']);
    });
  });
}
