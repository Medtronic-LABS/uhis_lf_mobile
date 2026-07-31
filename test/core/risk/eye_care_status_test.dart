import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/risk/eye_care_status.dart';

void main() {
  group('EyeCareStatus.status', () {
    test('matches the Spice token order: problems, sold, glass power', () {
      final status = EyeCareStatus.status({
        'eyeTestOutcomes': ['presbyopia'],
        'glassPower': '2.0',
        'haveTheGlassesBeenSold': 'yes',
        'typeOfGlass': 'sv',
        'typeOfFrame': 'metal',
        'firstTimeUser': 'yes',
      });

      expect(status, ['PRESBYOPIA', 'GLASSES_SOLD', 'GLASS_POWER:2.0']);
    });

    test('omits GLASSES_SOLD when the glasses were not sold', () {
      final status = EyeCareStatus.status({
        'eyeTestOutcomes': ['cataracts'],
        'haveTheGlassesBeenSold': 'no',
      });

      expect(status, ['CATARACTS']);
    });

    test('reads the cataract form eyeDisease list and dedupes ids', () {
      final status = EyeCareStatus.status({
        'eyeDisease': ['glaucoma', 'myopia'],
        'eyeTestOutcomes': ['myopia'],
      });

      expect(status, ['GLAUCOMA', 'MYOPIA']);
    });

    test('drops NO_EYE_PROBLEM only when skipNoProblem is set (NCD branch)', () {
      const card = {
        'eyeTestOutcomes': ['noProblem'],
      };

      expect(EyeCareStatus.status(card), ['NO_EYE_PROBLEM']);
      expect(EyeCareStatus.status(card, skipNoProblem: true), isEmpty);
    });

    test('ignores unknown option ids and an absent card', () {
      expect(
        EyeCareStatus.status({
          'eyeTestOutcomes': ['somethingElse'],
        }),
        isEmpty,
      );
      expect(EyeCareStatus.status(null), isEmpty);
      expect(EyeCareStatus.status(const {}), isEmpty);
    });
  });
}
