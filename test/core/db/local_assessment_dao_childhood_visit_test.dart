import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';

void main() {
  test('CHILDHOOD_VISIT wraps assessmentDetails under pncChild with no cbs key',
      () {
    final entity = LocalAssessmentEntity(
      id: 'a1',
      householdMemberLocalId: 1,
      patientId: 'p1',
      assessmentType: 'CHILDHOOD_VISIT',
      assessmentDetails: jsonEncode({
        'weight': 6.5,
        'childBreastFeeding': 'yes',
        'childFeedLast24Hrs': ['mothersBreastMilk', 'familyFood'],
      }),
    );

    final request = entity.toApiRequest(provenance: null);

    // toApiRequest sends Android's wire type, not the Flutter-side constant.
    expect(request['assessmentType'], 'ChildHood_Visit');
    expect(request['assessmentDetails'], {
      'pncChild': {
        'weight': 6.5,
        'childBreastFeeding': 'yes',
        'childFeedLast24Hrs': ['mothersBreastMilk', 'familyFood'],
      },
    });
    expect(
      (request['assessmentDetails'] as Map)['cbs'],
      isNull,
      reason: 'Android never sends a cbs sibling for a childhood visit',
    );
  });

  test('CHILDHOOD_VISIT re-entrant call (already wrapped) is not double-wrapped',
      () {
    final entity = LocalAssessmentEntity(
      id: 'a2',
      householdMemberLocalId: 1,
      patientId: 'p1',
      assessmentType: 'CHILDHOOD_VISIT',
      assessmentDetails: jsonEncode({
        'pncChild': {'weight': 6.5},
      }),
    );

    final request = entity.toApiRequest(provenance: null);

    expect(request['assessmentDetails'], {
      'pncChild': {'weight': 6.5},
    });
  });

  test('CHILD_MENU alias also wraps under pncChild with no cbs key', () {
    final entity = LocalAssessmentEntity(
      id: 'a3',
      householdMemberLocalId: 1,
      patientId: 'p1',
      assessmentType: 'CHILD_MENU',
      assessmentDetails: jsonEncode({'weight': 5.0}),
    );

    final request = entity.toApiRequest(provenance: null);

    expect(request['assessmentDetails'], {'pncChild': {'weight': 5.0}});
  });
}
