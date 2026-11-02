import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/naba/naba_models.dart';

void main() {
  group('resolveNabaIsPregnant', () {
    test('true when ANC is in activeProgrammes', () {
      expect(resolveNabaIsPregnant(['NCD', 'ANC']), isTrue);
      expect(resolveNabaIsPregnant(['anc']), isTrue);
    });

    test('false when ANC is absent', () {
      expect(resolveNabaIsPregnant(['NCD', 'PNC']), isFalse);
    });
  });

  group('resolveNabaGestationalWeeks', () {
    test('prefers visit-level weeks', () {
      expect(
        resolveNabaGestationalWeeks(
          visitGestationalWeeks: 24,
          assessments: const [
            NabaReferralAssessment(
              assessmentType: 'ANC',
              referralInputs: {'gestationalWeeks': 20},
            ),
          ],
        ),
        24,
      );
    });

    test('falls back to ANC assessment referralInputs', () {
      expect(
        resolveNabaGestationalWeeks(
          assessments: const [
            NabaReferralAssessment(
              assessmentType: 'ANC',
              referralInputs: {'gestationalWeeks': 18},
            ),
          ],
        ),
        18,
      );
    });
  });
}
