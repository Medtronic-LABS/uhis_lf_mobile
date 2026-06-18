import 'package:flutter/foundation.dart';

import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/fhir_observation.dart';
import '../patient/vitals_repository.dart';

/// Reads `Observation` resources from the HAPI FHIR server for a given
/// `Encounter`.
///
/// Engineering Design Standards mandate FHIR R4 as the *only* contract that
/// crosses service boundaries — this repository is the single seam between
/// the encounter-detail UI and the FHIR server. Callers receive
/// strongly-typed [FhirObservation] / [VitalReading] objects; raw JSON never
/// escapes the repository.
class ObservationRepository extends ApiRepository {
  ObservationRepository(super.api);

  /// Fetch every observation linked to the given FHIR `Encounter` id.
  ///
  /// Strips a leading `Encounter/` prefix so callers can pass either the
  /// bare id (`499120`) or the typed reference (`Encounter/499120`).
  Future<FhirObservationBundle> forEncounter(String encounterId) async {
    final bareId = _stripEncounterPrefix(encounterId);
    if (bareId.isEmpty) {
      return const FhirObservationBundle(observations: []);
    }

    try {
      final body = await getOk(
        Endpoints.fhirObservationByEncounter(bareId),
        action: 'Observations by encounter',
      );
      if (body is! Map) {
        return const FhirObservationBundle(observations: []);
      }
      return FhirObservationBundle.fromJson(Map<String, dynamic>.from(body));
    } catch (e) {
      debugPrint(
        '[ObservationRepository] forEncounter($bareId) failed: $e',
      );
      return const FhirObservationBundle(observations: []);
    }
  }

  /// Convenience: fetch observations for [encounterId] and map them onto the
  /// existing [VitalReading] type so the recent-vitals row and any vitals
  /// chart can render without two parallel models for the same data.
  Future<List<VitalReading>> vitalsForEncounter(String encounterId) async {
    final bundle = await forEncounter(encounterId);
    final out = <VitalReading>[];
    for (final obs in bundle.observations) {
      out.addAll(_mapObservationToVitals(obs));
    }
    return out;
  }

  /// Maps a single FHIR Observation to one or more [VitalReading] rows.
  /// LOINC + UCUM only — see [LoincVitalCodes] for the binding table.
  /// Returned as a list because blood-pressure-panel observations resolve
  /// into a single reading carrying both systolic and diastolic.
  List<VitalReading> _mapObservationToVitals(FhirObservation obs) {
    if (obs.system != LoincVitalCodes.loincSystem) {
      return const [];
    }
    final date = obs.effectiveDateTime ?? DateTime.now();

    switch (obs.code) {
      case LoincVitalCodes.bloodPressurePanel:
        double? sys;
        double? dia;
        String? unit;
        for (final c in obs.components) {
          if (c.system != LoincVitalCodes.loincSystem) continue;
          if (c.code == LoincVitalCodes.systolic) {
            sys = c.valueQuantity;
            unit ??= c.valueUnit;
          } else if (c.code == LoincVitalCodes.diastolic) {
            dia = c.valueQuantity;
            unit ??= c.valueUnit;
          }
        }
        if (sys == null && dia == null) return const [];
        return [
          VitalReading(
            type: VitalType.bloodPressure,
            date: date,
            systolic: sys,
            diastolic: dia,
            unit: unit ?? 'mmHg',
            rawJson: obs.rawJson,
          )
        ];
      case LoincVitalCodes.bodyHeight:
        return _single(obs, VitalType.height, date, defaultUnit: 'cm');
      case LoincVitalCodes.bodyWeight:
        return _single(obs, VitalType.weight, date, defaultUnit: 'kg');
      case LoincVitalCodes.bmi:
        return _single(obs, VitalType.bmi, date);
      case LoincVitalCodes.temperature:
        return _single(obs, VitalType.temperature, date, defaultUnit: '°C');
      case LoincVitalCodes.respiratoryRate:
        return _single(obs, VitalType.respiratoryRate, date,
            defaultUnit: '/min');
      case LoincVitalCodes.oxygenSaturation:
        return _single(obs, VitalType.spO2, date, defaultUnit: '%');
      case LoincVitalCodes.bloodGlucose:
        return _single(obs, VitalType.glucose, date, defaultUnit: 'mg/dL');
      case LoincVitalCodes.muac:
        return _single(obs, VitalType.muac, date, defaultUnit: 'cm');
      default:
        return const [];
    }
  }

  List<VitalReading> _single(
    FhirObservation obs,
    VitalType type,
    DateTime date, {
    String? defaultUnit,
  }) {
    final value = obs.valueQuantity;
    if (value == null) return const [];
    return [
      VitalReading(
        type: type,
        date: date,
        value: value,
        unit: obs.valueUnit ?? defaultUnit,
        rawJson: obs.rawJson,
      )
    ];
  }

  static String _stripEncounterPrefix(String id) {
    const prefix = 'Encounter/';
    if (id.startsWith(prefix)) return id.substring(prefix.length);
    return id;
  }
}
