import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/service_eligibility.dart';

void main() {
  group('hasAnyEligibleProgramme', () {
    test('unknown age fails open (does not block)', () {
      expect(hasAnyEligibleProgramme(ageYears: null), isTrue);
    });

    test('under-5 is eligible (vaccination/IMCI)', () {
      expect(hasAnyEligibleProgramme(ageYears: 0), isTrue);
      expect(hasAnyEligibleProgramme(ageYears: 4), isTrue);
    });

    test('ages 5-14 are the eligibility gap', () {
      expect(hasAnyEligibleProgramme(ageYears: 5), isFalse);
      expect(hasAnyEligibleProgramme(ageYears: 10), isFalse);
      expect(hasAnyEligibleProgramme(ageYears: 14), isFalse);
    });

    test('15+ is eligible (ANC/PNC/FP/PW/NCD/TB)', () {
      expect(hasAnyEligibleProgramme(ageYears: 15), isTrue);
      expect(hasAnyEligibleProgramme(ageYears: 18), isTrue);
      expect(hasAnyEligibleProgramme(ageYears: 60), isTrue);
    });
  });
}
