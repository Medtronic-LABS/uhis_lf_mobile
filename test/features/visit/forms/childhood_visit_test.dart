import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/childhood_visit.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_payload_mapper.dart';

void main() {
  group('ChildhoodVisit', () {
    test('age bands match Spice exclusive if/else', () {
      expect(ChildhoodVisit.fieldVisible('hrsBreastFed', 0), isTrue);
      expect(ChildhoodVisit.fieldVisible('hrsBreastFed', 3), isTrue);
      expect(ChildhoodVisit.fieldVisible('hrsBreastFed', 4), isFalse);

      expect(ChildhoodVisit.fieldVisible('monthAdditionalFeedGiven', 7), isTrue);
      expect(ChildhoodVisit.fieldVisible('monthAdditionalFeedGiven', 11), isTrue);
      expect(ChildhoodVisit.fieldVisible('monthAdditionalFeedGiven', 6), isFalse);
      expect(ChildhoodVisit.fieldVisible('monthAdditionalFeedGiven', 12), isFalse);

      expect(ChildhoodVisit.fieldVisible('childBreastFeeding', 12), isTrue);
      expect(ChildhoodVisit.fieldVisible('receivedVaccine', 18), isFalse);
      expect(ChildhoodVisit.fieldVisible('receivedVaccine', 19), isTrue);
      expect(ChildhoodVisit.fieldVisible('childFeedLast24Hrs', 18), isTrue);
      expect(ChildhoodVisit.fieldVisible('childFeedLast24Hrs', 19), isFalse);
    });

    test('nextVisitDate matches Spice first-match when branches', () {
      final birth = DateTime(2025, 1, 15);
      // age 4 → +5 months (0..4 wins over 4..5)
      final at4 = ChildhoodVisit.nextVisitDate(ageInMonths: 4, birthDate: birth)!;
      expect(at4, DateTime(2025, 6, 15));
      final at5 = ChildhoodVisit.nextVisitDate(ageInMonths: 5, birthDate: birth)!;
      expect(at5, DateTime(2025, 10, 15));
      expect(
        ChildhoodVisit.nextVisitDate(ageInMonths: 16, birthDate: birth),
        isNull,
      );
    });

    test('weight ranges by age', () {
      expect(ChildhoodVisit.weightRangeKg(2), (1.1, 9.0));
      expect(ChildhoodVisit.weightRangeKg(10), (4.0, 15.0));
      expect(ChildhoodVisit.weightRangeKg(20), (6.0, 25.0));
    });

    test('childIllnessType wire ids match UHIS Symptoms entity table', () {
      expect(ChildhoodVisit.allChildIllnessOptionIds, hasLength(14));
      expect(ChildhoodVisit.allChildIllnessOptionIds.first, 'diarrhea');
      expect(ChildhoodVisit.allChildIllnessOptionIds.last, 'other');
    });

    test('childIllnessType age filter matches Spice AssessmentRMNCHFragment', () {
      final infant = ChildhoodVisit.childIllnessOptionIdsForAge(12);
      expect(infant, contains('diarrhea'));
      expect(infant, contains('pneumonia'));
      expect(infant, isNot(contains('cannotStandWalk')));

      final older = ChildhoodVisit.childIllnessOptionIdsForAge(24);
      expect(older, contains('cannotStandWalk'));
      expect(older, isNot(contains('convulsion')));
    });
  });

  group('UnifiedPayloadMapper childhood visit', () {
    test('pncChild emits CHILDHOOD_VISIT with Spice field ids', () {
      final data = CanonicalVisitData({
        'congenitalDefect': 'no',
        'weight': 6.5,
        'childFeedLast24Hrs': ['mothersBreastMilk'],
        'anyIllness': 'no',
      });
      final payloads = UnifiedPayloadMapper.decompose(data, {'pncChild'});
      expect(payloads, hasLength(1));
      expect(payloads.single.assessmentType, 'CHILDHOOD_VISIT');
      expect(payloads.single.details['weight'], 6.5);
      expect(payloads.single.details['congenitalDefect'], 'no');
      expect(payloads.single.details.containsKey('childWeight'), isFalse);
    });

    test('delivery visit does not emit CHILDHOOD_VISIT for seeded pncChild', () {
      final payloads = UnifiedPayloadMapper.decompose(
        const CanonicalVisitData({'deliveryOutcomeType': 'liveBirth'}),
        {'pregnancyOutcome', 'pncMother', 'pncChild'},
      );
      expect(
        payloads.map((p) => p.assessmentType),
        isNot(contains('CHILDHOOD_VISIT')),
      );
      expect(
        payloads.map((p) => p.assessmentType),
        isNot(contains('PNC_NEONATE')),
      );
    });

    test('pncNeonatal still emits PNC_NEONATE', () {
      final payloads = UnifiedPayloadMapper.decompose(
        const CanonicalVisitData({'isChildAlive': 'yes', 'childWeight': 3.2}),
        {'pncNeonatal'},
      );
      expect(payloads.single.assessmentType, 'PNC_NEONATE');
      expect(payloads.single.details['childWeight'], 3.2);
    });

    test('visitNo travels in details and lands on encounter.visitNumber', () {
      final details = UnifiedPayloadMapper.decompose(
        const CanonicalVisitData({
          'childVisitNumber': 3,
          'congenitalDefect': 'no',
        }),
        {'pncChild'},
      ).single.details;
      expect(details['visitNo'], 3);

      final request = LocalAssessmentEntity(
        id: 'c1',
        householdMemberLocalId: 7,
        assessmentType: 'CHILDHOOD_VISIT',
        assessmentDetails: jsonEncode(details),
      ).toApiRequest(provenance: null);

      expect(request['assessmentType'], 'ChildHood_Visit');
      expect(request['assessmentDetails']['pncChild']['visitNo'], 3);
      expect(request['encounter']['visitNumber'], 3);
    });

    test('childhood visit syncs without customStatus (no Spice branch)', () {
      final request = LocalAssessmentEntity(
        id: 'c2',
        householdMemberLocalId: 7,
        assessmentType: 'CHILDHOOD_VISIT',
        assessmentDetails: jsonEncode({'visitNo': 1}),
        isReferred: true,
        referralStatus: 'Referred',
      ).toApiRequest(provenance: null);

      expect(request['encounter'].containsKey('customStatus'), isFalse);
    });
  });

  group('Childhood visit labels', () {
    test('layout leaves labels to field_library (Spice question titles)',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final config = await FormConfig.load(rootBundle);
      final refs = config.forms['pncChild']!
          .expand((s) => s.fieldRefs)
          .toList();

      expect(refs.every((r) => r.fieldName == null), isTrue);
      expect(
        config.fields['hrsBreastFed']!.label,
        'Within how many hours after birth was breastfed?',
      );
      expect(config.fields['anyIllness']!.label, 'Any Illness/Complications');
      expect(
        config.fields['childIllnessType']!.label,
        'If any complication, specify',
      );
    });
  });
}
