import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/household/enrollment/nid_ocr_service.dart';

void main() {
  group('NidOcrService.extractNidNumber', () {
    test('reads a 10-digit Smart NID number', () {
      const text = 'Name: Fatema Begum\nID NO: 1234567890';
      expect(NidOcrService.extractNidNumber(text), '1234567890');
    });

    test('reads a 13-digit NID number', () {
      expect(
        NidOcrService.extractNidNumber('NID No\n3456789012345'),
        '3456789012345',
      );
    });

    test('reads a 17-digit NID number', () {
      expect(
        NidOcrService.extractNidNumber('12345678901234567'),
        '12345678901234567',
      );
    });

    test('joins the space-separated digit groups OCR emits on one line', () {
      expect(
        NidOcrService.extractNidNumber('NID No: 1234 5678 90'),
        '1234567890',
      );
    });

    test('ignores date-of-birth and year digits, returns the NID', () {
      const text = 'Date of Birth: 01 Jan 1990\nID NO: 3456789012345';
      expect(NidOcrService.extractNidNumber(text), '3456789012345');
    });

    test('prefers the longest valid NID when several are present', () {
      const text = 'Old: 1234567890\nNew NID: 12345678901234567';
      expect(NidOcrService.extractNidNumber(text), '12345678901234567');
    });

    test('returns null when no NID-shaped number is present', () {
      expect(NidOcrService.extractNidNumber('Name only, phone 017123'), isNull);
    });

    test('rejects an 11-digit run (e.g. a mobile number)', () {
      expect(NidOcrService.extractNidNumber('01711223344'), isNull);
    });
  });

  group('NidOcrService.extractName', () {
    // Mirrors the Latin lines ML Kit reads off a real Smart NID card.
    const cardText = 'Government of the Peoples Republic of Bangladesh\n'
        'National ID Card\n'
        'Name\n'
        'NOOR ALAM\n'
        'Date of Birth 25 Nov 1983\n'
        'NID No. 600 458 9963';

    test('reads the English name on the line after the Name label', () {
      expect(NidOcrService.extractName(cardText), 'Noor Alam');
    });

    test('does not mistake the National ID Card header for the name', () {
      expect(
        NidOcrService.extractName('National ID Card\nName\nRomana Rahman'),
        'Romana Rahman',
      );
    });

    test('handles an inline "Name X" layout', () {
      expect(NidOcrService.extractName('Name ROMANA RAHMAN'), 'Romana Rahman');
    });

    test('returns null when no name label is present', () {
      expect(NidOcrService.extractName('NID No. 600 458 9963'), isNull);
    });
  });

  group('NidOcrService.extractDateOfBirth', () {
    test('parses "25 Nov 1983" to ISO yyyy-MM-dd', () {
      expect(
        NidOcrService.extractDateOfBirth('Date of Birth 25 Nov 1983'),
        '1983-11-25',
      );
    });

    test('parses a single-digit day', () {
      expect(
        NidOcrService.extractDateOfBirth('Date of Birth 5 Jan 1990'),
        '1990-01-05',
      );
    });

    test('returns null when no date is present', () {
      expect(NidOcrService.extractDateOfBirth('Name\nNOOR ALAM'), isNull);
    });
  });
}
