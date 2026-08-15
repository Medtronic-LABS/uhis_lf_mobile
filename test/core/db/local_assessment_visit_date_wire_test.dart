import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/follow_up_dao.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/models/provance_dto.dart';

void main() {
  group('toApiRequest visit timestamps — Android createdAt parity', () {
    LocalAssessmentEntity ncd({
      required String id,
      required DateTime createdAt,
      DateTime? updatedAt,
    }) =>
        LocalAssessmentEntity(
          id: id,
          referenceId: id == 'a-t20' ? 1 : 2,
          householdMemberLocalId: 1,
          patientId: 'p1',
          assessmentType: 'NCD',
          assessmentDetails: jsonEncode({
            'ncd': {'symptomsLog': {'hasSymptoms': 'No'}},
          }),
          createdAt: createdAt,
          updatedAt: updatedAt ?? createdAt,
        );

    test('each assessment keeps its own createdAt, not the shared provenance now',
        () {
      final t20 = DateTime.utc(2026, 7, 26, 10, 0, 0);
      final t10 = DateTime.utc(2026, 8, 5, 10, 0, 0);
      final shared = ProvanceDto.fromMap({
        'modifiedDate': DateTime.utc(2026, 8, 15, 12, 0, 0).toIso8601String(),
        'organizationId': '213',
        'spiceUserId': 19,
        'userId': '458534',
      });

      final older = ncd(id: 'a-t20', createdAt: t20).toApiRequest(
        provenance: shared,
      );
      final newer = ncd(id: 'a-t10', createdAt: t10).toApiRequest(
        provenance: shared,
      );

      expect(older['assessmentDate'], toOfflineOffsetDateTime(t20));
      expect(newer['assessmentDate'], toOfflineOffsetDateTime(t10));
      expect(older['updatedAt'], t20.millisecondsSinceEpoch);
      expect(newer['updatedAt'], t10.millisecondsSinceEpoch);

      final olderEnc = older['encounter'] as Map<String, dynamic>;
      final newerEnc = newer['encounter'] as Map<String, dynamic>;
      expect(
        (olderEnc['provenance'] as Map)['modifiedDate'],
        toOfflineOffsetDateTime(t20),
      );
      expect(
        (newerEnc['provenance'] as Map)['modifiedDate'],
        toOfflineOffsetDateTime(t10),
      );
      expect(olderEnc['startTime'], toOfflineOffsetDateTime(t20));
      expect(newerEnc['startTime'], toOfflineOffsetDateTime(t10));
      expect(olderEnc['endTime'], toOfflineOffsetDateTime(t20));
      expect(newerEnc['endTime'], toOfflineOffsetDateTime(t10));
    });

    test('sync-time updatedAt does not replace the visit date', () {
      final visit = DateTime.utc(2026, 7, 26, 10, 0, 0);
      final syncStamp = DateTime.utc(2026, 8, 15, 12, 0, 0);
      final request = ncd(
        id: 'a-t20',
        createdAt: visit,
        updatedAt: syncStamp,
      ).toApiRequest(
        provenance: ProvanceDto.fromMap({
          'modifiedDate': syncStamp.toIso8601String(),
          'organizationId': '213',
          'spiceUserId': 19,
        }),
      );

      expect(request['updatedAt'], visit.millisecondsSinceEpoch);
      expect(
        request['assessmentDate'],
        toOfflineOffsetDateTime(visit),
      );
      expect(
        (request['encounter'] as Map)['provenance']['modifiedDate'],
        toOfflineOffsetDateTime(visit),
      );
    });
  });
}
