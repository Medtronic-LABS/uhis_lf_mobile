import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/assessment_history_item.dart';

void main() {
  group('AssessmentHistoryItem.fromJson', () {
    test('parses a populated DTO row', () {
      final item = AssessmentHistoryItem.fromJson({
        'householdMemberId': 'm-1',
        'encounterId': '499120',
        'visitDate': 1717200000000,
        'serviceProvided': 'NCD',
        'referralStatus': 'REFERRED',
        'referralReason': 'Hypertension',
        'nextFollowUpDate': 1717800000000,
        'isLatestVisit': true,
        'customStatus': ['HIGH_RISK', 'FOLLOW_UP_DUE'],
      });

      expect(item, isNotNull);
      expect(item!.householdMemberId, 'm-1');
      expect(item.encounterId, '499120');
      expect(item.serviceProvided, 'NCD');
      expect(item.referralStatus, 'REFERRED');
      expect(item.isLatestVisit, isTrue);
      expect(item.customStatus, ['HIGH_RISK', 'FOLLOW_UP_DUE']);
      expect(item.nextFollowUpDate, isNotNull);
    });

    test('returns null when memberId or encounterId is missing', () {
      expect(
        AssessmentHistoryItem.fromJson({
          'encounterId': '1',
          'visitDate': 1717200000000,
        }),
        isNull,
      );
      expect(
        AssessmentHistoryItem.fromJson({
          'householdMemberId': 'm-1',
          'visitDate': 1717200000000,
        }),
        isNull,
      );
    });

    test('returns null when visitDate is unparseable', () {
      expect(
        AssessmentHistoryItem.fromJson({
          'householdMemberId': 'm-1',
          'encounterId': '1',
          'visitDate': 'never',
        }),
        isNull,
      );
    });

    test('accepts an ISO string visitDate', () {
      final item = AssessmentHistoryItem.fromJson({
        'householdMemberId': 'm-1',
        'encounterId': '1',
        'visitDate': '2026-04-01T10:00:00Z',
      });
      expect(item, isNotNull);
      expect(item!.visitDate.toUtc().year, 2026);
    });
  });
}
