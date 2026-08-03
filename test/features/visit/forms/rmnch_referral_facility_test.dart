import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/forms/rmnch_referral_facility.dart';

void main() {
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
