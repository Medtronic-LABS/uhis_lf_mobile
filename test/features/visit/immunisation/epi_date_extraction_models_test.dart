import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/immunisation/epi_date_extraction_models.dart';

void main() {
  group('EpiDoseExtraction.fromJson', () {
    test('parses a full dose entry', () {
      final d = EpiDoseExtraction.fromJson({
        'vaccineCode': 'BCG',
        'dose': 1,
        'date': '2023-01-15',
        'confidence': 0.9,
        'rawText': '15/1/23',
      });
      expect(d.vaccineCode, 'BCG');
      expect(d.dose, 1);
      expect(d.date, DateTime(2023, 1, 15));
      expect(d.confidence, 0.9);
      expect(d.rawText, '15/1/23');
    });

    test('null date stays null, confidence defaults to 0', () {
      final d = EpiDoseExtraction.fromJson({'vaccineCode': 'PENTA1'});
      expect(d.date, isNull);
      expect(d.confidence, 0.0);
    });
  });

  group('EpiDateExtractionResult', () {
    test('matchedCodes includes codes even when date is null', () {
      final result = EpiDateExtractionResult.fromJson({
        'doses': [
          {'vaccineCode': 'BCG', 'date': '2023-01-15'},
          {'vaccineCode': 'PENTA1', 'date': null},
        ],
      });
      expect(result.matchedCodes, containsAll(['BCG', 'PENTA1']));
    });

    test('dateByCode drops entries with a null date', () {
      final result = EpiDateExtractionResult.fromJson({
        'doses': [
          {'vaccineCode': 'BCG', 'date': '2023-01-15'},
          {'vaccineCode': 'PENTA1', 'date': null},
        ],
      });
      expect(result.dateByCode, {'BCG': DateTime(2023, 1, 15)});
    });

    test('first non-null date wins when the same code repeats', () {
      final result = EpiDateExtractionResult.fromJson({
        'doses': [
          {'vaccineCode': 'MR1', 'date': '2023-02-01'},
          {'vaccineCode': 'MR1', 'date': '2023-03-01'},
        ],
      });
      expect(result.dateByCode['MR1'], DateTime(2023, 2, 1));
    });

    test('empty doses list parses cleanly', () {
      final result = EpiDateExtractionResult.fromJson({'doses': []});
      expect(result.matchedCodes, isEmpty);
      expect(result.dateByCode, isEmpty);
    });
  });
}
