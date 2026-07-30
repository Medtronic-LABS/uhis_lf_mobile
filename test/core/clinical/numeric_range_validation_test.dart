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
}
