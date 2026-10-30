/// NABA `assessments[]` construction from Step 2 form state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

import '../../../helpers/fake_form_deps.dart';

void main() {
  group('buildNabaReferralAssessmentsForTesting', () {
    test('pregnancy outcome visit emits PREGNANCYOUTCOME assessment type', () {
      final notifier = buildTestNotifier(
        draftDao: FakeAssessmentDraftDao(),
        activeFormTypes: const ['pregnancyOutcome'],
      );
      notifier.updateField('deliveryOutcomeType', 'liveBirth');
      notifier.updateField('deliveryOutcome', 'liveBirth');
      notifier.updateField('liveBirthNumbers', 1);
      notifier.updateField('dateOfDelivery', '2026-01-15');

      final assessments = notifier.buildNabaReferralAssessmentsForTesting(
        isNcdFollowUp: false,
      );

      expect(
        assessments.map((a) => a.assessmentType),
        contains('PREGNANCYOUTCOME'),
      );
      final po = assessments.firstWhere(
        (a) => a.assessmentType == 'PREGNANCYOUTCOME',
      );
      expect(
        po.referralInputs['deliveryOutcomes'],
        isA<Map<String, dynamic>>(),
      );
      final delivery = po.referralInputs['deliveryOutcomes'] as Map;
      expect(delivery['deliveryOutcome'], 'liveBirth');
    });

    test('delivery visit with mother PNC includes both PO and PNC_MOTHER', () {
      final notifier = buildTestNotifier(
        draftDao: FakeAssessmentDraftDao(),
        activeFormTypes: const ['pregnancyOutcome', 'pncMother'],
      );
      notifier.updateField('deliveryOutcomeType', 'liveBirth');

      final assessments = notifier.buildNabaReferralAssessmentsForTesting(
        isNcdFollowUp: false,
      );

      expect(
        assessments.map((a) => a.assessmentType),
        containsAll(['PREGNANCYOUTCOME', 'PNC_MOTHER']),
      );
    });
  });
}
