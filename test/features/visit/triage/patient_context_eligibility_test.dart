import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/triage/patient_context_builder.dart';

PatientContext _ctx(int ageMonths, {Sex sex = Sex.female}) => PatientContext(
      patientId: 'p',
      ageMonths: ageMonths,
      sex: sex,
      isPregnant: false,
    );

void main() {
  group('PatientContext.isAdult (NCD, 18y/216mo)', () {
    test('215mo (17y11mo) is not adult', () {
      expect(_ctx(215).isAdult, isFalse);
    });
    test('216mo (exactly 18y) is adult', () {
      expect(_ctx(216).isAdult, isTrue);
    });
  });

  group('PatientContext.isEyeCareCataractEligible (35y/420mo)', () {
    test('419mo (34y11mo) is not eligible', () {
      expect(_ctx(419).isEyeCareCataractEligible, isFalse);
    });
    test('420mo (exactly 35y) is eligible', () {
      expect(_ctx(420).isEyeCareCataractEligible, isTrue);
    });
    test('has no upper bound', () {
      expect(_ctx(900).isEyeCareCataractEligible, isTrue);
    });
  });

  group('PatientContext.isReproductiveAge (14-55y / 168-661mo, inclusive-exclusive)', () {
    test('167mo (13y11mo) is below the window', () {
      expect(_ctx(167).isReproductiveAge, isFalse);
    });
    test('168mo (exactly 14y) is within the window', () {
      expect(_ctx(168).isReproductiveAge, isTrue);
    });
    test('660mo (54y11mo) is within the window', () {
      expect(_ctx(660).isReproductiveAge, isTrue);
    });
    test('661mo (exactly 55y1mo) is outside the window (exclusive upper bound)', () {
      expect(_ctx(661).isReproductiveAge, isFalse);
    });
  });

  group('PatientContext.isYoungChild (RMNCH childhoodVisit, 0-25mo exclusive)', () {
    test('24mo is within the window', () {
      expect(_ctx(24).isYoungChild, isTrue);
    });
    test('25mo is outside the window (exclusive upper bound)', () {
      expect(_ctx(25).isYoungChild, isFalse);
    });
  });
}
