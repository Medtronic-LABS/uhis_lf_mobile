import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/briefing/briefing_models.dart';

void main() {
  group('GreetingContent.fromJson', () {
    test('parses hint_bn and hint_bangla wire keys', () {
      final greeting = GreetingContent.fromJson(const {
        'bangla': 'বাংলা',
        'english': 'english',
        'hint': 'generic hint',
        'hint_bn': 'bn hint',
        'hint_bangla': 'bangla hint',
      });

      expect(greeting.hint, 'generic hint');
      expect(greeting.hintBn, 'bn hint');
      expect(greeting.hintBangla, 'bangla hint');
    });

    test('hintBn and hintBangla default to empty when the API omits them', () {
      final greeting = GreetingContent.fromJson(const {
        'bangla': 'বাংলা',
        'english': 'english',
        'hint': 'generic hint',
      });

      expect(greeting.hintBn, '');
      expect(greeting.hintBangla, '');
    });

    test('trims whitespace from hint_bn and hint_bangla', () {
      final greeting = GreetingContent.fromJson(const {
        'bangla': '',
        'english': '',
        'hint': '',
        'hint_bn': '  bn hint  ',
        'hint_bangla': '  bangla hint  ',
      });

      expect(greeting.hintBn, 'bn hint');
      expect(greeting.hintBangla, 'bangla hint');
    });

    test('isEmpty is false when only hintBn is populated', () {
      final greeting = GreetingContent.fromJson(const {
        'bangla': '',
        'english': '',
        'hint': '',
        'hint_bn': 'bn hint',
      });

      expect(greeting.isEmpty, isFalse);
    });

    test('isEmpty is true when bangla/english/hint/hintBn/hintBangla are all blank', () {
      final greeting = GreetingContent.fromJson(const {
        'bangla': '',
        'english': '',
        'hint': '',
      });

      expect(greeting.isEmpty, isTrue);
    });
  });
}
