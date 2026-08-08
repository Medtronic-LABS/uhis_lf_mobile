import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/core/mission/programme_reason.dart';
import 'package:uhis_next/core/models/programme.dart';

void main() {
  setUp(() {
    AppLocale.current = AppLanguage.english;
  });

  tearDown(() {
    AppLocale.current = AppLanguage.bangla;
  });

  group('MissionDashboardStrings.driverInsight', () {
    test('sla-breached', () {
      expect(MissionDashboardStrings.driverInsight('sla-breached'),
          'SLA breached — immediate action required.');
    });

    test('child-under-5', () {
      expect(MissionDashboardStrings.driverInsight('child-under-5'),
          'Child under 5 — higher priority.');
    });

    test('pregnancy', () {
      expect(MissionDashboardStrings.driverInsight('pregnancy'), 'High-risk pregnancy.');
    });

    test('urgent-risk', () {
      expect(MissionDashboardStrings.driverInsight('urgent-risk'),
          'Urgent clinical risk identified.');
    });

    test('high-risk', () {
      expect(MissionDashboardStrings.driverInsight('high-risk'), 'High clinical risk.');
    });

    test('overdue with days=3', () {
      expect(MissionDashboardStrings.driverInsight('overdue', days: '3'), 'Overdue by 3 days.');
    });

    test('overdue with days=1 has no singular form (sic)', () {
      expect(MissionDashboardStrings.driverInsight('overdue', days: '1'), 'Overdue by 1 days.');
    });

    test('overdue with empty days falls back to Visit overdue', () {
      expect(MissionDashboardStrings.driverInsight('overdue', days: ''), 'Visit overdue.');
    });

    test('overdue with no days falls back to Visit overdue', () {
      expect(MissionDashboardStrings.driverInsight('overdue'), 'Visit overdue.');
    });

    test('no-arrival', () {
      expect(MissionDashboardStrings.driverInsight('no-arrival'),
          'Patient never arrived at facility.');
    });

    test('emergency-dx', () {
      expect(MissionDashboardStrings.driverInsight('emergency-dx'), 'Emergency diagnosis.');
    });

    test('missed-follow-up', () {
      expect(MissionDashboardStrings.driverInsight('missed-follow-up'),
          'Missed scheduled follow-up.');
    });

    test('referral', () {
      expect(MissionDashboardStrings.driverInsight('referral'),
          'Active referral requires tracking.');
    });

    test('follow-up', () {
      expect(MissionDashboardStrings.driverInsight('follow-up'), 'Post-discharge follow-up due.');
    });

    test('unknown tag falls back to generic Requires attention', () {
      expect(MissionDashboardStrings.driverInsight('unknown-tag'), 'Requires attention.');
    });

    test('band1-severe has no dedicated sentence, falls back to generic', () {
      expect(MissionDashboardStrings.driverInsight('band1-severe'), 'Requires attention.');
    });
  });

  group('MissionDashboardStrings.driverInsightOrNull — tags that must stay silent', () {
    test('unknown tag returns null', () {
      expect(MissionDashboardStrings.driverInsightOrNull('unknown-tag'), isNull);
    });

    test('band1-severe returns null', () {
      expect(MissionDashboardStrings.driverInsightOrNull('band1-severe'), isNull);
    });

    test('band2-moderate returns null', () {
      expect(MissionDashboardStrings.driverInsightOrNull('band2-moderate'), isNull);
    });

    test('band3-mild returns null', () {
      expect(MissionDashboardStrings.driverInsightOrNull('band3-mild'), isNull);
    });

    test('danger-sign returns null', () {
      expect(MissionDashboardStrings.driverInsightOrNull('danger-sign'), isNull);
    });

    test('stroke-sign returns null', () {
      expect(MissionDashboardStrings.driverInsightOrNull('stroke-sign'), isNull);
    });

    test('eclampsia returns null', () {
      expect(MissionDashboardStrings.driverInsightOrNull('eclampsia'), isNull);
    });

    test('non-null tags still resolve through driverInsightOrNull', () {
      expect(MissionDashboardStrings.driverInsightOrNull('sla-breached'),
          'SLA breached — immediate action required.');
    });
  });

  group('_buildAiInsight envelope sentences', () {
    test('insightScheduledCheckUp — drivers empty', () {
      expect(MissionDashboardStrings.insightScheduledCheckUp, 'Scheduled for regular check-up.');
    });

    test('insightRequiresAttention — no tag matched', () {
      expect(MissionDashboardStrings.insightRequiresAttention, 'Requires attention.');
    });
  });

  group('Other Task 4 wording locks', () {
    test('WorklistStrings.unnamedPatient', () {
      expect(WorklistStrings.unnamedPatient, '(Unnamed patient)');
    });

    test('ReferralStrings.notifSlaBreachTitle', () {
      expect(ReferralStrings.notifSlaBreachTitle, '🔴 SLA breach');
    });

    test('ReferralStrings.notifWarningTitle', () {
      expect(ReferralStrings.notifWarningTitle, '🟠 Referral warning');
    });

    test('ReferralStrings.notifReferralCompletedTitle', () {
      expect(ReferralStrings.notifReferralCompletedTitle, '🟢 Referral completed');
    });

    test('ReferralStrings.notifGenericTitle', () {
      expect(ReferralStrings.notifGenericTitle, 'Referral update');
    });

    test('ReferralStrings.notifDefaultBody', () {
      expect(ReferralStrings.notifDefaultBody, 'Open referral needs your attention.');
    });

    test('ReferralStrings.escalatedToLevel', () {
      expect(ReferralStrings.escalatedToLevel(2), 'Escalated to level 2');
    });

    test('ReferralStrings.bulkClosedBy', () {
      expect(ReferralStrings.bulkClosedBy('sk'), 'Bulk closed by sk');
    });

    test('MissionDashboardStrings.memberFallback', () {
      expect(MissionDashboardStrings.memberFallback, 'Member');
    });

    test('MissionDashboardStrings.checkUpFallback', () {
      expect(MissionDashboardStrings.checkUpFallback, 'Check-up');
    });

    test('MissionDashboardStrings.patientLabel', () {
      expect(MissionDashboardStrings.patientLabel('abc12345'), 'Patient abc12345');
    });

    test('MissionDashboardStrings.referralFallback', () {
      expect(MissionDashboardStrings.referralFallback, 'Referral');
    });

    test('MissionDashboardStrings.followUpDueFallback', () {
      expect(MissionDashboardStrings.followUpDueFallback, 'Follow-up due');
    });

    test('MissionDashboardStrings.riskReferralOverdue', () {
      expect(MissionDashboardStrings.riskReferralOverdue(4), 'Referral overdue by 4 days');
    });

    test('MissionDashboardStrings.riskPatientsWaiting', () {
      expect(MissionDashboardStrings.riskPatientsWaiting(2),
          '2 patient(s) waiting for facility review');
    });

    test('MissionDashboardStrings.riskMissedFollowUps', () {
      expect(MissionDashboardStrings.riskMissedFollowUps(3), '3 patient(s) missed follow-up');
    });

    test('MissionDashboardStrings.dueSuffix', () {
      expect(MissionDashboardStrings.dueSuffix, 'due');
    });

    test('MissionDashboardStrings.dueSuffixTitleCase', () {
      expect(MissionDashboardStrings.dueSuffixTitleCase, 'Due');
    });
  });

  group('programmeReason badge rendering — casing quirk preserved', () {
    test('ANC badge uses lowercase "due"', () {
      expect(
        programmeReason(programmes: {Programme.anc}, ancVisitCount: 2),
        'ANC Visit 3 due',
      );
    });

    test('PNC badge uses title-case "Due" (inconsistent with ANC, preserved as-is)', () {
      expect(
        programmeReason(programmes: {Programme.pnc}, pncVisitCount: 1),
        'PNC Visit 2 Due',
      );
    });
  });
}
