import 'json_read.dart';

/// Single FHIR R4 `Observation` parsed from the HAPI FHIR Bundle returned by
/// `GET /fhir-server/fhir/Observation?encounter=Encounter/{id}`.
///
/// Only the fields needed by the encounter-detail view are captured — code +
/// LOINC binding, effectiveDateTime, value (Quantity or component vector),
/// status, and the rationale extension we ship with every Leapfrog AI
/// proposal. Other FHIR fields stay in [rawJson] so downstream code can read
/// them without re-parsing.
class FhirObservation {
  const FhirObservation({
    required this.id,
    required this.code,
    required this.system,
    this.display,
    this.effectiveDateTime,
    this.valueQuantity,
    this.valueUnit,
    this.valueString,
    this.components = const [],
    this.status,
    this.rawJson = const {},
  });

  final String id;

  /// Coded identifier — usually a LOINC code (e.g. `85354-9` for
  /// blood-pressure panel, `8302-2` for body height).
  final String code;

  /// Code system URI (e.g. `http://loinc.org`).
  final String system;
  final String? display;
  final DateTime? effectiveDateTime;
  final double? valueQuantity;
  final String? valueUnit;
  final String? valueString;

  /// BP-style observations carry components (8480-6 systolic + 8462-4
  /// diastolic). Each component reuses the same shape as the parent.
  final List<FhirObservation> components;
  final String? status;
  final Map<String, dynamic> rawJson;

  static FhirObservation? fromJson(Map<String, dynamic> json) {
    if (json['resourceType'] != 'Observation') return null;
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) return null;

    final coding = _firstCoding(json['code']);
    if (coding == null) return null;

    DateTime? effective;
    final eff = json['effectiveDateTime'];
    if (eff is String) effective = DateTime.tryParse(eff);

    final value = _valueQuantity(json['valueQuantity']);
    final valueStr = json['valueString'] is String
        ? (json['valueString'] as String).trim()
        : null;

    final components = <FhirObservation>[];
    final rawComponents = json['component'];
    if (rawComponents is List) {
      for (final c in rawComponents) {
        if (c is! Map) continue;
        final comp = _componentFromJson(
          Map<String, dynamic>.from(c),
          parentEffective: effective,
        );
        if (comp != null) components.add(comp);
      }
    }

    return FhirObservation(
      id: id,
      code: coding.code,
      system: coding.system,
      display: coding.display,
      effectiveDateTime: effective,
      valueQuantity: value?.value,
      valueUnit: value?.unit,
      valueString: valueStr,
      components: components,
      status: json['status']?.toString(),
      rawJson: Map<String, dynamic>.from(json),
    );
  }

  static _Coding? _firstCoding(Object? code) {
    if (code is! Map) return null;
    final coding = code['coding'];
    if (coding is! List) return null;
    for (final c in coding) {
      if (c is! Map) continue;
      final codeVal = c['code']?.toString();
      final systemVal = c['system']?.toString();
      if (codeVal == null || codeVal.isEmpty) continue;
      if (systemVal == null || systemVal.isEmpty) continue;
      return _Coding(
        code: codeVal,
        system: systemVal,
        display: c['display']?.toString(),
      );
    }
    return null;
  }

  static _Value? _valueQuantity(Object? q) {
    if (q is! Map) return null;
    final value = q['value'];
    double? n;
    if (value is num) n = value.toDouble();
    if (value is String) n = double.tryParse(value);
    if (n == null) return null;
    return _Value(value: n, unit: q['unit']?.toString());
  }

  static FhirObservation? _componentFromJson(
    Map<String, dynamic> json, {
    required DateTime? parentEffective,
  }) {
    final coding = _firstCoding(json['code']);
    if (coding == null) return null;
    final value = _valueQuantity(json['valueQuantity']);
    return FhirObservation(
      id: '${coding.system}|${coding.code}', // synthetic — components have no id
      code: coding.code,
      system: coding.system,
      display: coding.display,
      effectiveDateTime: parentEffective,
      valueQuantity: value?.value,
      valueUnit: value?.unit,
      rawJson: json,
    );
  }
}

class _Coding {
  const _Coding({required this.code, required this.system, this.display});
  final String code;
  final String system;
  final String? display;
}

class _Value {
  const _Value({required this.value, this.unit});
  final double value;
  final String? unit;
}

/// Wrapper around the FHIR `Bundle` HAPI returns from a search interaction.
class FhirObservationBundle {
  const FhirObservationBundle({required this.observations, this.total});

  final List<FhirObservation> observations;
  final int? total;

  static FhirObservationBundle fromJson(Map<String, dynamic> json) {
    final entries = json['entry'];
    final out = <FhirObservation>[];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is! Map) continue;
        final resource = entry['resource'];
        if (resource is! Map) continue;
        final obs =
            FhirObservation.fromJson(Map<String, dynamic>.from(resource));
        if (obs != null) out.add(obs);
      }
    }
    return FhirObservationBundle(
      observations: out,
      total: JsonRead.firstInt(json, const ['total']),
    );
  }
}

/// LOINC + UCUM codes for the vitals the encounter detail screen renders.
/// Centralised so the mapping table is the single home for the rule
/// (Engineering Design Standards: DRY) and a coding swap (e.g. SNOMED for a
/// future programme) is a one-file change.
abstract final class LoincVitalCodes {
  LoincVitalCodes._();

  static const String loincSystem = 'http://loinc.org';

  static const String bloodPressurePanel = '85354-9';
  static const String systolic = '8480-6';
  static const String diastolic = '8462-4';
  static const String bodyHeight = '8302-2';
  static const String bodyWeight = '29463-7';
  static const String bmi = '39156-5';
  static const String temperature = '8310-5';
  static const String pulse = '8867-4';
  static const String respiratoryRate = '9279-1';
  static const String oxygenSaturation = '59408-5';
  static const String bloodGlucose = '2339-0';
  static const String muac = '56072-2';
}
