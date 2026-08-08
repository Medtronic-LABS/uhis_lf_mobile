import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/assessment_thresholds.dart';

void main() {
  group('isPlausibleTemperatureF', () {
    test('accepts a normal body temperature', () {
      expect(isPlausibleTemperatureF(98.6), isTrue);
    });

    test('accepts the "could not be measured" sentinel (0)', () {
      expect(isPlausibleTemperatureF(0), isTrue);
    });

    test('rejects an implausibly low reading', () {
      expect(isPlausibleTemperatureF(3), isFalse);
    });

    test('rejects an implausibly high reading', () {
      expect(isPlausibleTemperatureF(900), isFalse);
    });

    test('accepts a genuine high fever without rejecting it as out of range', () {
      expect(isPlausibleTemperatureF(106), isTrue);
    });
  });

  group('isPlausibleBpReading', () {
    test('accepts a normal systolic reading', () {
      expect(isPlausibleBpReading(120), isTrue);
    });

    test('accepts the "could not be measured" sentinel (0)', () {
      expect(isPlausibleBpReading(0), isTrue);
    });

    test('rejects an implausibly low reading', () {
      expect(isPlausibleBpReading(3), isFalse);
    });

    test('rejects an implausibly high reading', () {
      expect(isPlausibleBpReading(900), isFalse);
    });

    test('accepts a genuine hypertensive-crisis reading without rejecting it', () {
      expect(isPlausibleBpReading(250), isTrue);
    });
  });

  group('isPlausibleFundalHeightCm', () {
    test('accepts a normal term fundal height', () {
      expect(isPlausibleFundalHeightCm(34), isTrue);
    });

    test('rejects an implausibly low reading', () {
      expect(isPlausibleFundalHeightCm(1), isFalse);
    });

    test('rejects an implausibly high reading', () {
      expect(isPlausibleFundalHeightCm(90), isFalse);
    });
  });

  group('isPlausibleHemoglobin', () {
    test('accepts 1–20 g/dL inclusive', () {
      expect(isPlausibleHemoglobin(1.0), isTrue);
      expect(isPlausibleHemoglobin(20.0), isTrue);
      expect(isPlausibleHemoglobin(11.2), isTrue);
    });

    test('rejects 0 and values outside 1–20', () {
      expect(isPlausibleHemoglobin(0), isFalse);
      expect(isPlausibleHemoglobin(0.9), isFalse);
      expect(isPlausibleHemoglobin(20.1), isFalse);
      expect(isPlausibleHemoglobin(25), isFalse);
    });
  });

  group('isPlausibleGlucoseMmol', () {
    test('accepts 0–33 mmol/L inclusive', () {
      expect(isPlausibleGlucoseMmol(0), isTrue);
      expect(isPlausibleGlucoseMmol(0.6), isTrue);
      expect(isPlausibleGlucoseMmol(15), isTrue);
      expect(isPlausibleGlucoseMmol(33), isTrue);
    });

    test('rejects values outside 0–33', () {
      expect(isPlausibleGlucoseMmol(-0.1), isFalse);
      expect(isPlausibleGlucoseMmol(33.1), isFalse);
    });
  });

  group('isPlausibleSupplementTablets', () {
    test('accepts 0–60 inclusive', () {
      expect(isPlausibleSupplementTablets(0), isTrue);
      expect(isPlausibleSupplementTablets(30), isTrue);
      expect(isPlausibleSupplementTablets(60), isTrue);
    });

    test('rejects values outside 0–60', () {
      expect(isPlausibleSupplementTablets(-1), isFalse);
      expect(isPlausibleSupplementTablets(61), isFalse);
      expect(isPlausibleSupplementTablets(90), isFalse);
    });
  });
}
