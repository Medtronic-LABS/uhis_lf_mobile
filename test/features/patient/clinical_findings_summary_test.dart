import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/briefing_rules/clinical_finding.dart';
import 'package:uhis_next/features/patient/patient_context_screen.dart';

void main() {
  group('clinicalFindingsSummary', () {
    test('empty list → empty string (triggers the unavailable-message fallback)', () {
      expect(clinicalFindingsSummary(const []), '');
    });

    test('single finding → that finding\'s message verbatim', () {
      final result = clinicalFindingsSummary(const [
        ClinicalFinding(code: 'anc.severeAnaemia', message: 'Severe anemia.', programme: 'anc'),
      ]);
      expect(result, 'Severe anemia.');
    });

    test('multiple findings → space-joined, in order, no extra punctuation added', () {
      final result = clinicalFindingsSummary(const [
        ClinicalFinding(
          code: 'anc.highBp',
          message: 'BP is above the safe threshold. Watch for pre-eclampsia.',
          programme: 'anc',
        ),
        ClinicalFinding(
          code: 'anc.severeAnaemia',
          message: 'Severe anemia.',
          programme: 'anc',
        ),
        ClinicalFinding(
          code: 'anc.supplementGap',
          message: 'Iron-folic intake is below the expected daily rate.',
          programme: 'anc',
        ),
      ]);
      expect(
        result,
        'BP is above the safe threshold. Watch for pre-eclampsia. Severe anemia. '
        'Iron-folic intake is below the expected daily rate.',
      );
    });
  });
}
