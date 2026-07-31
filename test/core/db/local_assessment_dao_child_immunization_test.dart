import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';

void main() {
  test('CHILD_IMMUNIZATION wraps assessmentDetails under childImmunization',
      () {
    final entity = LocalAssessmentEntity(
      id: 'a1',
      householdMemberLocalId: 1,
      patientId: 'p1',
      assessmentType: 'CHILD_IMMUNIZATION',
      assessmentDetails: jsonEncode({
        'vaccinations': [
          {
            'vaccineName': 'BCG',
            'vaccinatedDate': '2026-01-15T00:00:00+00:00',
            'status': 'Vaccinated',
          },
        ],
      }),
    );

    final request = entity.toApiRequest(provenance: null);

    expect(request['assessmentType'], 'CHILD_IMMUNIZATION');
    expect(request['assessmentDetails'], {
      'childImmunization': {
        'vaccinations': [
          {
            'vaccineName': 'BCG',
            'vaccinatedDate': '2026-01-15T00:00:00+00:00',
            'status': 'Vaccinated',
          },
        ],
      },
    });
  });

  test('otherDetails.referralFacilityType round-trips into wire summary key',
      () {
    final entity = LocalAssessmentEntity(
      id: 'a2',
      householdMemberLocalId: 1,
      patientId: 'p1',
      assessmentType: 'CHILD_IMMUNIZATION',
      assessmentDetails: jsonEncode({
        'vaccinations': [
          {'vaccineName': 'OPV-1', 'status': 'Missed', 'reason': 'Sick'},
        ],
      }),
      otherDetails: jsonEncode({'referralFacilityType': 'governmentHospital'}),
      isReferred: true,
      referralStatus: 'Referred',
      referredReasons: jsonEncode(['Government Hospital']),
    );

    final request = entity.toApiRequest(provenance: null);

    expect(request['summary'], {'referralFacilityType': 'governmentHospital'});
    expect(request['patientStatus'], 'Referred');
    expect(request['encounter']['referred'], true);
    expect(request['referredReasons'], 'Government Hospital');
  });
}
