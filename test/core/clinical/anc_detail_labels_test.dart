import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/referral_facility_labels.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/features/visit/forms/anc_existing_illness.dart';

void main() {
  group('ReferralFacilityLabels.labelOf', () {
    tearDown(() {
      AppLocale.current = AppLanguage.bangla;
    });

    test('maps RMNCH wire id uhfwc', () {
      AppLocale.current = AppLanguage.english;
      expect(
        ReferralFacilityLabels.labelOf('uhfwc'),
        'UHFWC (Union health and family welfare center)',
      );
    });
  });

  group('AncExistingIllness', () {
    tearDown(() {
      AppLocale.current = AppLanguage.bangla;
    });

    test('formats existing illness ids', () {
      AppLocale.current = AppLanguage.english;
      expect(
        AncExistingIllness.formatExistingIllnessList('["dm","heartDisease"]'),
        'DM, Heart Disease',
      );
    });

    test('formats on-treatment illness id', () {
      AppLocale.current = AppLanguage.english;
      expect(
        AncExistingIllness.formatOnTreatmentList('["heartDisease"]'),
        'Heart Disease',
      );
    });

    test('handles comma-separated legacy string', () {
      AppLocale.current = AppLanguage.english;
      expect(
        AncExistingIllness.formatExistingIllnessList('dm, heartDisease'),
        'DM, Heart Disease',
      );
    });
  });
}
