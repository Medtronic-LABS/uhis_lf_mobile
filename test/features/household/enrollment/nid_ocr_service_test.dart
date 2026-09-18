import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/household/enrollment/nid_ocr_service.dart';

void main() {
  group('extractName', () {
    test('reads the English name on the line after the Name label', () {
      const text = '''
Government of the People's Republic of Bangladesh
National ID Card
Name
NOOR ALAM
Date of Birth 25 Nov 1983
NID No. 600 458 9963
''';
      expect(NidOcrService.extractName(text), 'Noor Alam');
    });

    test('reads an inline "Name X Y" value', () {
      expect(NidOcrService.extractName('Name RANU MONDOL'), 'Ranu Mondol');
    });

    test('never returns card boilerplate as the name (LEAP-52)', () {
      // Name value missing; the lines around the label are all boilerplate.
      const text = '''
Government of the People's Republic of Bangladesh
National ID Card
Name
Date of Birth 25 Nov 1983
''';
      expect(NidOcrService.extractName(text), isNull);
    });

    test('rejects country/govt words even if positioned after the label', () {
      const text = '''
Name
Republic of Bangladesh
''';
      expect(NidOcrService.extractName(text), isNull);
    });
  });

  group('extractNidNumber', () {
    test('reads a spaced 10-digit Smart NID', () {
      expect(NidOcrService.extractNidNumber('NID No. 600 458 9963'),
          '6004589963');
    });

    test('returns null when no NID-length digit run exists', () {
      expect(NidOcrService.extractNidNumber('Name NOOR ALAM'), isNull);
    });
  });

  group('extractDateOfBirth', () {
    test('parses "25 Nov 1983" to ISO', () {
      expect(NidOcrService.extractDateOfBirth('Date of Birth 25 Nov 1983'),
          '1983-11-25');
    });

    test('tolerates a one-char month OCR misread ("Noy" → Nov)', () {
      expect(NidOcrService.extractDateOfBirth('Date of Birth 25 Noy 1983'),
          '1983-11-25');
    });
  });

  group('extractGender', () {
    test('is null on a front card with no Latin Sex label', () {
      const text = 'Name\nNOOR ALAM\nDate of Birth 25 Nov 1983';
      expect(NidOcrService.extractGender(text), isNull);
    });

    test('reads an explicit Sex label when present', () {
      expect(NidOcrService.extractGender('Sex: Male'), NidGender.male);
      expect(NidOcrService.extractGender('Gender F'), NidGender.female);
    });
  });

  group('parseMrz (card back — reliable gender)', () {
    const mrz = '''
I<BGD000000000<00<<<<<<<<<<<<<
0000000M0000000BGD<<<<<<<<<<<<0
MONDOL<<RANU<<<<<<<<<<<<<<<<
''';

    test('extracts sex from the MRZ (LEAP-49)', () {
      expect(NidOcrService.parseMrz(mrz)?.gender, NidGender.male);
    });

    test('extracts the name from the MRZ name line', () {
      expect(NidOcrService.parseMrz(mrz)?.name, 'Ranu Mondol');
    });

    test('returns null for non-MRZ text', () {
      expect(NidOcrService.parseMrz('Name\nNOOR ALAM'), isNull);
    });
  });

  group('NidGender.label', () {
    test('maps to option-list labels', () {
      expect(NidGender.male.label, 'Male');
      expect(NidGender.female.label, 'Female');
    });
  });
}
