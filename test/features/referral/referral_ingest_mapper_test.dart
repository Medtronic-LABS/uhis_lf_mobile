import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/follow_up_dao.dart';
import 'package:uhis_next/core/models/assessment_history_item.dart';
import 'package:uhis_next/core/models/referral.dart';
import 'package:uhis_next/core/referral/referral_ingest_mapper.dart';

void main() {
  group('ReferralIngestMapper.fromFollowUp', () {
    test('maps REFERRED follow-up with reason and site', () {
      final row = FollowUpRow(
        id: 'fu-1',
        patientId: 'pat-1',
        kind: FollowUpKind.generic,
        type: 'REFERRED',
        referredSiteId: '13',
        dueAt: 1_700_000_000_000,
        rawJson: jsonEncode({
          'referralReason': 'bloodPressure, bloodGlucose',
          'referralStatus': 'Referred',
        }),
      );

      final referral = ReferralIngestMapper.fromFollowUp(
        row,
        householdId: 'hh-1',
        villageId: '143',
      );

      expect(referral, isNotNull);
      expect(referral!.id, 'ref-fu-fu-1');
      expect(referral.patientId, 'pat-1');
      expect(referral.householdId, 'hh-1');
      expect(referral.villageId, '143');
      expect(referral.state, ReferralStatus.created);
      expect(referral.slaTier, SlaTier.urgent);
      expect(referral.diagnosisLabel, 'bloodPressure, bloodGlucose');
    });

    test('skips Recovered follow-up', () {
      final row = FollowUpRow(
        id: 'fu-2',
        patientId: 'pat-1',
        kind: FollowUpKind.generic,
        type: 'REFERRED',
        rawJson: jsonEncode({'referralStatus': 'Recovered'}),
      );

      expect(ReferralIngestMapper.fromFollowUp(row), isNull);
    });

    test('skips non-referral follow-up', () {
      final row = FollowUpRow(
        id: 'fu-3',
        patientId: 'pat-1',
        kind: FollowUpKind.generic,
        type: 'SCREENED',
        rawJson: '{}',
      );

      expect(ReferralIngestMapper.fromFollowUp(row), isNull);
    });
  });

  group('ReferralIngestMapper.fromAssessmentHistory', () {
    test('maps Referred history row (NCD payload shape)', () {
      final item = AssessmentHistoryItem(
        householdMemberId: '505314',
        encounterId: 'enc-99',
        visitDate: DateTime.utc(2026, 7, 20, 18, 37),
        serviceProvided: 'NCD',
        referralStatus: 'Referred',
        referralReason: 'bloodPressure, bloodGlucose',
        customStatus: const ['Referred'],
        rawJson: const {
          'patientStatus': 'Referred',
          'referredReasons': 'bloodPressure, bloodGlucose',
        },
      );

      final referral = ReferralIngestMapper.fromAssessmentHistory(
        item,
        patientId: '0390444751531',
      );

      expect(referral, isNotNull);
      expect(referral!.id, 'ref-hist-enc-99');
      expect(referral.patientId, '0390444751531');
      expect(referral.state, ReferralStatus.created);
      expect(referral.slaTier, SlaTier.urgent);
      expect(referral.diagnosisLabel, 'bloodPressure, bloodGlucose');
      expect(referral.diagnosisCode, 'NCD');
    });

    test('maps when only customStatus carries Referred', () {
      final item = AssessmentHistoryItem(
        householdMemberId: 'm1',
        encounterId: 'enc-1',
        visitDate: DateTime.utc(2026, 7, 20),
        customStatus: const ['Referred'],
        rawJson: const {},
      );

      final referral = ReferralIngestMapper.fromAssessmentHistory(
        item,
        patientId: 'p1',
      );

      expect(referral, isNotNull);
      expect(referral!.state, ReferralStatus.created);
    });

    test('skips Recovered history', () {
      final item = AssessmentHistoryItem(
        householdMemberId: 'm1',
        encounterId: 'enc-2',
        visitDate: DateTime.utc(2026, 7, 20),
        referralStatus: 'Recovered',
        rawJson: const {},
      );

      expect(
        ReferralIngestMapper.fromAssessmentHistory(item, patientId: 'p1'),
        isNull,
      );
    });
  });

  group('ReferralIngestMapper.fromLocalAssessment', () {
    test('builds deterministic local id and urgent tier for BP/glucose', () {
      final referral = ReferralIngestMapper.fromLocalAssessment(
        assessmentId: 'local-abc',
        patientId: 'pat-1',
        reasons: const ['bloodPressure', 'bloodGlucose'],
        facilityName: '13',
        householdId: 'hh-1',
        villageId: '143',
        diagnosisCode: 'NCD',
        now: DateTime.utc(2026, 7, 20, 18, 37),
      );

      expect(referral.id, 'ref-assess-local-abc');
      expect(referral.state, ReferralStatus.created);
      expect(referral.slaTier, SlaTier.urgent);
      expect(referral.diagnosisLabel, 'bloodPressure, bloodGlucose');
    });
  });

  group('SlaTier.inferFromReason', () {
    test('treats NCD reason codes as urgent', () {
      expect(SlaTier.inferFromReason('bloodPressure'), SlaTier.urgent);
      expect(SlaTier.inferFromReason('bloodGlucose'), SlaTier.urgent);
    });

    test('treats stroke as emergency', () {
      expect(SlaTier.inferFromReason('stroke'), SlaTier.emergency);
    });
  });
}
