import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/triage/patient_context_builder.dart';
import 'package:uhis_next/features/visit/triage/triage_view_model.dart';
import 'package:uhis_next/features/visit/triage/unified_symptom_catalog.dart';

void main() {
  group('TriageViewModel Pre-Tick Scenarios', () {
    // Step 1 is now AI-driven (spec — symptoms populated dynamically from the
    // AI Scribe response). The patient-context auto-pre-tick has been removed:
    // the chip list starts empty and only the AI / SK fills it. These tests
    // pin the new contract — no symptom is selected at construction time.

    test('Known Hypertension → does NOT pre-tick high_bp_known', () {
      final ctx = PatientContext(
        patientId: 'test-1',
        ageMonths: 480, // 40 years
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {'HTN'},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);

      expect(vm.isPreTicked('high_bp_known'), isFalse);
      expect(vm.isSelected('high_bp_known'), isFalse);
      expect(vm.selectedSymptoms, isEmpty);
    });

    test('Known Diabetes → does NOT pre-tick polyuria / polydipsia', () {
      final ctx = PatientContext(
        patientId: 'test-2',
        ageMonths: 600, // 50 years
        sex: Sex.male,
        isPregnant: false,
        knownConditions: {'DM'},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);

      expect(vm.isSelected('polyuria'), isFalse);
      expect(vm.isSelected('polydipsia'), isFalse);
      expect(vm.selectedSymptoms, isEmpty);
    });

    test('Pregnant → does NOT pre-tick pregnant', () {
      final ctx = PatientContext(
        patientId: 'test-3',
        ageMonths: 300, // 25 years
        sex: Sex.female,
        isPregnant: true,
        knownConditions: {},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);

      expect(vm.isPreTicked('pregnant'), isFalse);
      expect(vm.isSelected('pregnant'), isFalse);
    });

    test('ANC enrolled → does NOT pre-tick pregnant', () {
      final ctx = PatientContext(
        patientId: 'test-4',
        ageMonths: 336, // 28 years
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {Programme.anc},
      );

      final vm = TriageViewModel(patientContext: ctx);

      expect(vm.isPreTicked('pregnant'), isFalse);
    });

    test('NCD enrolled + HTN → does NOT pre-tick high_bp_known', () {
      final ctx = PatientContext(
        patientId: 'test-5',
        ageMonths: 540, // 45 years
        sex: Sex.male,
        isPregnant: false,
        knownConditions: {'HTN'},
        activeProgrammes: {Programme.ncd},
      );

      final vm = TriageViewModel(patientContext: ctx);

      expect(vm.isPreTicked('high_bp_known'), isFalse);
    });

    test('TB screen due → does NOT pre-tick but expands cluster', () {
      final ctx = PatientContext(
        patientId: 'test-6',
        ageMonths: 360, // 30 years
        sex: Sex.male,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
        openFlags: {'TB_SCREEN_DUE'},
      );

      final vm = TriageViewModel(patientContext: ctx);

      // No TB symptoms pre-ticked
      expect(vm.isPreTicked('cough_over_2_weeks'), isFalse);
      expect(vm.isPreTicked('weight_loss'), isFalse);

      // But cluster should be expanded
      expect(vm.preExpandedClusters.contains(SymptomCluster.tbIndicators), isTrue);
    });

    test('Under 5 child → expands child health clusters', () {
      final ctx = PatientContext(
        patientId: 'test-7',
        ageMonths: 36, // 3 years
        sex: Sex.male,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);

      expect(vm.preExpandedClusters.contains(SymptomCluster.childHealth), isTrue);
      expect(vm.preExpandedClusters.contains(SymptomCluster.feverRespiratory), isTrue);
      expect(vm.preExpandedClusters.contains(SymptomCluster.giNutrition), isTrue);
    });

    test('Postpartum → expands maternal cluster', () {
      // Set delivery date to 3 weeks ago (within 6-week PNC window)
      final threeWeeksAgo = DateTime.now().subtract(const Duration(days: 21));
      final ctx = PatientContext(
        patientId: 'test-8',
        ageMonths: 300, // 25 years
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
        deliveryDateMillis: threeWeeksAgo.millisecondsSinceEpoch,
      );

      final vm = TriageViewModel(patientContext: ctx);

      expect(vm.preExpandedClusters.contains(SymptomCluster.maternal), isTrue);
    });
  });

  group('TriageViewModel Runtime Scenarios', () {
    late TriageViewModel vm;

    setUp(() {
      final ctx = PatientContext(
        patientId: 'test-runtime',
        ageMonths: 360, // 30 years
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
      );
      vm = TriageViewModel(patientContext: ctx);
    });

    test('Toggle symptom on → adds to selection', () {
      expect(vm.isSelected('fever'), isFalse);

      vm.toggleSymptom('fever');

      expect(vm.isSelected('fever'), isTrue);
    });

    test('Toggle symptom off → removes from selection', () {
      vm.toggleSymptom('fever');
      expect(vm.isSelected('fever'), isTrue);

      vm.toggleSymptom('fever');

      expect(vm.isSelected('fever'), isFalse);
    });

    test('Bulk select → adds multiple symptoms', () {
      vm.selectSymptoms({'fever', 'cough', 'vomiting'});

      expect(vm.isSelected('fever'), isTrue);
      expect(vm.isSelected('cough'), isTrue);
      expect(vm.isSelected('vomiting'), isTrue);
    });

    test('Clear all → empties selection and pathways', () {
      vm.selectSymptoms({'fever', 'cough'});
      expect(vm.selectedSymptoms.isNotEmpty, isTrue);

      vm.clearAll();

      expect(vm.selectedSymptoms.isEmpty, isTrue);
      expect(vm.activatedPathways.isEmpty, isTrue);
    });

    test('Routine visit → clears symptoms, keeps history triggers', () {
      vm.selectSymptoms({'fever'});

      vm.setRoutineVisit();

      expect(vm.selectedSymptoms.isEmpty, isTrue);
      expect(vm.isRoutineVisit, isTrue);
    });

    test('Danger sign detected → hasDangerSign is true', () {
      expect(vm.hasDangerSign, isFalse);

      // Select a danger sign (convulsions is in the catalog)
      vm.toggleSymptom('convulsions');

      expect(vm.hasDangerSign, isTrue);
    });
  });

  group('TriageViewModel Pathway Activation Scenarios', () {
    test('Pregnant + high BP → ANC + NCD pathways', () {
      final ctx = PatientContext(
        patientId: 'test-path-1',
        ageMonths: 300,
        sex: Sex.female,
        isPregnant: true,
        knownConditions: {},
        activeProgrammes: {},
        lastBpSystolic: 150,
        lastBpDiastolic: 95,
      );

      final vm = TriageViewModel(patientContext: ctx);
      vm.toggleSymptom('high_bp');

      final programmes = vm.activatedPathways.map((p) => p.programme).toSet();
      expect(programmes.contains(Programme.anc), isTrue);
      expect(programmes.contains(Programme.ncd), isTrue);
    });

    test('TB symptoms → TB pathway', () {
      final ctx = PatientContext(
        patientId: 'test-path-2',
        ageMonths: 408, // 34 years
        sex: Sex.male,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);
      vm.selectSymptoms({'cough_over_2_weeks', 'weight_loss', 'fever'});

      final programmes = vm.activatedPathways.map((p) => p.programme).toSet();
      expect(programmes.contains(Programme.tb), isTrue);
    });

    test('Child with MUAC red → IMCI pathway', () {
      final ctx = PatientContext(
        patientId: 'test-path-3',
        ageMonths: 30,
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
        openFlags: {'MR_OVERDUE'},
      );

      final vm = TriageViewModel(patientContext: ctx);
      vm.toggleSymptom('muac_red');

      final programmes = vm.activatedPathways.map((p) => p.programme).toSet();
      expect(programmes.contains(Programme.imci), isTrue);
    });

    test('Neonate with fever → IMCI pathway (neonates use IMCI)', () {
      final ctx = PatientContext(
        patientId: 'test-path-4',
        ageMonths: 1, // 6 weeks ~ 1.5 months
        sex: Sex.male,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);
      vm.toggleSymptom('fever');

      // Pathways will be activated
      expect(vm.activatedPathways.isNotEmpty, isTrue);
    });

    test('No symptoms, pregnant enrolled → ANC from history', () {
      final ctx = PatientContext(
        patientId: 'test-path-5',
        ageMonths: 300,
        sex: Sex.female,
        isPregnant: true,
        knownConditions: {},
        activeProgrammes: {Programme.anc},
      );

      final vm = TriageViewModel(patientContext: ctx);
      // Clear the pre-tick
      vm.clearAll();
      vm.setRoutineVisit();

      // History trigger should still activate ANC
      final programmes = vm.activatedPathways.map((p) => p.programme).toSet();
      expect(programmes.contains(Programme.anc), isTrue);
    });

    test('No symptoms, no history → empty pathways (routine visit)', () {
      final ctx = PatientContext(
        patientId: 'test-path-6',
        ageMonths: 300,
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);

      expect(vm.activatedPathways.isEmpty, isTrue);
      expect(vm.isRoutineVisit, isTrue);
    });

    test('Postpartum + headache → PNC pathway', () {
      // Set delivery date to 3 weeks ago (within 6-week PNC window)
      final threeWeeksAgo = DateTime.now().subtract(const Duration(days: 21));
      final ctx = PatientContext(
        patientId: 'test-path-7',
        ageMonths: 336, // 28 years
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
        deliveryDateMillis: threeWeeksAgo.millisecondsSinceEpoch,
      );

      final vm = TriageViewModel(patientContext: ctx);
      vm.toggleSymptom('headache');

      final programmes = vm.activatedPathways.map((p) => p.programme).toSet();
      expect(programmes.contains(Programme.pnc), isTrue);
    });

    test('Known HTN, no symptoms → NCD from history trigger', () {
      final ctx = PatientContext(
        patientId: 'test-path-8',
        ageMonths: 540, // 45 years
        sex: Sex.male,
        isPregnant: false,
        knownConditions: {'HTN'},
        activeProgrammes: {Programme.ncd},
      );

      final vm = TriageViewModel(patientContext: ctx);
      // high_bp_known is pre-ticked, clear it
      vm.clearAll();
      vm.setRoutineVisit();

      // History trigger should still activate NCD
      final programmes = vm.activatedPathways.map((p) => p.programme).toSet();
      expect(programmes.contains(Programme.ncd), isTrue);
    });
  });

  group('TriageViewModel Cluster Display', () {
    test('Danger signs cluster always expanded', () {
      final ctx = PatientContext(
        patientId: 'test-cluster-1',
        ageMonths: 360,
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);

      expect(vm.preExpandedClusters.contains(SymptomCluster.dangerSigns), isTrue);
    });

    test('symptomsByCluster returns all clusters with symptoms', () {
      final ctx = PatientContext(
        patientId: 'test-cluster-2',
        ageMonths: 360,
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);
      final clusters = vm.symptomsByCluster;

      expect(clusters.isNotEmpty, isTrue);
      expect(clusters.containsKey(SymptomCluster.dangerSigns), isTrue);
      expect(clusters[SymptomCluster.dangerSigns]!.isNotEmpty, isTrue);
    });
  });

  group('TriageViewModel Notifier', () {
    test('toggleSymptom notifies listeners', () {
      final ctx = PatientContext(
        patientId: 'test-notify-1',
        ageMonths: 360,
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);
      var notified = false;
      vm.addListener(() => notified = true);

      vm.toggleSymptom('fever');

      expect(notified, isTrue);
    });

    test('clearAll notifies listeners', () {
      final ctx = PatientContext(
        patientId: 'test-notify-2',
        ageMonths: 360,
        sex: Sex.female,
        isPregnant: false,
        knownConditions: {},
        activeProgrammes: {},
      );

      final vm = TriageViewModel(patientContext: ctx);
      vm.toggleSymptom('fever');
      
      var notified = false;
      vm.addListener(() => notified = true);

      vm.clearAll();

      expect(notified, isTrue);
    });
  });
}
