import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

/// Locks the exact English wording of the CCE derivation copy that moved out of
/// the deleted private `_CceCopy` class into [CceStrings], and pins the
/// reject-reason key/label split.
///
/// [AppLocale.current] defaults to [AppLanguage.bangla], so English is set
/// explicitly rather than relying on the fallback path in `flutter test`.
void main() {
  late AppLanguage previousLanguage;

  setUp(() {
    previousLanguage = AppLocale.current;
    AppLocale.current = AppLanguage.english;
  });

  tearDown(() => AppLocale.current = previousLanguage);

  group('CceStrings — migrated derivation constants', () {
    test('identity and badge copy', () {
      expect(CceStrings.unknownPatient, 'Patient');
      expect(CceStrings.referralReasonFallback, 'Referral');
      expect(CceStrings.attentionBadge, 'Needs attention');
      expect(CceStrings.onTrackBadge, 'On track');
      expect(CceStrings.completedBadge, 'Completed');
    });

    test('SLA window fallbacks', () {
      expect(CceStrings.slaEmergencyWindow, '6 hours');
      expect(CceStrings.slaUrgentWindow, '24 hours');
      expect(CceStrings.slaRoutineWindow, '72 hours');
    });

    test('journey step labels and sublabels', () {
      expect(CceStrings.stepSkVisit, 'SK Visit');
      expect(CceStrings.stepReferred, 'Referred');
      expect(CceStrings.stepFacility, 'Facility');
      expect(CceStrings.stepArrived, 'Arrived');
      expect(CceStrings.stepNotArrived, 'Not arrived');
      expect(CceStrings.stepPending, 'Pending');
      expect(CceStrings.stepTreatment, 'Treatment');
      expect(CceStrings.stepTreated, 'Treated');
      expect(CceStrings.stepInProgress, 'In progress');
      expect(CceStrings.stepDischarged, 'Discharged');
    });

    test('intel tags', () {
      expect(CceStrings.tagCareComplete, 'Care completed');
      expect(CceStrings.tagAtFacility, 'At facility');
      expect(CceStrings.tagNotCheckedIn, 'Not checked in');
      expect(CceStrings.tagTransportBarrier, 'Transport barrier?');
    });

    test('status lines use an em dash (U+2014)', () {
      expect(CceStrings.actionRecommended, 'Action recommended');
      expect(CceStrings.atFacilityOnTrack, 'At facility — care in progress');
      expect(CceStrings.onTrackLine, 'On track — no action needed');
    });
  });

  group('CceStrings — migrated derivation templates', () {
    test('breachBadge takes a formatted duration string, not a count', () {
      expect(CceStrings.breachBadge('4d'), 'SLA BREACHED +4d');
      expect(CceStrings.breachBadge('45m'), 'SLA BREACHED +45m');
    });

    test('leftBadge', () {
      expect(CceStrings.leftBadge('3h'), 'SLA: 3h left');
    });

    test('referredMeta includes the facility when it is non-empty', () {
      expect(
        CceStrings.referredMeta('13 May', 'UHC Manikganj', 'Severe pneumonia'),
        'Referred: 13 May · UHC Manikganj · Severe pneumonia',
      );
    });

    test('referredMeta drops the facility when null or blank', () {
      expect(
        CceStrings.referredMeta('13 May', null, 'Severe pneumonia'),
        'Referred: 13 May · Severe pneumonia',
      );
      expect(
        CceStrings.referredMeta('13 May', '', 'Severe pneumonia'),
        'Referred: 13 May · Severe pneumonia',
      );
    });

    test('overdue and waiting status lines', () {
      expect(
        CceStrings.notArrivedOverdue('7 days', '3 days'),
        'Not arrived · 7 days overdue · SLA was 3 days',
      );
      expect(
        CceStrings.treatmentOverdue('3 days'),
        'Treatment overdue · SLA was 3 days',
      );
      expect(
        CceStrings.awaitingReview('5 hours'),
        'Checked in — awaiting review · 5 hours waiting',
      );
      expect(CceStrings.dueSoon('6 hours'), 'Due in 6 hours · act soon');
    });

    test('closure status lines', () {
      expect(
        CceStrings.dischargedLine('27 May'),
        'Discharged 27 May · care complete',
      );
      expect(CceStrings.closedDeceased('27 May'), 'Closed 27 May · deceased');
    });

    test('tagEscalated interpolates the numeric level', () {
      expect(CceStrings.tagEscalated(2), 'Escalated L2');
    });
  });

  group('CceStrings — follow-up call copy', () {
    test('wrongNumberClosed uses a middle dot (U+00B7)', () {
      expect(CceStrings.wrongNumberClosed, 'Wrong number · closed');
    });

    test('callAttemptsStatus takes three ints', () {
      expect(
        CceStrings.callAttemptsStatus(2, 3, 1),
        '2 of 3 calls · 1 left',
      );
    });

    test('single-word tags', () {
      expect(CceStrings.lastAttempt, 'Last attempt');
      expect(CceStrings.followingUp, 'Following up');
    });
  });

  group('CceStrings — reject-reason key/label split', () {
    // WIRE CONTRACT: the keys are the current English display strings, so the
    // value written to `follow_up_calls.reason` and pushed to the server stays
    // byte-identical to the pre-migration behaviour.
    const expectedKeys = <String>[
      'Treatment from other facility',
      'No Medicine',
      'Long Distance',
      'Transportation and unsupplied medicine cost',
      'Long waiting queue',
      'Migrated to other places',
      'Died',
      'Other',
    ];

    test('keys match the deleted _rejectReasons list, in chip order', () {
      expect(CceStrings.rejectReasonKeys, hasLength(8));
      expect(CceStrings.rejectReasonKeys, expectedKeys);
      expect(
        CceStrings.rejectReasonKeys.first,
        'Treatment from other facility',
      );
      expect(CceStrings.rejectReasonKeys.last, 'Other');
    });

    test('the Other key is a constant, and is one of the keys', () {
      expect(CceStrings.rejectReasonOtherKey, 'Other');
      expect(
        CceStrings.rejectReasonKeys,
        contains(CceStrings.rejectReasonOtherKey),
      );
    });

    test('labels render the English key verbatim', () {
      expect(CceStrings.rejectReasonLabel('Other'), 'Other');
      expect(CceStrings.rejectReasonLabel('Long Distance'), 'Long Distance');
      expect(
        CceStrings.rejectReasonLabel(
          'Transportation and unsupplied medicine cost',
        ),
        'Transportation and unsupplied medicine cost',
      );
    });

    test('every key resolves to a non-empty label', () {
      for (final key in CceStrings.rejectReasonKeys) {
        expect(CceStrings.rejectReasonLabel(key), isNotEmpty);
      }
    });

    test('an unrecognised key passes through unchanged', () {
      expect(CceStrings.rejectReasonLabel('not-a-key'), 'not-a-key');
    });
  });
}
