import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/unified_payload_mapper.dart';

void main() {
  group('UnifiedPayloadMapper.decompose — eye_care', () {
    test('maps layout_manifest field IDs into a non-empty flat payload', () {
      final data = CanonicalVisitData({
        'eyeTestOutcome': 'myopia',
        'glassPower': '1.5',
        'haveTheGlassesBeenSold': 'Yes',
        'typeOfGlass': 'singleVision',
        'typeOfFrame': 'fullFrame',
        'firstTimeUser': 'No',
        'referPlace': 'medicalCollegeHospital',
        // Noise from co-activated NCD — must not leak into eye_care details.
        'systolic': 169,
        'diastolic': 89,
      });

      final payloads = UnifiedPayloadMapper.decompose(data, {'eye_care'});

      expect(payloads, hasLength(1));
      expect(payloads.single.assessmentType, 'EYE_CARE');
      expect(payloads.single.details, {
        'eyeTestOutcome': 'myopia',
        'glassPower': '1.5',
        'haveTheGlassesBeenSold': 'Yes',
        'typeOfGlass': 'singleVision',
        'typeOfFrame': 'fullFrame',
        'firstTimeUser': 'No',
        'referPlace': 'medicalCollegeHospital',
      });
    });

    test('does not emit empty {} when form fields were filled', () {
      final data = CanonicalVisitData({
        'eyeTestOutcome': 'myopia',
        'referPlace': 'medicalCollegeHospital',
      });

      final payloads = UnifiedPayloadMapper.decompose(data, {'eyeCare'});

      expect(payloads.single.details, isNotEmpty);
      expect(payloads.single.details['eyeTestOutcome'], 'myopia');
      expect(payloads.single.details['referPlace'], 'medicalCollegeHospital');
      // Old placeholder keys must not be required / present.
      expect(payloads.single.details.containsKey('visualAcuityRight'), isFalse);
    });
  });
}
