/// Cataract disclosure-chain coverage (Spice cataract.json parity).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_section_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool visible(FormConfig config, String fieldId, Map<String, dynamic> values) =>
      FieldVisibilityRules.isFieldVisible(
        field: config.fields[fieldId]!,
        data: CanonicalVisitData(values),
        rulesByTargetId: config.visibilityRulesByTargetId,
        formType: 'cataract',
      );

  group('Cataract surgical disclosure chain', () {
    test('cataracts → history → referred yes → operation → pseudophakia → ncd',
        () async {
      final config = await FormConfig.load(rootBundle);

      expect(visible(config, 'eyeDisease', const {}), isTrue);
      expect(visible(config, 'historyOfOtherDiseases', const {}), isFalse);

      final values = <String, dynamic>{
        'eyeDisease': ['cataracts'],
      };
      expect(visible(config, 'historyOfOtherDiseases', values), isTrue);

      values['historyOfOtherDiseases'] = ['diabetes'];
      expect(visible(config, 'patientReferredForOperation', values), isTrue);

      values['patientReferredForOperation'] = 'yes';
      expect(visible(config, 'operationName', values), isTrue);
      expect(visible(config, 'reason', values), isFalse);

      values['operationName'] = ['dct'];
      expect(visible(config, 'pseudophakiaPostCataractSurgery', values), isTrue);

      values['pseudophakiaPostCataractSurgery'] = 'no';
      expect(visible(config, 'ncdServiceProvided', values), isTrue);
    });

    test('ncdServiceProvided=no opens whoReferred; vitals stay hidden', () async {
      final config = await FormConfig.load(rootBundle);
      final values = <String, dynamic>{
        'eyeDisease': ['cataracts'],
        'historyOfOtherDiseases': ['noProblem'],
        'patientReferredForOperation': 'no',
        'reason': ['noProblem'],
        'pseudophakiaPostCataractSurgery': 'yes',
        'ncdServiceProvided': 'no',
      };

      expect(visible(config, 'whoReferredThisPerson', values), isTrue);
      expect(visible(config, 'bpLogDetails', values), isFalse);
      expect(visible(config, 'height', values), isFalse);
      expect(visible(config, 'isBeforeHtnDiagnosis', values), isFalse);
      expect(visible(config, 'isBeforeDiabetesDiagnosis', values), isFalse);
      expect(visible(config, 'glucoseType', values), isFalse);
    });

    test('ncdServiceProvided=yes opens NCD vitals; medication needs prior dx',
        () async {
      final config = await FormConfig.load(rootBundle);
      final values = <String, dynamic>{
        'eyeDisease': ['cataracts'],
        'historyOfOtherDiseases': ['noProblem'],
        'patientReferredForOperation': 'no',
        'reason': ['noProblem'],
        'pseudophakiaPostCataractSurgery': 'no',
        'ncdServiceProvided': 'yes',
      };

      expect(visible(config, 'isBeforeHtnDiagnosis', values), isTrue);
      expect(visible(config, 'bpLogDetails', values), isTrue);
      expect(visible(config, 'height', values), isTrue);
      expect(visible(config, 'isRegularSmoker', values), isTrue);
      expect(visible(config, 'isBeforeDiabetesDiagnosis', values), isTrue);
      expect(visible(config, 'glucoseType', values), isTrue);
      expect(visible(config, 'whoReferredThisPerson', values), isFalse);

      expect(visible(config, 'medicationFrequencyBp', values), isFalse);
      values['isBeforeHtnDiagnosis'] = 'yes';
      expect(visible(config, 'medicationFrequencyBp', values), isTrue);

      expect(visible(config, 'medicationFrequencyBg', values), isFalse);
      values['isBeforeDiabetesDiagnosis'] = 'yes';
      expect(visible(config, 'medicationFrequencyBg', values), isTrue);
    });

    test('vitals stay hidden before ncdServiceProvided is answered', () async {
      final config = await FormConfig.load(rootBundle);
      expect(visible(config, 'height', const {}), isFalse);
      expect(visible(config, 'bpLogDetails', const {}), isFalse);
      expect(visible(config, 'isBeforeDiabetesDiagnosis', const {}), isFalse);
    });
  });

  group('Cataract glasses / referPlace branches', () {
    test('presbyopia opens the glasses chain ending at ncdServiceProvided',
        () async {
      final config = await FormConfig.load(rootBundle);
      final values = <String, dynamic>{
        'eyeDisease': ['presbyopia'],
      };
      expect(visible(config, 'glassPower', values), isTrue);

      values['glassPower'] = '2.0';
      expect(visible(config, 'haveTheGlassesBeenSold', values), isTrue);

      values['haveTheGlassesBeenSold'] = 'yes';
      expect(visible(config, 'typeOfGlass', values), isTrue);

      values['typeOfGlass'] = 'sv';
      expect(visible(config, 'typeOfFrame', values), isTrue);

      values['typeOfFrame'] = 'plastic';
      expect(visible(config, 'firstTimeUser', values), isTrue);

      values['firstTimeUser'] = 'no';
      expect(visible(config, 'ncdServiceProvided', values), isTrue);
    });

    test('myopia / otherProblem open cataract referPlace', () async {
      final config = await FormConfig.load(rootBundle);
      for (final disease in const ['myopia', 'otherProblem']) {
        expect(
          visible(config, 'referPlace', {
            'eyeDisease': [disease],
          }),
          isTrue,
          reason: disease,
        );
      }

      final values = <String, dynamic>{
        'eyeDisease': ['myopia'],
        'referPlace': 'districtHospital',
      };
      expect(visible(config, 'ncdServiceProvided', values), isTrue);
    });
  });

  group('Standalone NCD still shows core vitals without ncdServiceProvided', () {
    test('isBeforeHtnDiagnosis visible on ncd formType', () async {
      final config = await FormConfig.load(rootBundle);
      expect(
        FieldVisibilityRules.isFieldVisible(
          field: config.fields['isBeforeHtnDiagnosis']!,
          data: const CanonicalVisitData(),
          rulesByTargetId: config.visibilityRulesByTargetId,
          formType: 'ncd',
        ),
        isTrue,
      );
    });
  });
}
