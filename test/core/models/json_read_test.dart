import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/json_read.dart';

void main() {
  group('JsonRead.asDateTime / firstDateTime', () {
    test('parses ISO string', () {
      final d = JsonRead.asDateTime('2026-01-15T00:00:00.000');
      expect(d, DateTime.parse('2026-01-15T00:00:00.000'));
    });

    test('parses epoch millis int (avoids String cast trap)', () {
      final ms = DateTime(2026, 3, 1).millisecondsSinceEpoch;
      final d = JsonRead.asDateTime(ms);
      expect(d, DateTime.fromMillisecondsSinceEpoch(ms));
    });

    test('parses epoch millis numeric string', () {
      final ms = DateTime(2026, 3, 1).millisecondsSinceEpoch;
      final d = JsonRead.asDateTime('$ms');
      expect(d, DateTime.fromMillisecondsSinceEpoch(ms));
    });

    test('firstDateTime reads first matching key', () {
      final ms = DateTime(2026, 4, 10).millisecondsSinceEpoch;
      final d = JsonRead.firstDateTime({
        'other': null,
        'lmpDate': ms,
      }, const [
        'lastMenstrualPeriod',
        'lmpDate',
      ]);
      expect(d, DateTime.fromMillisecondsSinceEpoch(ms));
    });

    test('returns null for blank / unparsable', () {
      expect(JsonRead.asDateTime(null), isNull);
      expect(JsonRead.asDateTime(''), isNull);
      expect(JsonRead.asDateTime('not-a-date'), isNull);
    });
  });
}
