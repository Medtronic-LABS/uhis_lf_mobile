import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/features/visit/forms/delivery_facility_type.dart';

void main() {
  group('DeliveryFacilityType.labelOfId', () {
    tearDown(() {
      AppLocale.current = AppLanguage.bangla;
    });

    test('returns Bangla when app language is Bangla', () {
      AppLocale.current = AppLanguage.bangla;
      expect(
        DeliveryFacilityType.labelOfId('ngoFacility'),
        'এনজিও স্বাস্থ্যসেবা কেন্দ্র',
      );
    });

    test('returns English when app language is English', () {
      AppLocale.current = AppLanguage.english;
      expect(
        DeliveryFacilityType.labelOfId('ngoFacility'),
        'NGO facility',
      );
      expect(
        DeliveryFacilityType.labelOfId('uhfwc'),
        'UHFWC (Union health and family welfare center)',
      );
    });

    test('returns raw value when id is unknown', () {
      expect(DeliveryFacilityType.labelOfId('unknownKey'), 'unknownKey');
    });
  });
}
