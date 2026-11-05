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
    String daysAgo(int days) => DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);

    test('falls back to the PWPROFILE LMP entered on this visit', () {
      expect(
        resolveNabaGestationalWeeks(
          assessments: [
            NabaReferralAssessment(
              assessmentType: 'PWPROFILE',
              referralInputs: {'lmp': daysAgo(10 * 7 + 2)},
            ),
          ],
        ),
        10,
      );
    });

    test('ANC weeks win over the PWPROFILE LMP', () {
      expect(
        resolveNabaGestationalWeeks(
          assessments: [
            NabaReferralAssessment(
              assessmentType: 'PWPROFILE',
              referralInputs: {'lmp': daysAgo(10 * 7)},
            ),
            const NabaReferralAssessment(
              assessmentType: 'ANC',
              referralInputs: {'gestationalWeeks': 12},
            ),
          ],
        ),
        12,
      );
    });

    test('ignores a future or implausibly old PWPROFILE LMP', () {
      for (final lmp in [daysAgo(-3), daysAgo(46 * 7)]) {
        expect(
          resolveNabaGestationalWeeks(
            assessments: [
              NabaReferralAssessment(
                assessmentType: 'PWPROFILE',
                referralInputs: {'lmp': lmp},
              ),
            ],
          ),
          isNull,
          reason: 'lmp=$lmp',
        );
      }
    });
  });
}
