import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/immunisation/epi_card_scanner.dart';

void main() {
  group('EpiCardScanner.matchText — vaccine code matching', () {
    const allCodes = [
      'BCG', 'PENTA1', 'PENTA2', 'PENTA3',
      'PCV1', 'PCV2', 'PCV3',
      'OPV1', 'OPV2', 'OPV3',
      'FIPV1', 'FIPV2',
      'MR1', 'MR2',
      'TCV',
    ];

    test('matches BCG by name', () {
      final r = EpiCardScanner.matchText('BCG\n12/03/2024', ['BCG']);
      expect(r.matchedCodes, contains('BCG'));
    });

    test('matches Penta case-insensitive', () {
      final r = EpiCardScanner.matchText('Penta-1  given on 05/06/2023', ['PENTA1']);
      expect(r.matchedCodes, contains('PENTA1'));
    });

    test('matches Pentavalent-2 alias', () {
      final r = EpiCardScanner.matchText('Pentavalent-2\n10/07/2023', ['PENTA2']);
      expect(r.matchedCodes, contains('PENTA2'));
    });

    test('matches PCV by code fragment', () {
      final r = EpiCardScanner.matchText('PCV-3 administered', ['PCV3']);
      expect(r.matchedCodes, contains('PCV3'));
    });

    test('matches OPV', () {
      final r = EpiCardScanner.matchText('OPV 2\nDate: 14/08/2023', ['OPV2']);
      expect(r.matchedCodes, contains('OPV2'));
    });

    test('matches fIPV alias ipv-1', () {
      final r = EpiCardScanner.matchText('IPV-1 dose given', ['FIPV1']);
      expect(r.matchedCodes, contains('FIPV1'));
    });

    test('matches MR-1 vaccine', () {
      final r = EpiCardScanner.matchText('MR-1\n01/11/2023', ['MR1']);
      expect(r.matchedCodes, contains('MR1'));
    });

    test('matches MR-2 via measles-rubella alias', () {
      final r = EpiCardScanner.matchText('Measles-Rubella 2\n15/01/2024', ['MR2']);
      expect(r.matchedCodes, contains('MR2'));
    });

    test('matches TCV', () {
      final r = EpiCardScanner.matchText('TCV given 20/03/2024', ['TCV']);
      expect(r.matchedCodes, contains('TCV'));
    });

    test('returns only target-code matches, not all aliases', () {
      // OCR contains "PCV 1" but target is only PENTA1 and OPV1
      final r = EpiCardScanner.matchText(
        'PCV 1\nPenta-1\nOPV 1',
        ['PENTA1', 'OPV1'],
      );
      expect(r.matchedCodes, containsAll(['PENTA1', 'OPV1']));
      expect(r.matchedCodes, isNot(contains('PCV1')));
    });

    test('returns empty matchedCodes for unrelated text', () {
      final r = EpiCardScanner.matchText('Patient: Rashed, DOB: 01/01/2023', allCodes);
      expect(r.matchedCodes, isEmpty);
    });

    test('anyMatched false when no codes and no date', () {
      final r = EpiCardScanner.matchText('random text without vaccines', allCodes);
      expect(r.anyMatched, isFalse);
    });
  });

  group('EpiCardScanner.matchText — date extraction', () {
    test('extracts DD/MM/YYYY date', () {
      final r = EpiCardScanner.matchText('BCG\n15/03/2023', ['BCG']);
      expect(r.extractedDate, equals(DateTime(2023, 3, 15)));
    });

    test('extracts DD-MM-YYYY date', () {
      final r = EpiCardScanner.matchText('PENTA 1\n07-06-2023', ['PENTA1']);
      expect(r.extractedDate, equals(DateTime(2023, 6, 7)));
    });

    test('expands 2-digit year', () {
      final r = EpiCardScanner.matchText('OPV 1\n03/09/23', ['OPV1']);
      expect(r.extractedDate?.year, equals(2023));
    });

    test('returns null for future dates', () {
      final r = EpiCardScanner.matchText('BCG\n01/01/2099', ['BCG']);
      expect(r.extractedDate, isNull);
    });

    test('returns null for impossible dates', () {
      final r = EpiCardScanner.matchText('BCG\n45/13/2023', ['BCG']);
      expect(r.extractedDate, isNull);
    });

    test('anyMatched true when date extracted even without code match', () {
      final r = EpiCardScanner.matchText('Some text\n15/03/2023', ['BCG']);
      // No code matched but date was found
      expect(r.matchedCodes, isEmpty);
      expect(r.extractedDate, isNotNull);
      expect(r.anyMatched, isTrue);
    });

    test('picks first valid date from multi-date text', () {
      final r = EpiCardScanner.matchText(
          'BCG 12/01/2023\nPENTA 1 15/03/2023', ['BCG', 'PENTA1']);
      expect(r.extractedDate, equals(DateTime(2023, 1, 12)));
    });
  });
}
