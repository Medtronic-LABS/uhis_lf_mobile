import 'package:flutter_test/flutter_test.dart';
import 'package:leapwell/core/clinical/briefing_rules/clinical_vitals_history_adapter.dart';
import 'package:leapwell/core/db/assessment_dao.dart';
import 'package:leapwell/core/models/risk.dart';

void main() {
  group('vitalsHistoryFor', () {
    test('matches kind case-insensitively and as a substring (PNC vs PNC_MOTHER)', () {
      final rows = [
        AssessmentRow(id: '1', patientId: 'p1', kind: 'PNC_MOTHER', occurredAt: 2000, rawJson: '{"hemoglobin": 9.0}'),
        AssessmentRow(id: '2', patientId: 'p1', kind: 'ncd', occurredAt: 1000, rawJson: '{"systolic": 150}'),
      ];
      final pnc = vitalsHistoryFor(rows, 'PNC');
      expect(pnc, hasLength(1));
      expect(pnc.first.hemoglobin, 9.0);

      final ncd = vitalsHistoryFor(rows, 'NCD');
      expect(ncd, hasLength(1));
      expect(ncd.first.systolicBp, 150);
    });

    test('returns at most 2 entries, newest-first as given', () {
      final rows = [
        AssessmentRow(id: '1', patientId: 'p1', kind: 'ANC', occurredAt: 3000, rawJson: '{"systolic": 140}'),
        AssessmentRow(id: '2', patientId: 'p1', kind: 'ANC', occurredAt: 2000, rawJson: '{"systolic": 130}'),
        AssessmentRow(id: '3', patientId: 'p1', kind: 'ANC', occurredAt: 1000, rawJson: '{"systolic": 120}'),
      ];
      final vitals = vitalsHistoryFor(rows, 'ANC');
      expect(vitals, hasLength(2));
      expect(vitals[0].systolicBp, 140);
      expect(vitals[1].systolicBp, 130);
    });

    test('skips rows that fail to parse into any recognisable clinical field', () {
      final rows = [
        AssessmentRow(id: '1', patientId: 'p1', kind: 'ANC', occurredAt: 2000, rawJson: 'not json'),
        AssessmentRow(id: '2', patientId: 'p1', kind: 'ANC', occurredAt: 1000, rawJson: '{"systolic": 130}'),
      ];
      final vitals = vitalsHistoryFor(rows, 'ANC');
      expect(vitals, hasLength(1));
      expect(vitals.first.systolicBp, 130);
    });

    test('no matching kind → empty', () {
      final rows = [
        AssessmentRow(id: '1', patientId: 'p1', kind: 'NCD', occurredAt: 1000, rawJson: '{"systolic": 150}'),
      ];
      expect(vitalsHistoryFor(rows, 'ANC'), isEmpty);
    });
  });

  group('ancMapFromVitals', () {
    test('maps BP and Hb into the expected nested shape', () {
      const vitals = ClinicalVitals(systolicBp: 145, diastolicBp: 92, hemoglobin: 7.5);
      final map = ancMapFromVitals(vitals);
      expect(map['medicalHistoryPhysicalExamination'], {'systolic': 145, 'diastolic': 92});
      expect(map['pointOfCareInvestigations'], {'hemoglobin': 7.5});
    });

    test('omits sections entirely when the underlying value is null', () {
      const vitals = ClinicalVitals(systolicBp: 130);
      final map = ancMapFromVitals(vitals);
      expect(map.containsKey('medicalHistoryPhysicalExamination'), isTrue);
      expect(map.containsKey('pointOfCareInvestigations'), isFalse);
      // Never fabricates danger signs or IFA/Calcium data from a boolean flag.
      expect(map.containsKey('dangerSignsRiskIdentification'), isFalse);
      expect(map.containsKey('vaccinationAndSupplements'), isFalse);
    });
  });

  group('pncMapFromVitals', () {
    test('maps BP and Hb; never fabricates temperature/pulse', () {
      const vitals = ClinicalVitals(systolicBp: 150, diastolicBp: 95, hemoglobin: 7.0);
      final map = pncMapFromVitals(vitals);
      final maternal = map['maternalHealthAssessment'] as Map;
      expect(maternal['systolic'], 150);
      expect(maternal['diastolic'], 95);
      expect(maternal['hemoglobin'], 7.0);
      expect(maternal.containsKey('temperature'), isFalse);
      expect(maternal.containsKey('pulse'), isFalse);
    });
  });

  group('ncdMapFromVitals', () {
    test('maps BP into bpLog and fasting glucose into glucoseLog as fbs', () {
      const vitals = ClinicalVitals(systolicBp: 150, diastolicBp: 95, fastingGlucoseMmolL: 8.0);
      final map = ncdMapFromVitals(vitals);
      expect(map['bpLog'], {'avgSystolic': 150, 'avgDiastolic': 95});
      expect(map['glucoseLog'], {'glucoseValue': 8.0, 'glucoseType': 'fbs'});
    });

    test('no glucose reading → glucoseLog omitted, never guesses compliance', () {
      const vitals = ClinicalVitals(systolicBp: 150, diastolicBp: 95);
      final map = ncdMapFromVitals(vitals);
      expect(map.containsKey('glucoseLog'), isFalse);
      expect(map.containsKey('symptomsLog'), isFalse);
    });
  });
}
