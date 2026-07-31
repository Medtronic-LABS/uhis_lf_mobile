import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/risk/cataract_status.dart';
import 'package:uhis_next/core/risk/ncd_status.dart';

void main() {
  group('CataractStatus.status', () {
    test('surgical path: problems + REFERRED_FOR_OPERATION', () {
      expect(
        CataractStatus.status({
          'eyeTestOutcomes': ['cataracts', 'glaucoma'],
          'historyOfOtherDiseases': ['diabetes'],
          'patientReferredForOperation': 'yes',
          'operationName': ['cataracts'],
          'pseudophakiaPostCataractSurgery': 'no',
          'ncdServiceProvided': 'no',
        }),
        ['CATARACTS', 'GLAUCOMA', 'REFERRED_FOR_OPERATION'],
      );
    });

    test('presbyopia path: problems, sold, referred, then glass power last', () {
      expect(
        CataractStatus.status({
          'eyeTestOutcomes': ['presbyopia'],
          'glassPower': '2.0',
          'haveTheGlassesBeenSold': 'yes',
          'patientReferredForOperation': 'yes',
          'ncdServiceProvided': 'no',
        }),
        [
          'PRESBYOPIA',
          'GLASSES_SOLD',
          'REFERRED_FOR_OPERATION',
          'GLASS_POWER:2.0',
        ],
      );
    });

    test('NCD yes adds camp token and uncontrolled BP/BG from referral', () {
      expect(
        CataractStatus.status(
          {
            'eyeTestOutcomes': ['cataracts'],
            'ncdServiceProvided': 'yes',
            'patientReferredForOperation': 'no',
          },
          referredReasons: [NcdStatus.reasonHighBp, NcdStatus.reasonHighBg],
        ),
        [
          'CATARACTS',
          'UNCONTROLLED_BP',
          'UNCONTROLLED_BG',
          'NCD_SERVICE_IN_CATARACT_CAMP',
        ],
      );
    });

    test('does not emit NCD camp token when ncdServiceProvided is no', () {
      final status = CataractStatus.status({
        'eyeTestOutcomes': ['myopia'],
        'referPlace': 'districtHospital',
        'ncdServiceProvided': 'no',
      });

      expect(status, ['MYOPIA']);
      expect(status, isNot(contains('NCD_SERVICE_IN_CATARACT_CAMP')));
    });

    test('reads pre-transform eyeDisease lists', () {
      expect(
        CataractStatus.status({
          'eyeDisease': ['pterygium'],
          'patientReferredForOperation': 'no',
        }),
        ['PTERYGIUM'],
      );
    });
  });
}
