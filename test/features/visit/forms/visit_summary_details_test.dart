import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/forms/visit_summary_details.dart';
import 'package:uhis_next/features/visit/naba/naba_models.dart';

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

    test('FAMILY_PLANNING does not stamp nextVisitDate', () {
      final patch = VisitSummaryDetails.patchFor(
        assessmentType: 'FAMILY_PLANNING',
        nextVisitDate: date,
        isReferred: false,
      );
      expect(patch, isEmpty);
    });

    test('PWPROFILE does not stamp nextVisitDate', () {
      final patch = VisitSummaryDetails.patchFor(
        assessmentType: 'PWPROFILE',
        nextVisitDate: date,
        isReferred: false,
      );
      expect(patch, isEmpty);
    });

    test('CATARACT stamps nextVisitDate only when referred', () {
      expect(
        VisitSummaryDetails.patchFor(
          assessmentType: 'CATARACT',
          nextVisitDate: date,
          isReferred: false,
        ),
        isEmpty,
      );
      expect(
        VisitSummaryDetails.patchFor(
          assessmentType: 'CATARACT',
          nextVisitDate: date,
          isReferred: true,
          referralFacilityType: 'Community Clinic',
        )['nextVisitDate'],
        '2026-08-15T00:00:00+00:00',
      );
    });
  });

  group('VisitSummaryDetails follow-up summary UI', () {
    test('filters family planning follow-up rows', () {
      const items = [
        NabaFollowUpItem(
          activity: 'ANC visit',
          timeline: 'In 4 weeks',
          programme: 'ANC',
        ),
        NabaFollowUpItem(
          activity: 'FP counselling',
          timeline: 'In 2 weeks',
          programme: 'FAMILY_PLANNING',
        ),
      ];
      final filtered = VisitSummaryDetails.followUpItemsForSummary(items);
      expect(filtered, hasLength(1));
      expect(filtered.first.programme, 'ANC');
    });

    test('filters PW registration follow-up rows', () {
      const items = [
        NabaFollowUpItem(
          activity: 'ANC visit',
          timeline: 'In 4 weeks',
          programme: 'ANC',
        ),
        NabaFollowUpItem(
          activity: 'Return for ANC',
          timeline: 'In 4 weeks',
          programme: 'PWPROFILE',
        ),
      ];
      final filtered = VisitSummaryDetails.followUpItemsForSummary(items);
      expect(filtered, hasLength(1));
      expect(filtered.first.programme, 'ANC');
    });

    test('skips generic follow-up fallback on FP-only visits', () {
      expect(
        VisitSummaryDetails.shouldAddGenericFollowUpFallback(
          programmes: {Programme.familyPlanning},
        ),
        isFalse,
      );
      expect(
        VisitSummaryDetails.shouldAddGenericFollowUpFallback(
          programmes: {Programme.anc, Programme.familyPlanning},
        ),
        isTrue,
      );
    });

    test('skips generic follow-up fallback on PW-only visits', () {
      expect(
        VisitSummaryDetails.shouldAddGenericFollowUpFallback(
          programmes: {Programme.pw},
        ),
        isFalse,
      );
      expect(
        VisitSummaryDetails.shouldAddGenericFollowUpFallback(
          programmes: {Programme.pw, Programme.anc},
        ),
        isTrue,
      );
    });

    test('skips generic follow-up fallback on eye-care-only visits', () {
      expect(
        VisitSummaryDetails.shouldAddGenericFollowUpFallback(
          programmes: {Programme.eyeCare},
        ),
        isFalse,
      );
    });

    test('skips generic follow-up fallback on cataract-only visits', () {
      expect(
        VisitSummaryDetails.shouldAddGenericFollowUpFallback(
          programmes: {Programme.cataract},
        ),
        isFalse,
      );
    });

    test('filters eye care and cataract follow-up rows', () {
      const items = [
        NabaFollowUpItem(
          activity: 'Return',
          timeline: 'In 4 weeks',
          programme: 'EYE_CARE',
        ),
        NabaFollowUpItem(
          activity: 'Camp review',
          timeline: 'In 5 days',
          programme: 'CATARACT',
        ),
      ];
      expect(VisitSummaryDetails.followUpItemsForSummary(items), isEmpty);
    });

    test('eye-care-only visit drops untagged NABA follow-up rows', () {
      const items = [
        NabaFollowUpItem(
          activity: 'Routine review',
          timeline: 'In 4 weeks',
        ),
      ];
      expect(
        VisitSummaryDetails.followUpItemsForSummary(
          items,
          programmes: {Programme.eyeCare},
          primaryProgramme: Programme.eyeCare,
        ),
        isEmpty,
      );
      expect(
        VisitSummaryDetails.followUpItemsForSummary(
          items,
          assessmentTypes: const ['EYE_CARE'],
        ),
        isEmpty,
      );
    });

    test('resolveStep3FollowUpDate eye-care-only is always null', () {
      expect(
        VisitSummaryDetails.resolveStep3FollowUpDate(
          programmes: {Programme.eyeCare},
          isReferred: true,
          programmeDefault: DateTime.utc(2026, 9, 1),
        ),
        isNull,
      );
    });

    test('resolveStep3FollowUpDate cataract-only when not referred', () {
      expect(
        VisitSummaryDetails.resolveStep3FollowUpDate(
          programmes: {Programme.cataract},
          isReferred: false,
          programmeDefault: DateTime.utc(2026, 9, 1),
        ),
        isNull,
      );
    });

    test('resolveStep3FollowUpDate cataract-only when referred uses default',
        () {
      final defaultDate = DateTime.utc(2026, 9, 6);
      expect(
        VisitSummaryDetails.resolveStep3FollowUpDate(
          programmes: {Programme.cataract},
          primaryProgramme: Programme.cataract,
          isReferred: true,
          programmeDefault: defaultDate,
        ),
        defaultDate,
      );
    });

    test('PO-only visit hides Step 3 follow-up (Spice PO summary parity)', () {
      const poOnly = ['PREGNANCY_OUTCOME'];
      expect(
        VisitSummaryDetails.shouldScheduleStep3FollowUp(
          programmes: {Programme.anc},
          isReferred: false,
          assessmentTypes: poOnly,
        ),
        isFalse,
      );
      expect(
        VisitSummaryDetails.followUpItemsForSummary(
          const [
            NabaFollowUpItem(
              activity: 'ANC visit',
              timeline: 'In 4 weeks',
              programme: 'ANC',
            ),
          ],
          programmes: {Programme.anc},
          assessmentTypes: poOnly,
        ),
        isEmpty,
      );
      expect(
        VisitSummaryDetails.resolveStep3FollowUpDate(
          programmes: {Programme.anc},
          isReferred: false,
          programmeDefault: DateTime.utc(2026, 9, 1),
          assessmentTypes: poOnly,
        ),
        isNull,
      );
    });

    test('PO+PNC keeps PNC follow-up and drops ANC rows', () {
      const poPnc = ['PREGNANCY_OUTCOME', 'PNC_MOTHER'];
      expect(
        VisitSummaryDetails.shouldScheduleStep3FollowUp(
          programmes: {Programme.anc, Programme.pnc},
          isReferred: false,
          assessmentTypes: poPnc,
        ),
        isTrue,
      );
      final filtered = VisitSummaryDetails.followUpItemsForSummary(
        const [
          NabaFollowUpItem(
            activity: 'ANC visit',
            timeline: 'In 4 weeks',
            programme: 'ANC',
          ),
          NabaFollowUpItem(
            activity: 'PNC visit',
            timeline: 'In 7 days',
            programme: 'PNC',
          ),
        ],
        programmes: {Programme.anc, Programme.pnc},
        assessmentTypes: poPnc,
      );
      expect(filtered, hasLength(1));
      expect(filtered.first.programme, 'PNC');
    });
  });
}
