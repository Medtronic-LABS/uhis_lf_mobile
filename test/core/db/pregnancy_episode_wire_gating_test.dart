/// Regression test for the pregnancyEpisodeId wire-gating fix — three call
/// sites (local_assessment_dao.dart, assessment_repository.dart,
/// unified_form_notifier.dart) used to each maintain their own ad hoc list of
/// "does this assessment type carry a pregnancyEpisodeId", and all three
/// disagreed with each other and with Android's actual 5-type list
/// (OfflineSyncRepository.getPregnancyEpisodeId). This locks in the shared
/// kPregnancyEpisodeLinkedTypes constant both at the source and at the
/// wire-emission boundary.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/db/pregnancy_episode_dao.dart';

void main() {
  group('kPregnancyEpisodeLinkedTypes', () {
    test('matches Android OfflineSyncRepository.getPregnancyEpisodeId exactly',
        () {
      expect(kPregnancyEpisodeLinkedTypes, {
        'PWPROFILE', 'PW_PROFILE',
        'PREGNANCY_OUTCOME', 'PREGNANCYOUTCOME',
        'ANC',
        'PNC_MOTHER', 'PNC',
        'CHILDHOOD_VISIT', 'CHILD_MENU',
      });
    });

    test('does not include neonate/child PNC — Android never links those',
        () {
      expect(kPregnancyEpisodeLinkedTypes, isNot(contains('PNC_NEONATE')));
      expect(kPregnancyEpisodeLinkedTypes, isNot(contains('PNC_CHILD')));
      expect(kPregnancyEpisodeLinkedTypes, isNot(contains('PNC_NEONATAL')));
    });
  });

  group('LocalAssessmentEntity.toApiRequest — pregnancyEpisodeId gating', () {
    LocalAssessmentEntity entity(String type, {String? episodeId}) =>
        LocalAssessmentEntity(
          id: 'a1',
          householdMemberLocalId: 1,
          patientId: 'p1',
          assessmentType: type,
          assessmentDetails: jsonEncode({'weight': 5.0}),
          pregnancyEpisodeId: episodeId,
        );

    test('CHILDHOOD_VISIT carries pregnancyEpisodeId (Android links it)', () {
      final request =
          entity('CHILDHOOD_VISIT', episodeId: 'ep-1').toApiRequest(provenance: null);
      expect(
        (request['encounter'] as Map)['pregnancyEpisodeId'],
        'ep-1',
      );
    });

    test('PNC_NEONATE does NOT carry pregnancyEpisodeId (Android never sends it)',
        () {
      final request =
          entity('PNC_NEONATE', episodeId: 'ep-1').toApiRequest(provenance: null);
      expect(
        (request['encounter'] as Map).containsKey('pregnancyEpisodeId'),
        isFalse,
      );
    });

    test('PNC_CHILD does NOT carry pregnancyEpisodeId', () {
      final request =
          entity('PNC_CHILD', episodeId: 'ep-1').toApiRequest(provenance: null);
      expect(
        (request['encounter'] as Map).containsKey('pregnancyEpisodeId'),
        isFalse,
      );
    });

    test('ANC carries pregnancyEpisodeId', () {
      final request =
          entity('ANC', episodeId: 'ep-1').toApiRequest(provenance: null);
      expect((request['encounter'] as Map)['pregnancyEpisodeId'], 'ep-1');
    });
  });
}
