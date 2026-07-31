/// Regression coverage for the Eye Care disclosure chain.
///
/// `field_library.json` carries Spice's `condition` blocks verbatim but its
/// `optionsList` ids had been rewritten into display/camelCase forms
/// (`+1.00` vs `1.0`, `Yes` vs `yes`, `biFocal` vs `bf`, `Metal` vs `metal`).
/// [FieldVisibilityRule.matches] is exact string equality, so every hop after
/// Eye Test Outcome was unreachable — the SK saw one field and a dead end.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';
import 'package:uhis_next/features/visit/forms/unified_section_rules.dart';

import '../../../helpers/fake_form_deps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool visible(FormConfig config, String fieldId, Map<String, dynamic> values) =>
      FieldVisibilityRules.isFieldVisible(
        field: config.fields[fieldId]!,
        data: CanonicalVisitData(values),
        rulesByTargetId: config.visibilityRulesByTargetId,
        formType: 'eye_care',
      );

  group('Eye Care disclosure chain (Spice eye_care.json parity)', () {
    test('each hop opens the next field', () async {
      final config = await FormConfig.load(rootBundle);

      // Only Eye Test Outcome starts visible.
      expect(visible(config, 'eyeTestOutcome', const {}), isTrue);
      for (final id in const [
        'glassPower',
        'haveTheGlassesBeenSold',
        'typeOfGlass',
        'typeOfFrame',
        'firstTimeUser',
        'referPlace',
      ]) {
        expect(visible(config, id, const {}), isFalse, reason: '$id at start');
      }

      final values = <String, dynamic>{'eyeTestOutcome': 'presbyopia'};
      expect(visible(config, 'glassPower', values), isTrue);
      expect(visible(config, 'referPlace', values), isFalse);

      values['glassPower'] = '1.5';
      expect(visible(config, 'haveTheGlassesBeenSold', values), isTrue);

      values['haveTheGlassesBeenSold'] = 'yes';
      expect(visible(config, 'typeOfGlass', values), isTrue);

      values['typeOfGlass'] = 'bf';
      expect(visible(config, 'typeOfFrame', values), isTrue);

      values['typeOfFrame'] = 'metal';
      expect(visible(config, 'firstTimeUser', values), isTrue);
    });

    test('cataracts / myopia / otherProblem branch to Refer Place', () async {
      final config = await FormConfig.load(rootBundle);

      for (final outcome in const ['cataracts', 'myopia', 'otherProblem']) {
        expect(
          visible(config, 'referPlace', {'eyeTestOutcome': outcome}),
          isTrue,
          reason: outcome,
        );
        expect(
          visible(config, 'glassPower', {'eyeTestOutcome': outcome}),
          isFalse,
          reason: outcome,
        );
      }

      // No Problem ends the form.
      expect(
        visible(config, 'referPlace', const {'eyeTestOutcome': 'noProblem'}),
        isFalse,
      );
      expect(
        visible(config, 'glassPower', const {'eyeTestOutcome': 'noProblem'}),
        isFalse,
      );
    });

    test('eye care Refer Place offers Spice\'s eye_care.json options', () async {
      final config = await FormConfig.load(rootBundle);

      expect(
        config.fields['referPlace']!.options.map((o) => o.id).toList(),
        ['visionCenter', 'pspCamp', 'medicalCollegeHospital',
          'govtPrivateHospital', 'others'],
      );
    });

    test('cataract overrides Refer Place with its own facility list', () async {
      final config = await FormConfig.load(rootBundle);

      final ref = config.forms['cataract']!
          .expand((s) => s.fieldRefs)
          .firstWhere((r) => r.id == 'referPlace');

      expect(
        ref.options?.map((o) => o.id).toList(),
        ['upazilaHealthComplex', 'districtHospital', 'medicalCollegeHospital',
          'govtPrivateSpecializedHospital', 'others'],
      );
      // The override must not mutate the shared library entry.
      expect(config.fields['referPlace']!.options.first.id, 'visionCenter');
      expect(
        config.fields['referPlace']!.withOptions(ref.options!).options.first.id,
        'upazilaHealthComplex',
      );
    });
  });

  group('condition trigger values are producible by their driver', () {
    // The pre-existing reachability test only checks that a target's driver
    // sits in the same form — it never checks the driver can actually produce
    // the trigger value, which is how the whole Eye Care chain shipped broken.
    test('every eq / eqList value matches one of the driver\'s option ids',
        () async {
      final config = await FormConfig.load(rootBundle);

      // Conditions pointing at a field no layout renders are inert leftovers
      // from non-BD Spice variants (e.g. isRegularSmoker → smokerTypes).
      final renderedFieldIds = config.forms.values
          .expand((sections) => sections)
          .expand((section) => section.fieldRefs)
          .map((ref) => ref.id)
          .toSet();

      final failures = <String>[];
      for (final driver in config.fields.values) {
        if (driver.options.isEmpty) continue;
        final optionIds = driver.options.map((o) => o.id).toSet();
        for (final condition in driver.conditions) {
          if (condition.greaterThanOrEqual != null) continue;
          if (!renderedFieldIds.contains(condition.targetId)) continue;
          final triggers = condition.eq != null
              ? [condition.eq!]
              : condition.eqList;
          if (triggers.isEmpty) continue;
          if (triggers.any(optionIds.contains)) continue;
          failures.add(
            '${driver.id} → ${condition.targetId}: triggers $triggers '
            'are unreachable from options ${optionIds.toList()}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'Conditions no option can ever satisfy:\n'
            '${failures.join('\n')}',
      );
    });
  });

  group('UnifiedFormNotifier clears fields a condition just hid', () {
    late FakeAssessmentDraftDao draftDao;
    late UnifiedFormNotifier notifier;

    setUp(() async {
      draftDao = FakeAssessmentDraftDao();
      notifier = buildTestNotifier(
        draftDao: draftDao,
        activeFormTypes: const ['eye_care'],
      );
      notifier.formConfig = await FormConfig.load(rootBundle);
    });

    test('de-selecting a branch cascades through the whole chain', () async {
      notifier.updateField('eyeTestOutcome', 'presbyopia');
      notifier.updateField('glassPower', '1.5');
      notifier.updateField('haveTheGlassesBeenSold', 'yes');
      notifier.updateField('typeOfGlass', 'bf');
      notifier.updateField('typeOfFrame', 'metal');
      notifier.updateField('firstTimeUser', 'yes');

      expect(notifier.data.getValue('typeOfFrame'), 'metal');

      // Android resetChildViews: hiding the branch drops everything under it.
      notifier.updateField('eyeTestOutcome', 'noProblem');

      for (final id in const [
        'glassPower',
        'haveTheGlassesBeenSold',
        'typeOfGlass',
        'typeOfFrame',
        'firstTimeUser',
      ]) {
        expect(notifier.data.getValue(id), isNull, reason: id);
      }
      expect(notifier.data.getValue('eyeTestOutcome'), 'noProblem');
    });

    test('switching a mid-chain answer clears only what it hides', () async {
      notifier.updateField('eyeTestOutcome', 'presbyopia');
      notifier.updateField('glassPower', '2.0');
      notifier.updateField('haveTheGlassesBeenSold', 'yes');
      notifier.updateField('typeOfGlass', 'sv');

      notifier.updateField('haveTheGlassesBeenSold', 'no');

      expect(notifier.data.getValue('typeOfGlass'), isNull);
      expect(notifier.data.getValue('glassPower'), '2.0');
      expect(notifier.data.getValue('eyeTestOutcome'), 'presbyopia');
    });

    test('fields with no condition rule are never cleared', () async {
      notifier.updateField('weight', 62.0);
      notifier.updateField('eyeTestOutcome', 'noProblem');

      expect(notifier.data.getValue('weight'), 62.0);
    });
  });
}
