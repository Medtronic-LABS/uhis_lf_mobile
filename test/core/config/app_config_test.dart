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
        AppConfig.joinUrlSegment('https://backend.example.test/', 'admin-api'),
        'https://backend.example.test/admin-api',
      );
    });
  });

  group('coachingServiceUrl', () {
    test('derives from apiBaseUrl when COACHING_SERVICE_URL is unset', () {
      expect(
        AppConfig.coachingServiceUrl,
        AppConfig.joinUrlSegment(AppConfig.apiBaseUrl, 'micro-coaching'),
      );
    });
  });
}
