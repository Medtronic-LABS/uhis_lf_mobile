import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/rmnch/deceased_reason.dart';

void main() {
  group('DeceasedReason.buildPayload', () {
    test('neonatal encodes cause ids with prefix', () {
      expect(
        DeceasedReason.buildPayload(
          typeId: DeceasedReason.deathTypeNeonatal,
          freeTextReason: '',
          selectedCauseIds: ['asphyxia', 'pneumonia'],
        ),
        '__neonatal__:asphyxia,pneumonia',
      );
    });

    test('maternal encodes cause ids with prefix', () {
      expect(
        DeceasedReason.buildPayload(
          typeId: DeceasedReason.deathTypeMother,
          freeTextReason: '',
          selectedCauseIds: ['infection'],
        ),
        '__mother__:infection',
      );
    });

    test('free text takes precedence', () {
      expect(
        DeceasedReason.buildPayload(
          typeId: DeceasedReason.deathTypeNeonatal,
          freeTextReason: '  custom reason  ',
          selectedCauseIds: ['infection'],
        ),
        'custom reason',
      );
    });
  });

  group('DeceasedReason.formatForDisplay', () {
    test('maps encoded neonatal causes to labels', () {
      expect(
        DeceasedReason.formatForDisplay('__neonatal__:asphyxia,pneumonia'),
        'Neo Natal(Asphyxia, Pneumonia)',
      );
    });

    test('returns plain text unchanged', () {
      expect(
        DeceasedReason.formatForDisplay('Road accident'),
        'Road accident',
      );
    });
  });

  group('DeceasedReason age helpers', () {
    test('isNeonate true for 10-day-old', () {
      final dob = DateTime.now().subtract(const Duration(days: 10));
      expect(DeceasedReason.isNeonate(dob.toIso8601String()), isTrue);
    });

    test('isNeonate false for 1-year-old', () {
      final dob = DateTime.now().subtract(const Duration(days: 400));
      expect(DeceasedReason.isNeonate(dob.toIso8601String()), isFalse);
    });
  });
}
