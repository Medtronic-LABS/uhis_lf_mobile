import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/assessment_dao.dart';
import 'package:uhis_next/features/household/member_assessment_lookup.dart';

void main() {
  group('memberAssessmentLookupKeys', () {
    test('includes local id, fhir id, and patient id', () {
      expect(
        memberAssessmentLookupKeys(
          id: '279',
          fhirId: '823260',
          patientId: '999',
        ),
        containsAll(['279', '823260', '999']),
      );
    });
  });

  group('combinedVisitCount', () {
    test('adds synced and pending local counts across lookup keys', () {
      expect(
        combinedVisitCount(
          lookupKeys: const ['279', '823260'],
          syncedCounts: const {'823260': 1},
          localPendingCounts: const {'279': 1},
        ),
        2,
      );
    });

    test('uses highest per-key count when history is keyed by FHIR id', () {
      expect(
        combinedVisitCount(
          lookupKeys: const ['279', '823260'],
          syncedCounts: const {'823260': 1},
          localPendingCounts: const {},
        ),
        1,
      );
    });

    test('counts pending local visit before sync populates assessments table',
        () {
      expect(
        combinedVisitCount(
          lookupKeys: const ['279'],
          syncedCounts: const {},
          localPendingCounts: const {'279': 1},
        ),
        1,
      );
    });
  });

  group('resolveRecentServiceKind', () {
    test('prefers synced row keyed by local member id', () {
      final synced = {
        '279': [
          AssessmentRow(
            id: 'a1',
            patientId: '279',
            kind: 'FAMILY_PLANNING',
            occurredAt: 1000,
            rawJson: '{}',
          ),
        ],
      };
      expect(
        resolveRecentServiceKind(
          lookupKeys: const ['279', '823260'],
          syncedByKey: synced,
          localLatestByPatientId: const {},
        ),
        'FAMILY_PLANNING',
      );
    });

    test('prefers newer local assessment over older synced row', () {
      final synced = {
        '279': [
          AssessmentRow(
            id: 'a1',
            patientId: '279',
            kind: 'NCD',
            occurredAt: 1000,
            rawJson: '{}',
          ),
        ],
      };
      expect(
        resolveRecentServiceKind(
          lookupKeys: const ['279'],
          syncedByKey: synced,
          localLatestByPatientId: {
            '279': (type: 'EYE_CARE', at: 2000),
          },
        ),
        'EYE_CARE',
      );
    });
  });
}
