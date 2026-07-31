import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/risk/cataract_status.dart';
import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/unified_payload_mapper.dart';

void main() {
  group('UnifiedPayloadMapper.decompose — cataract', () {
    test('groups answers under card families with eyeTestOutcomes', () {
      final data = CanonicalVisitData({
        'eyeDisease': ['cataracts', 'glaucoma'],
        'historyOfOtherDiseases': ['diabetes'],
        'patientReferredForOperation': 'yes',
        'operationName': ['cataracts'],
        'pseudophakiaPostCataractSurgery': 'no',
        'ncdServiceProvided': 'no',
        'whoReferredThisPerson': 'SK',
        'systolic': 169,
        'height': 165,
        'glucose': 8.5,
      });

      final payloads = UnifiedPayloadMapper.decompose(data, {'cataract'});

      expect(payloads, hasLength(1));
      expect(payloads.single.assessmentType, 'CATARACT');
      expect(payloads.single.details, {
        'generalInformation': <String, dynamic>{},
        'cataract': {
          'eyeTestOutcomes': ['cataracts', 'glaucoma'],
          'historyOfOtherDiseases': ['diabetes'],
          'patientReferredForOperation': 'yes',
          'operationName': ['cataracts'],
          'pseudophakiaPostCataractSurgery': 'no',
          'ncdServiceProvided': 'no',
        },
        'referralInformation': {
          'whoReferredThisPerson': 'SK',
        },
      });
      expect(payloads.single.details.containsKey('ncd'), isFalse);
    });

    test('ncdServiceProvided=yes nests vitals under cataract.ncd', () {
      final details = UnifiedPayloadMapper.decompose(
        CanonicalVisitData({
          'eyeDisease': ['cataracts'],
          'historyOfOtherDiseases': ['noProblem'],
          'patientReferredForOperation': 'no',
          'reason': ['financialIssue'],
          'pseudophakiaPostCataractSurgery': 'no',
          'ncdServiceProvided': 'yes',
          'isBeforeHtnDiagnosis': 'yes',
          'medicationFrequencyBp': 'yes',
          'bpLogDetails': [
            {'systolic': 150, 'diastolic': 95},
          ],
          'height': 165,
          'weight': 70,
          'bmi': 25.7,
          'isRegularSmoker': false,
          'isBeforeDiabetesDiagnosis': 'no',
          'glucoseType': 'fbs',
          'glucose': 8.5,
          'referralFacilityType': 'Upazila Health Complex',
        }),
        {'cataract'},
      ).single.details;

      expect(details['cataract']['ncdServiceProvided'], 'yes');
      expect(details.containsKey('referralInformation'), isFalse);

      final ncd = details['ncd'] as Map<String, dynamic>;
      expect(ncd['referralFacilityType'], 'Upazila Health Complex');
      final bp = ncd['bpLog'] as Map<String, dynamic>;
      expect(bp['isBeforeHtnDiagnosis'], isTrue);
      expect(bp['height'], 165.0);
      expect(bp['weight'], 70.0);
      expect(bp['bmi'], 25.7);
      expect(bp['avgSystolic'], 150);
      expect(bp['avgDiastolic'], 95);
      expect(bp['isRegularSmoker'], isFalse);
      final glucose = ncd['glucoseLog'] as Map<String, dynamic>;
      expect(glucose['isBeforeDiabetesDiagnosis'], isFalse);
      expect(glucose['glucose'], 8.5);
      expect(glucose['glucoseType'], 'fbs');
    });

    test('presbyopia path carries glasses fields', () {
      final details = UnifiedPayloadMapper.decompose(
        CanonicalVisitData({
          'eyeDisease': ['presbyopia'],
          'glassPower': '2.0',
          'haveTheGlassesBeenSold': 'yes',
          'typeOfGlass': 'sv',
          'typeOfFrame': 'metal',
          'firstTimeUser': 'yes',
          'ncdServiceProvided': 'no',
          'whoReferredThisPerson': 'volunteer',
        }),
        {'cataract'},
      ).single.details;

      expect(details['cataract'], {
        'eyeTestOutcomes': ['presbyopia'],
        'glassPower': '2.0',
        'haveTheGlassesBeenSold': 'yes',
        'typeOfGlass': 'sv',
        'typeOfFrame': 'metal',
        'firstTimeUser': 'yes',
        'ncdServiceProvided': 'no',
      });
      expect(details.containsKey('visualAcuityRight'), isFalse);
      expect(details.containsKey('ncd'), isFalse);
    });
  });

  group('LocalAssessmentEntity.toApiRequest — cataract', () {
    test('wraps card families under the cataract menu key', () {
      final details = UnifiedPayloadMapper.decompose(
        CanonicalVisitData({
          'eyeDisease': ['cataracts'],
          'historyOfOtherDiseases': ['noProblem'],
          'patientReferredForOperation': 'no',
          'reason': ['financialIssue'],
          'pseudophakiaPostCataractSurgery': 'no',
          'ncdServiceProvided': 'no',
          'whoReferredThisPerson': 'SK',
        }),
        {'cataract'},
      ).single.details;

      final entity = LocalAssessmentEntity(
        id: 'a1',
        householdMemberLocalId: 7,
        assessmentType: 'CATARACT',
        assessmentDetails: jsonEncode(details),
        customStatus: jsonEncode(CataractStatus.status(
          details['cataract'] as Map<String, dynamic>,
        )),
      );

      final request = entity.toApiRequest(provenance: null);

      expect(request['assessmentType'], 'CATARACT');
      expect(request['assessmentDetails'], {
        'cataract': {
          'generalInformation': <String, dynamic>{},
          'cataract': {
            'eyeTestOutcomes': ['cataracts'],
            'historyOfOtherDiseases': ['noProblem'],
            'patientReferredForOperation': 'no',
            'reason': ['financialIssue'],
            'pseudophakiaPostCataractSurgery': 'no',
            'ncdServiceProvided': 'no',
          },
          'referralInformation': {
            'whoReferredThisPerson': 'SK',
          },
        },
      });
      expect(request['encounter']['customStatus'], ['CATARACTS']);
    });
  });
}
