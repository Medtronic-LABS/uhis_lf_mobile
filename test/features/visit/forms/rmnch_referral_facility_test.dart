import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/forms/rmnch_referral_facility.dart';

void main() {
  group('RmnchReferralFacility.labelOf', () {
    tearDown(() {
      AppLocale.current = AppLanguage.bangla;
    });

    test('returns Bangla when app language is Bangla', () {
      AppLocale.current = AppLanguage.bangla;
      final uhfwc = RmnchReferralFacility.options.firstWhere((o) => o.id == 'uhfwc');
      expect(
        RmnchReferralFacility.labelOf(uhfwc),
        'ইউনিয়ন স্বাস্থ্য ও পরিবার কল্যাণ কেন্দ্র',
      );
    });

    test('returns English when app language is English', () {
      AppLocale.current = AppLanguage.english;
      final uhfwc = RmnchReferralFacility.options.firstWhere((o) => o.id == 'uhfwc');
      expect(
        RmnchReferralFacility.labelOf(uhfwc),
        'UHFWC (Union health and family welfare center)',
      );
    });
  });

  group('RmnchReferralFacility.showOnStep3', () {
    test('shows for ANC/PNC when referred', () {
      expect(
        RmnchReferralFacility.showOnStep3(
          programme: Programme.anc,
          isReferred: true,
        ),
        isTrue,
      );
      expect(
        RmnchReferralFacility.showOnStep3(
          programme: Programme.pnc,
          isReferred: true,
        ),
        isTrue,
      );
    });

    test('shows when visit includes ANC even if primary is PW', () {
      expect(
        RmnchReferralFacility.showOnStep3(
          programme: Programme.pw,
          isReferred: true,
          visitProgrammes: {Programme.pw, Programme.anc},
        ),
        isTrue,
      );
    });

    test('shows when visit includes PNC even if primary is PW', () {
      expect(
        RmnchReferralFacility.showOnStep3(
          programme: Programme.pw,
          isReferred: true,
          visitProgrammes: {Programme.pw, Programme.pnc},
        ),
        isTrue,
      );
    });

    test('hides when not referred or other programme', () {
      expect(
        RmnchReferralFacility.showOnStep3(
          programme: Programme.anc,
          isReferred: false,
        ),
        isFalse,
      );
      expect(
        RmnchReferralFacility.showOnStep3(
          programme: Programme.ncd,
          isReferred: true,
        ),
        isFalse,
      );
      expect(
        RmnchReferralFacility.showOnStep3(
          programme: Programme.pw,
          isReferred: true,
          visitProgrammes: {Programme.pw},
        ),
        isFalse,
      );
    });
  });

  group('RmnchReferralFacility.initialSelection', () {
    test('defaults to first Spice option (uhfwc)', () {
      expect(RmnchReferralFacility.initialSelection(), 'uhfwc');
      expect(
        RmnchReferralFacility.initialSelection(preferredId: ''),
        'uhfwc',
      );
      expect(
        RmnchReferralFacility.initialSelection(preferredId: 'unknown'),
        'uhfwc',
      );
    });

    test('keeps a known preferred option id', () {
      expect(
        RmnchReferralFacility.initialSelection(
          preferredId: 'districtHospital',
        ),
        'districtHospital',
      );
    });

    test('options match Spice ANC/PNC referralFacility ids', () {
      expect(
        RmnchReferralFacility.options.map((o) => o.id).toList(),
        [
          'uhfwc',
          'mcwc',
          'uhc',
          'districtHospital',
          'medicalCollegeHospital',
        ],
      );
    });
  });
}
