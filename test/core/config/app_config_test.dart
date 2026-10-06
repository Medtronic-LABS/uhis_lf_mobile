import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/config/app_config.dart';

void main() {
  group('AppConfig.joinUrlSegment', () {
    test('adds a slash when the base has none', () {
      expect(
        AppConfig.joinUrlSegment('https://uhis-next-backend.labsplatform.com', 'admin-api'),
        'https://uhis-next-backend.labsplatform.com/admin-api',
      );
    });

    test('does not double the slash when the base already ends with one', () {
      expect(
        AppConfig.joinUrlSegment('https://spice-dev-backend.uhis.labsplatform.com/', 'admin-api'),
        'https://spice-dev-backend.uhis.labsplatform.com/admin-api',
      );
    });
  });
}
