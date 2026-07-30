import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/risk/clinical_vitals_from_history.dart';

void main() {
  group('ClinicalVitalsFromHistory', () {
    test('extracts hemoglobin from observations', () {
      final vitals = ClinicalVitalsFromHistory.fromRawJson(jsonEncode({
        'serviceProvided': 'ANC',
        'observations': {'ancVisitNumber': 1, 'weight': 45, 'hemoglobin': 7},
      }));
      expect(vitals, isNotNull);
      expect(vitals!.hemoglobin, 7.0);
      expect(vitals.assessmentType, 'ANC');
    });

    test('maps gravida 1 to primigravida parity 0', () {
      final vitals = ClinicalVitalsFromHistory.fromRawJson(jsonEncode({
        'serviceProvided': 'PWPROFILE',
        'observations': {'gravida': 1},
      }));
      expect(vitals, isNotNull);
      expect(vitals!.parity, 0);
    });

    test('parses slash BP string', () {
      final vitals = ClinicalVitalsFromHistory.fromRawJson(jsonEncode({
        'serviceProvided': 'NCD',
        'observations': {'bp': '165/100'},
      }));
      expect(vitals, isNotNull);
      expect(vitals!.systolicBp, 165);
      expect(vitals.diastolicBp, 100);
    });

    test('merge prefers primary non-null and fills gaps from fallback', () {
      final primary = ClinicalVitalsFromHistory.fromMap({
        'observations': {'hemoglobin': 7},
      });
      final fallback = ClinicalVitalsFromHistory.fromMap({
        'observations': {'gravida': 1, 'systolic': 140, 'diastolic': 90},
      });
      final merged = ClinicalVitalsFromHistory.merge(primary, fallback)!;
      expect(merged.hemoglobin, 7.0);
      expect(merged.parity, 0);
      expect(merged.systolicBp, 140);
    });
  });
}
