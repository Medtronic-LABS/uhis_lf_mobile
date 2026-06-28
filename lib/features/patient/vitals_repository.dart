import 'package:flutter/foundation.dart';

import '../../core/api/api_repository.dart';
import '../../core/db/encounter_dao.dart';
import '../visit/observation_repository.dart';

/// Type of vital sign measurement.
enum VitalType {
  bloodPressure,
  glucose,
  weight,
  height,
  temperature,
  respiratoryRate,
  spO2,
  muac,
  bmi,
}

/// A single vital sign reading.
class VitalReading {
  const VitalReading({
    required this.type,
    required this.date,
    this.value,
    this.systolic,
    this.diastolic,
    this.unit,
    this.classification,
    this.rawJson = const {},
  });

  final VitalType type;
  final DateTime date;
  final double? value;
  final double? systolic; // For BP
  final double? diastolic; // For BP
  final String? unit;
  final String? classification; // Normal, High, Low, etc.
  final Map<String, dynamic> rawJson;

  /// Human-readable display value.
  String get displayValue {
    if (type == VitalType.bloodPressure && systolic != null && diastolic != null) {
      return '${systolic!.toInt()}/${diastolic!.toInt()}';
    }
    if (value == null) return '--';
    if (type == VitalType.temperature) {
      return '${value!.toStringAsFixed(1)}°C';
    }
    if (type == VitalType.weight) {
      return '${value!.toStringAsFixed(1)} kg';
    }
    if (type == VitalType.height) {
      return '${value!.toInt()} cm';
    }
    if (type == VitalType.glucose) {
      return '${value!.toStringAsFixed(1)} mg/dL';
    }
    if (type == VitalType.spO2) {
      return '${value!.toInt()}%';
    }
    if (type == VitalType.respiratoryRate) {
      return '${value!.toInt()} /min';
    }
    if (type == VitalType.muac) {
      return '${value!.toStringAsFixed(1)} cm';
    }
    if (type == VitalType.bmi) {
      return value!.toStringAsFixed(1);
    }
    return value!.toString();
  }
}

/// Recent vitals summary for a patient.
class RecentVitals {
  const RecentVitals({
    this.latestBp,
    this.latestGlucose,
    this.latestWeight,
    this.latestTemperature,
    this.latestSpO2,
    this.latestRr,
    this.latestBmi,
    this.allReadings = const [],
  });

  final VitalReading? latestBp;
  final VitalReading? latestGlucose;
  final VitalReading? latestWeight;
  final VitalReading? latestTemperature;
  final VitalReading? latestSpO2;
  final VitalReading? latestRr;
  final VitalReading? latestBmi;
  final List<VitalReading> allReadings;

  bool get isEmpty =>
      latestBp == null &&
      latestGlucose == null &&
      latestWeight == null &&
      latestTemperature == null &&
      latestSpO2 == null &&
      latestRr == null &&
      latestBmi == null;
}

/// Repository for fetching patient vitals history.
///
/// Server-side vitals are sourced exclusively from the FHIR Observation
/// search by encounter (`GET /fhir-server/fhir/Observation?encounter=
/// Encounter/{id}`) via [ObservationRepository]. The legacy spice-service
/// log endpoints (`bplog/list`, `glucoselog/list`) are no longer called.
class VitalsRepository extends ApiRepository {
  VitalsRepository(
    super.api, {
    EncounterDao? encounters,
    ObservationRepository? observations,
  })  : _encounters = encounters,
        _observations = observations;

  final EncounterDao? _encounters;
  final ObservationRepository? _observations;

  /// Strip a FHIR-style `Resource/id` prefix so callers can pass either
  /// `Patient/0390444751474` or `0390444751474` interchangeably. DAOs
  /// store the bare id; remote endpoints accept either.
  static String _bareId(String id) {
    final slash = id.lastIndexOf('/');
    return slash < 0 ? id : id.substring(slash + 1);
  }

  /// Offline-first vital extraction. Reads every cached encounter for the
  /// patient, decodes its `vitals_json` blob, and picks the most recent
  /// non-null value per vital code: BP (systolic+diastolic), pulse,
  /// glucose, height, weight, BMI, temperature, SpO2, respiratory rate.
  /// Returns an empty list when no encounter has been captured yet.
  Future<List<VitalReading>> latestFromLocal(String patientId) async {
    final encDao = _encounters;
    if (encDao == null) return const <VitalReading>[];
    final stripped = _bareId(patientId);
    final out = <VitalReading>[];
    try {
      final rows = await encDao.recentForPatient(stripped, limit: 20);
      for (final row in rows) {
        final m = row.vitalsData;
        if (m == null || m.isEmpty) continue;
        final ts = DateTime.fromMillisecondsSinceEpoch(
            row.completedAt ?? row.startedAt);

        double? asDouble(Object? v) {
          if (v is num) return v.toDouble();
          if (v is String) return double.tryParse(v);
          return null;
        }

        final sys = asDouble(m['systolic'] ?? m['systolicBp']);
        final dia = asDouble(m['diastolic'] ?? m['diastolicBp']);
        if (sys != null && dia != null) {
          out.add(VitalReading(
            type: VitalType.bloodPressure,
            date: ts,
            systolic: sys,
            diastolic: dia,
            unit: 'mmHg',
          ));
        }

        final pulse = asDouble(m['pulse'] ?? m['heartRate']);
        if (pulse != null) {
          out.add(VitalReading(
            type: VitalType.respiratoryRate, // closest match in enum
            date: ts,
            value: pulse,
            unit: 'bpm',
          ));
        }

        final glucose = asDouble(m['glucose'] ?? m['bloodGlucose'] ?? m['glucoseValue']);
        if (glucose != null) {
          out.add(VitalReading(
            type: VitalType.glucose,
            date: ts,
            value: glucose,
            unit: 'mg/dL',
          ));
        }

        final height = asDouble(m['height']);
        if (height != null) {
          out.add(VitalReading(
              type: VitalType.height, date: ts, value: height, unit: 'cm'));
        }

        final weight = asDouble(m['weight']);
        if (weight != null) {
          out.add(VitalReading(
              type: VitalType.weight, date: ts, value: weight, unit: 'kg'));
        }

        final bmi = asDouble(m['bmi']);
        double? derivedBmi;
        if (bmi == null && height != null && weight != null && height > 0) {
          final h = height / 100.0;
          derivedBmi = weight / (h * h);
        }
        final effectiveBmi = bmi ?? derivedBmi;
        if (effectiveBmi != null) {
          out.add(VitalReading(
              type: VitalType.bmi, date: ts, value: effectiveBmi));
        }

        final temp = asDouble(m['temperature'] ?? m['temp']);
        if (temp != null) {
          out.add(VitalReading(
              type: VitalType.temperature,
              date: ts,
              value: temp,
              unit: '°C'));
        }

        final spo2 = asDouble(m['spO2'] ?? m['spo2'] ?? m['oxygenSaturation']);
        if (spo2 != null) {
          out.add(VitalReading(
              type: VitalType.spO2, date: ts, value: spo2, unit: '%'));
        }

        final rr = asDouble(m['respiratoryRate'] ?? m['respiratoryRateValue']);
        if (rr != null) {
          out.add(VitalReading(
              type: VitalType.respiratoryRate,
              date: ts,
              value: rr,
              unit: '/min'));
        }
      }
    } on Object catch (e) {
      // ignore: avoid_print
      print('[VitalsRepository] latestFromLocal failed: $e');
    }
    return out;
  }

  /// Fetch recent vitals for a patient.
  ///
  /// Local cache is the offline-first source — every row written to the
  /// encounter table by [OfflineSyncService] is read here first so the
  /// section renders before any network call. To top up with the server's
  /// view we pull the FHIR Observation bundle for the most recent encounters
  /// from local cache and map LOINC-coded observations onto [VitalReading]s.
  Future<RecentVitals> recent(
    String patientId, {
    String? memberReference,
    int limit = 20,
  }) async {
    final readings = <VitalReading>[];
    readings.addAll(await latestFromLocal(patientId));

    final obsRepo = _observations;
    if (obsRepo != null && _encounters != null) {
      final encounterIds = await _recentEncounterIdsForPatient(patientId);
      for (final encounterId in encounterIds) {
        final vitals = await obsRepo.vitalsForEncounter(encounterId);
        readings.addAll(vitals);
      }
    } else {
      debugPrint(
          '[VitalsRepository] ObservationRepository/EncounterDao not wired — local only');
    }

    readings.sort((a, b) => b.date.compareTo(a.date));

    // Extract latest of each type
    VitalReading? latestBp;
    VitalReading? latestGlucose;
    VitalReading? latestWeight;
    VitalReading? latestTemp;
    VitalReading? latestSpO2;
    VitalReading? latestRr;
    VitalReading? latestBmi;

    for (final r in readings) {
      switch (r.type) {
        case VitalType.bloodPressure:
          latestBp ??= r;
          break;
        case VitalType.glucose:
          latestGlucose ??= r;
          break;
        case VitalType.weight:
          latestWeight ??= r;
          break;
        case VitalType.temperature:
          latestTemp ??= r;
          break;
        case VitalType.spO2:
          latestSpO2 ??= r;
          break;
        case VitalType.respiratoryRate:
          latestRr ??= r;
          break;
        case VitalType.bmi:
          latestBmi ??= r;
          break;
        default:
          break;
      }
    }

    return RecentVitals(
      latestBp: latestBp,
      latestGlucose: latestGlucose,
      latestWeight: latestWeight,
      latestTemperature: latestTemp,
      latestSpO2: latestSpO2,
      latestRr: latestRr,
      latestBmi: latestBmi,
      allReadings: readings,
    );
  }

  /// Returns the encounter ids most recently cached for [patientId] so we
  /// know which encounters to request observations for.
  Future<List<String>> _recentEncounterIdsForPatient(
    String patientId, {
    int limit = 5,
  }) async {
    final dao = _encounters;
    if (dao == null) return const [];
    final stripped = _bareId(patientId);
    final rows = await dao.recentForPatient(stripped, limit: limit);
    return rows.map((r) => r.id).where((id) => id.isNotEmpty).toList();
  }

}
