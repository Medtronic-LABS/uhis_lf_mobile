import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/fhir_observation.dart';

Map<String, dynamic> _bp(String systolic, String diastolic) => {
      'resourceType': 'Observation',
      'id': 'bp-1',
      'status': 'final',
      'code': {
        'coding': [
          {
            'system': 'http://loinc.org',
            'code': LoincVitalCodes.bloodPressurePanel,
            'display': 'Blood pressure panel',
          }
        ]
      },
      'effectiveDateTime': '2026-05-01T09:30:00Z',
      'component': [
        {
          'code': {
            'coding': [
              {
                'system': 'http://loinc.org',
                'code': LoincVitalCodes.systolic,
              }
            ]
          },
          'valueQuantity': {'value': systolic, 'unit': 'mmHg'},
        },
        {
          'code': {
            'coding': [
              {
                'system': 'http://loinc.org',
                'code': LoincVitalCodes.diastolic,
              }
            ]
          },
          'valueQuantity': {'value': diastolic, 'unit': 'mmHg'},
        },
      ],
    };

Map<String, dynamic> _weight(num kg) => {
      'resourceType': 'Observation',
      'id': 'w-1',
      'code': {
        'coding': [
          {
            'system': 'http://loinc.org',
            'code': LoincVitalCodes.bodyWeight,
          }
        ]
      },
      'effectiveDateTime': '2026-05-01T09:30:00Z',
      'valueQuantity': {'value': kg, 'unit': 'kg'},
    };

void main() {
  group('FhirObservation', () {
    test('parses a body-weight observation with a numeric quantity', () {
      final obs = FhirObservation.fromJson(_weight(58.5));
      expect(obs, isNotNull);
      expect(obs!.code, LoincVitalCodes.bodyWeight);
      expect(obs.valueQuantity, 58.5);
      expect(obs.valueUnit, 'kg');
      expect(obs.components, isEmpty);
    });

    test('parses a BP panel into two components', () {
      final obs = FhirObservation.fromJson(_bp('120', '80'));
      expect(obs, isNotNull);
      expect(obs!.code, LoincVitalCodes.bloodPressurePanel);
      expect(obs.components.length, 2);
      expect(
        obs.components.firstWhere((c) => c.code == LoincVitalCodes.systolic).valueQuantity,
        120,
      );
      expect(
        obs.components.firstWhere((c) => c.code == LoincVitalCodes.diastolic).valueQuantity,
        80,
      );
    });

    test('returns null for resources that are not Observations', () {
      expect(
        FhirObservation.fromJson({'resourceType': 'Patient', 'id': 'p-1'}),
        isNull,
      );
    });
  });

  group('FhirObservationBundle', () {
    test('extracts Observation resources from a HAPI Bundle entry list', () {
      final bundle = FhirObservationBundle.fromJson({
        'resourceType': 'Bundle',
        'total': 2,
        'entry': [
          {'resource': _weight(60)},
          {'resource': _bp('118', '76')},
          {'resource': {'resourceType': 'Patient', 'id': 'p'}},
        ],
      });
      expect(bundle.observations.length, 2);
      expect(bundle.total, 2);
    });
  });
}
