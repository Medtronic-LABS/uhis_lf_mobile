import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/mission/latest_service_badge.dart';
import 'package:uhis_next/core/mission/programme_reason.dart';
import 'package:uhis_next/core/models/programme.dart';

void main() {
  group('badgeFromLatestServiceKind', () {
    test('PO → Pregnancy Outcome', () {
      final b = badgeFromLatestServiceKind('PREGNANCY_OUTCOME');
      expect(b.reason, MissionDashboardStrings.pregnancyOutcomeBadge);
      expect(b.badgeProgramme, Programme.pnc);
    });

    test('PW → pregnancy registered', () {
      final b = badgeFromLatestServiceKind('PWPROFILE');
      expect(b.reason, PatientProfileStrings.pregnancyRegistered);
      expect(b.badgeProgramme, Programme.pw);
    });

    test('ANC → visit N due from count', () {
      final b = badgeFromLatestServiceKind('ANC', ancVisitCount: 2);
      expect(b.reason, contains('3'));
      expect(b.reason, contains(MissionDashboardStrings.ancVisitLabel));
      expect(b.badgeProgramme, Programme.anc);
    });

    test('PNC mother → visit N due', () {
      final b = badgeFromLatestServiceKind('PNC_MOTHER', pncVisitCount: 0);
      expect(b.reason, contains('1'));
      expect(b.badgeProgramme, Programme.pnc);
    });

    test('all NCD kinds → NCD checkup', () {
      for (final kind in ['NCD', 'NCD_MEDICAL_REVIEW', 'ENROLLMENT']) {
        final b = badgeFromLatestServiceKind(kind);
        expect(b.reason, MissionDashboardStrings.ncdCheckup, reason: kind);
      }
    });

    test('FP → Family Planning', () {
      final b = badgeFromLatestServiceKind('FAMILY_PLANNING');
      expect(b.reason, ProgrammeLabels.of(Programme.familyPlanning));
    });

    test('childhood → child immunisation', () {
      final b = badgeFromLatestServiceKind('CHILDHOOD_VISIT');
      expect(b.reason, MissionDashboardStrings.childImmunisation);
    });
  });

  group('patientBadgeLabel strict latest', () {
    test('latest PW beats enrolled ANC on programme set', () {
      final label = patientBadgeLabel(
        latestServiceKind: 'PWPROFILE',
        programmes: {Programme.anc, Programme.pw},
      );
      expect(label.reason, PatientProfileStrings.pregnancyRegistered);
    });

    test('no latest falls back to enrolled', () {
      final label = patientBadgeLabel(
        programmes: {Programme.ncd},
      );
      expect(label.reason, MissionDashboardStrings.enrolled);
    });

    test('PO latest does not show ANC due even if ANC enrolled', () {
      final label = patientBadgeLabel(
        latestServiceKind: 'PREGNANCYOUTCOME',
        programmes: {Programme.anc, Programme.pnc},
        ancVisitCount: 4,
      );
      expect(label.reason, MissionDashboardStrings.pregnancyOutcomeBadge);
    });
  });

  group('pickLatestServiceKind', () {
    test('prefers newer local', () {
      expect(
        pickLatestServiceKind(
          syncedKind: 'NCD',
          syncedAtMs: 100,
          localKind: 'ANC',
          localAtMs: 200,
        ),
        'ANC',
      );
    });
  });
}
