import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/member_assessment_history_dao.dart';
import 'package:uhis_next/core/db/pregnancy_detail_rebuilder.dart';

MemberAssessmentHistoryRow _history({
  required String service,
  required String visitDate,
  required int id,
  required Map<String, dynamic> observations,
}) {
  return MemberAssessmentHistoryRow(
    id: id,
    memberId: 10,
    visitDate: visitDate,
    serviceProvided: service,
    observationsJson: jsonEncode(observations),
  );
}

void main() {
  test('rebuild folds one episode pw profile then anc then outcome', () {
    const episodeId = 'episode-1';
    final history = [
      _history(
        service: 'pwProfile',
        visitDate: '2026-01-01T00:00:00+00:00',
        id: 1,
        observations: {
          'pregnancyEpisodeId': episodeId,
          'lastMenstrualPeriod': '2025-12-01',
          'estimatedDeliveryDate': '2026-09-01',
          'gravida': '1',
          'parity': '0',
        },
      ),
      _history(
        service: 'anc',
        visitDate: '2026-02-01T00:00:00+00:00',
        id: 2,
        observations: {
          'pregnancyEpisodeId': episodeId,
          'gapsInAnc': '[]',
        },
      ),
      _history(
        service: 'anc',
        visitDate: '2026-03-01T00:00:00+00:00',
        id: 3,
        observations: {
          'pregnancyEpisodeId': episodeId,
          'gapsInAnc': '["lateBooking"]',
        },
      ),
      _history(
        service: 'pregnancyOutcome',
        visitDate: '2026-09-05T00:00:00+00:00',
        id: 4,
        observations: {
          'pregnancyEpisodeId': episodeId,
          'dateOfDelivery': '2026-09-05',
        },
      ),
    ];

    final details = PregnancyDetailRebuilder.rebuildMotherEpisodes(
      householdMemberLocalId: 10,
      householdMemberFhirId: 'fhir-10',
      history: history,
    );

    expect(details, hasLength(1));
    final detail = details.single;
    expect(detail.pregnancyEpisodeId, episodeId);
    expect(detail.lastMenstrualPeriod, '2025-12-01');
    expect(detail.ancVisitNo, 2);
    expect(detail.gapsInAnc, '["lateBooking"]');
    expect(detail.dateOfDelivery, '2026-09-05');
  });
}
