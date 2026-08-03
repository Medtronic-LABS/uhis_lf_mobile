import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/visit_summary_details.dart';

void main() {
  group('VisitSummaryDetails.patchFor', () {
    final date = DateTime.utc(2026, 8, 15);

    test('ANC always stamps nextVisitDate', () {
      final patch = VisitSummaryDetails.patchFor(
        assessmentType: 'ANC',
        nextVisitDate: date,
        isReferred: false,
      );
      expect(patch['nextVisitDate'], '2026-08-15T00:00:00+00:00');
      expect(patch.containsKey('referralFacilityType'), isFalse);
    });

    test('ANC referred adds referralFacilityType option id', () {
      final patch = VisitSummaryDetails.patchFor(
        assessmentType: 'ANC',
        nextVisitDate: date,
        isReferred: true,
        referralFacilityType: 'uhfwc',
      );
      expect(patch['nextVisitDate'], isNotNull);
      // Spice Done remaps spinner option id → summary.referralFacilityType.
      expect(patch['referralFacilityType'], 'uhfwc');
    });

    test('NCD stamps nextVisitDate only when referred', () {
      expect(
        VisitSummaryDetails.patchFor(
          assessmentType: 'NCD',
          nextVisitDate: date,
          isReferred: false,
        ),
        isEmpty,
      );
      final referred = VisitSummaryDetails.patchFor(
        assessmentType: 'NCD',
        nextVisitDate: date,
        isReferred: true,
        referralFacilityType: 'Upazila Health Complex',
      );
      expect(referred['nextVisitDate'], '2026-08-15T00:00:00+00:00');
      expect(referred['referralFacilityType'], 'Upazila Health Complex');
    });

    test('TB does not stamp nextVisitDate', () {
      final patch = VisitSummaryDetails.patchFor(
        assessmentType: 'TB',
        nextVisitDate: date,
        isReferred: true,
        referralFacilityType: 'Community Clinic',
        referredSiteId: 'site-1',
      );
      expect(patch.containsKey('nextVisitDate'), isFalse);
      expect(patch['referralFacilityType'], 'Community Clinic');
      expect(patch['referredSiteId'], 'site-1');
    });

    test('CHILDHOOD_VISIT only stamps when a date is provided', () {
      expect(
        VisitSummaryDetails.patchFor(
          assessmentType: 'CHILDHOOD_VISIT',
          nextVisitDate: null,
          isReferred: false,
        ),
        isEmpty,
      );
      expect(
        VisitSummaryDetails.patchFor(
          assessmentType: 'CHILDHOOD_VISIT',
          nextVisitDate: date,
          isReferred: false,
        )['nextVisitDate'],
        '2026-08-15T00:00:00+00:00',
      );
    });

    test('EYE_CARE stamps referral facility when referred, not nextVisitDate', () {
      final patch = VisitSummaryDetails.patchFor(
        assessmentType: 'EYE_CARE',
        nextVisitDate: date,
        isReferred: true,
        referralFacilityType: 'Community Clinic',
      );
      expect(patch.containsKey('nextVisitDate'), isFalse);
      expect(patch['referralFacilityType'], 'Community Clinic');
    });
  });
}
