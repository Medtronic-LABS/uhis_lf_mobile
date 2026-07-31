import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/pathway/pathway_engine.dart';
import 'package:uhis_next/features/visit/triage/patient_context_builder.dart';

void main() {
  group('PathwayEngine', () {
    // =========================================================================
    // Golden Case 1: F, pregnant, BP 150/95 entered → {ANC, NCD_HTN}
    // =========================================================================
    test('Golden Case 1: pregnant woman with high BP activates ANC + NCD_HTN', () {
      final ctx = PatientContext(
        patientId: 'test-1',
        ageMonths: 28 * 12, // 28 years
        sex: Sex.female,
        isPregnant: true,
        lastBpSystolic: 150,
        lastBpDiastolic: 95,
      );

      final symptoms = <String>{'high_bp_known'};
      final activated = PathwayEngine.activate(symptoms, ctx);

      // Should have both ANC and NCD
      final programmes = activated.map((a) => a.programme).toSet();
      expect(programmes, contains(Programme.anc), reason: 'Should activate ANC for pregnant woman');
      expect(programmes, contains(Programme.ncd), reason: 'Should activate NCD for high BP');
    });

    // =========================================================================
    // Golden Case 2: M 34y, cough_over_2_weeks + weight_loss + fever → {TB_SCREEN}
    // =========================================================================
    test('Golden Case 2: adult male with TB symptoms activates TB_SCREEN', () {
      final ctx = PatientContext(
        patientId: 'test-2',
        ageMonths: 34 * 12, // 34 years
        sex: Sex.male,
        isPregnant: false,
      );

      final symptoms = <String>{'cough_over_2_weeks', 'weight_loss', 'fever'};
      final activated = PathwayEngine.activate(symptoms, ctx);

      // Should have TB
      final programmes = activated.map((a) => a.programme).toSet();
      expect(programmes, contains(Programme.tb), reason: 'Should activate TB screening');
    });

    // =========================================================================
    // Golden Case 3: 30mo, muac_red, MR vaccine overdue → {ICCM, NUTRITION, EPI}
    // Ordered: acute-first
    // =========================================================================
    test('Golden Case 3: malnourished child with overdue vaccine activates ICCM + EPI', () {
      final ctx = PatientContext(
        patientId: 'test-3',
        ageMonths: 30, // 30 months / 2.5 years
        sex: Sex.male,
        isPregnant: false,
        overdueImmunizations: ['MR'],
      );

      final symptoms = <String>{'muac_red'};
      final activated = PathwayEngine.activate(symptoms, ctx);

      // Should have IMCI (for nutrition and ICCM)
      final programmes = activated.map((a) => a.programme).toSet();
      expect(programmes, contains(Programme.imci), reason: 'Should activate ICCM/Nutrition');

      // Check ordering: acute pathways should come before scheduled (EPI)
      final priorities = activated.map((a) => a.priority).toList();
      for (int i = 1; i < priorities.length; i++) {
        expect(priorities[i], greaterThanOrEqualTo(priorities[i - 1]),
            reason: 'Pathways should be ordered by priority (acute before scheduled)');
      }
    });

    // =========================================================================
    // Golden Case 4: 6wk old, fever → {NEONATE} only — no ICCM
    // =========================================================================
    test('Golden Case 4: neonate with fever activates only NEONATE, not ICCM', () {
      final ctx = PatientContext(
        patientId: 'test-4',
        ageMonths: 1, // 6 weeks ≈ 1.5 months, rounds to 1
        sex: Sex.male,
        isPregnant: false,
      );

      final symptoms = <String>{'fever'};
      final activated = PathwayEngine.activate(symptoms, ctx);

      // Should only have one IMCI pathway (neonate, priority 1)
      final imciPathways = activated.where((a) => a.programme == Programme.imci).toList();
      expect(imciPathways.length, equals(1), reason: 'Should have exactly one IMCI pathway');
      expect(imciPathways.first.priority, equals(1), reason: 'Should be neonate (priority 1), not ICCM');
    });

    // =========================================================================
    // Golden Case 5: no symptoms, pregnancy active → {ANC} (scheduled path)
    // =========================================================================
    test('Golden Case 5: pregnant woman with no symptoms activates ANC', () {
      final ctx = PatientContext(
        patientId: 'test-5',
        ageMonths: 25 * 12, // 25 years
        sex: Sex.female,
        isPregnant: true,
        activeProgrammes: {Programme.anc},
      );

      final symptoms = <String>{}; // No symptoms
      final activated = PathwayEngine.activate(symptoms, ctx);

      // Should have ANC from history trigger
      final programmes = activated.map((a) => a.programme).toSet();
      expect(programmes, contains(Programme.anc), reason: 'Should activate ANC for pregnant woman');
    });

    // =========================================================================
    // Golden Case 6: no symptoms, no history → [] → routine-visit path
    // =========================================================================
    test('Golden Case 6: healthy adult with no symptoms activates nothing', () {
      final ctx = PatientContext(
        patientId: 'test-6',
        ageMonths: 30 * 12, // 30 years
        sex: Sex.male,
        isPregnant: false,
      );

      final symptoms = <String>{}; // No symptoms
      final activated = PathwayEngine.activate(symptoms, ctx);

      // Should be empty (routine visit)
      expect(activated, isEmpty, reason: 'Should have no activated pathways for routine visit');
    });

    // =========================================================================
    // Golden Case 7: F 28y, delivered 3wk ago, headache → {PNC, ...}
    // =========================================================================
    test('Golden Case 7: postpartum woman with headache activates PNC', () {
      // 3 weeks ago
      final deliveryDate = DateTime.now().subtract(const Duration(days: 21));

      final ctx = PatientContext(
        patientId: 'test-7',
        ageMonths: 28 * 12, // 28 years
        sex: Sex.female,
        isPregnant: false,
        deliveryDateMillis: deliveryDate.millisecondsSinceEpoch,
      );

      final symptoms = <String>{'headache_severe'};
      final activated = PathwayEngine.activate(symptoms, ctx);

      // Should have PNC
      final programmes = activated.map((a) => a.programme).toSet();
      expect(programmes, contains(Programme.pnc), reason: 'Should activate PNC for postpartum woman');
    });

    // =========================================================================
    // Golden Case 8: known HTN, no symptoms → {NCD_HTN} via historyTrigger
    // =========================================================================
    test('Golden Case 8: known hypertensive with no symptoms activates NCD', () {
      final ctx = PatientContext(
        patientId: 'test-8',
        ageMonths: 45 * 12, // 45 years
        sex: Sex.male,
        isPregnant: false,
        knownConditions: {'HYPERTENSION'},
        activeProgrammes: {Programme.ncd},
      );

      final symptoms = <String>{}; // No symptoms
      final activated = PathwayEngine.activate(symptoms, ctx);

      // Should have NCD from history trigger
      final programmes = activated.map((a) => a.programme).toSet();
      expect(programmes, contains(Programme.ncd), reason: 'Should activate NCD for known HTN');
    });

    // =========================================================================
    // Additional edge cases
    // =========================================================================
    
    group('Edge cases', () {
      test('Night sweats + weight loss combo activates TB', () {
        final ctx = PatientContext(
          patientId: 'edge-1',
          ageMonths: 40 * 12,
          sex: Sex.male,
          isPregnant: false,
        );

        final symptoms = <String>{'night_sweats', 'weight_loss'};
        final activated = PathwayEngine.activate(symptoms, ctx);

        final programmes = activated.map((a) => a.programme).toSet();
        expect(programmes, contains(Programme.tb), reason: 'Should activate TB from combo');
      });

      test('Polyuria + polydipsia combo activates NCD-DM', () {
        final ctx = PatientContext(
          patientId: 'edge-2',
          ageMonths: 50 * 12,
          sex: Sex.female,
          isPregnant: false,
        );

        final symptoms = <String>{'polyuria', 'polydipsia'};
        final activated = PathwayEngine.activate(symptoms, ctx);

        final programmes = activated.map((a) => a.programme).toSet();
        expect(programmes, contains(Programme.ncd), reason: 'Should activate NCD from DM symptoms');
      });

      test('Child under 2 months does not get ICCM pathway', () {
        final ctx = PatientContext(
          patientId: 'edge-3',
          ageMonths: 1,
          sex: Sex.male,
          isPregnant: false,
        );

        final symptoms = <String>{'cough', 'fever', 'diarrhea'};
        final activated = PathwayEngine.activate(symptoms, ctx);

        // Should only have neonate (priority 1), not ICCM (priority 10)
        for (final pathway in activated) {
          if (pathway.programme == Programme.imci) {
            expect(pathway.priority, lessThan(10),
                reason: 'Neonate should suppress ICCM');
          }
        }
      });

      test('Manual pathway addition works', () {
        final existing = <ActivatedPathway>[
          const ActivatedPathway(
            programme: Programme.imci,
            priority: 10,
            confidence: 1.0,
            trigger: PathwayTrigger.rule,
            rationaleKey: 'test',
          ),
        ];

        final result = PathwayEngine.addManual(existing, Programme.tb);

        expect(result.length, equals(2));
        expect(result.any((a) => a.programme == Programme.tb), isTrue);
        expect(
          result.firstWhere((a) => a.programme == Programme.tb).trigger,
          equals(PathwayTrigger.manual),
        );
      });

      test('Pathway removal works and returns removed pathway', () {
        final existing = <ActivatedPathway>[
          const ActivatedPathway(
            programme: Programme.imci,
            priority: 10,
            confidence: 1.0,
            trigger: PathwayTrigger.rule,
            rationaleKey: 'test',
          ),
          const ActivatedPathway(
            programme: Programme.tb,
            priority: 30,
            confidence: 1.0,
            trigger: PathwayTrigger.rule,
            rationaleKey: 'test',
          ),
        ];

        final (result, removed) = PathwayEngine.remove(existing, Programme.tb);

        expect(result.length, equals(1));
        expect(removed, isNotNull);
        expect(removed!.programme, equals(Programme.tb));
        expect(result.any((a) => a.programme == Programme.tb), isFalse);
      });

      test('Elevated BP from history triggers NCD', () {
        final ctx = PatientContext(
          patientId: 'edge-4',
          ageMonths: 35 * 12,
          sex: Sex.male,
          isPregnant: false,
          lastBpSystolic: 145,
          lastBpDiastolic: 92,
        );

        final symptoms = <String>{}; // No symptoms
        final activated = PathwayEngine.activate(symptoms, ctx);

        final programmes = activated.map((a) => a.programme).toSet();
        expect(programmes, contains(Programme.ncd),
            reason: 'Should activate NCD for elevated BP');
      });

      test('Trigger symptoms are captured for explainability', () {
        final ctx = PatientContext(
          patientId: 'edge-5',
          ageMonths: 3 * 12,
          sex: Sex.male,
          isPregnant: false,
        );

        final symptoms = <String>{'fever', 'cough'};
        final activated = PathwayEngine.activate(symptoms, ctx);

        final iccm = activated.firstWhere((a) => a.programme == Programme.imci);
        expect(iccm.triggerSymptoms, isNotEmpty,
            reason: 'Should capture trigger symptoms');
        expect(iccm.triggerSymptoms, containsAll(['fever', 'cough']),
            reason: 'Should contain the symptoms that triggered');
      });
    });
  });
}
