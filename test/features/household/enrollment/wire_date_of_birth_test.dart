import 'package:flutter_test/flutter_test.dart';
import 'package:leapwell/features/household/enrollment/enrollment_repository.dart';

void main() {
  group('EnrollmentRepository.wireDateOfBirth', () {
    test('keeps ISO date with UTC midnight', () {
      expect(
        EnrollmentRepository.wireDateOfBirth('1990-05-15'),
        '1990-05-15T00:00:00+00:00',
      );
    });

    test('parses DD/MM/YYYY (UI hint format) so wire is never empty', () {
      expect(
        EnrollmentRepository.wireDateOfBirth('15/05/1990'),
        '1990-05-15T00:00:00+00:00',
      );
    });

    test('derives from age when DOB empty', () {
      final year = DateTime.now().toUtc().year - 40;
      expect(
        EnrollmentRepository.wireDateOfBirth('', age: 40),
        '${year.toString().padLeft(4, '0')}-01-01T00:00:00+00:00',
      );
    });

    test('never returns empty (Android non-null String contract)', () {
      final wired = EnrollmentRepository.wireDateOfBirth('');
      expect(wired, isNotEmpty);
      expect(wired, contains('T'));
    });
  });
}
