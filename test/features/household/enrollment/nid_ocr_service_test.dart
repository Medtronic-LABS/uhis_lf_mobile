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
}
