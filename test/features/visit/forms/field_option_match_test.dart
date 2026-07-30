import 'package:flutter_test/flutter_test.dart';
import 'package:leapwell/features/visit/forms/form_config.dart';

void main() {
  group('FieldOption.coerceId', () {
    test('passes strings through and stringifies bool/num', () {
      expect(FieldOption.coerceId(null), isNull);
      expect(FieldOption.coerceId('Yes'), 'Yes');
      expect(FieldOption.coerceId(true), 'true');
      expect(FieldOption.coerceId(false), 'false');
      expect(FieldOption.coerceId(1), '1');
    });
  });

  group('FieldOption.matchId', () {
    const boolIdOptions = [
      FieldOption(id: 'true', name: 'Yes'),
      FieldOption(id: 'false', name: 'No'),
    ];
    const yesNoOptions = [
      FieldOption(id: 'Yes', name: 'Yes'),
      FieldOption(id: 'No', name: 'No'),
    ];

    test('matches bool against stringified option ids (isRegularSmoker)', () {
      expect(FieldOption.matchId(true, boolIdOptions), 'true');
      expect(FieldOption.matchId(false, boolIdOptions), 'false');
      expect(FieldOption.matchId('true', boolIdOptions), 'true');
    });

    test('matches bool against Yes/No string option ids', () {
      expect(FieldOption.matchId(true, yesNoOptions), 'Yes');
      expect(FieldOption.matchId(false, yesNoOptions), 'No');
      expect(FieldOption.matchId(1, yesNoOptions), 'Yes');
      expect(FieldOption.matchId(0, yesNoOptions), 'No');
    });

    test('matches display name case-insensitively', () {
      expect(FieldOption.matchId('yes', yesNoOptions), 'Yes');
      expect(FieldOption.matchId('NO', yesNoOptions), 'No');
    });

    test('find returns the option for a preloaded bool', () {
      expect(FieldOption.find(true, boolIdOptions)?.displayName, 'Yes');
      expect(FieldOption.find(true, yesNoOptions)?.id, 'Yes');
      expect(FieldOption.find(null, yesNoOptions), isNull);
    });
  });
}
