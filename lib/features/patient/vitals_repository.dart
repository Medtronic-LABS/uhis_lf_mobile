import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';

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
      latestTemperature == null;
}

/// Repository for fetching patient vitals history.
class VitalsRepository extends ApiRepository {
  VitalsRepository(super.api);

  /// Fetch recent vitals for a patient.
  Future<RecentVitals> recent(String patientId, {int limit = 20}) async {
    final readings = <VitalReading>[];

    try {
      // Fetch from patient vitals endpoint
      final body = await postOk(
        Endpoints.patientVitalsList,
        data: {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        },
        action: 'Patient vitals',
      );

      final list = extractList(body);
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final reading = _parseVitalReading(item);
          if (reading != null) readings.add(reading);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[VitalsRepository] Failed to fetch vitals: $e');
    }

    // Also fetch BP logs
    try {
      final bpBody = await postOk(
        Endpoints.bpLogList,
        data: {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        },
        action: 'BP logs',
      );
      final bpList = extractList(bpBody);
      for (final item in bpList) {
        if (item is Map<String, dynamic>) {
          final reading = _parseBpReading(item);
          if (reading != null) readings.add(reading);
        }
      }
    } catch (_) {}

    // Fetch glucose logs for NCD patients
    try {
      final glucoseBody = await postOk(
        Endpoints.glucoseLogList,
        data: {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        },
        action: 'Glucose logs',
      );
      final glucoseList = extractList(glucoseBody);
      for (final item in glucoseList) {
        if (item is Map<String, dynamic>) {
          final reading = _parseGlucoseReading(item);
          if (reading != null) readings.add(reading);
        }
      }
    } catch (_) {}

    // Sort all readings by date descending
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

  VitalReading? _parseVitalReading(Map<String, dynamic> json) {
    final typeStr = json['type']?.toString()?.toLowerCase() ?? '';
    
    DateTime? date;
    final dateVal = json['createdAt'] ?? json['date'] ?? json['recordedAt'];
    if (dateVal is String) {
      date = DateTime.tryParse(dateVal);
    } else if (dateVal is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateVal);
    }
    date ??= DateTime.now();

    VitalType? type;
    double? value;
    double? systolic;
    double? diastolic;

    if (typeStr.contains('bp') || typeStr.contains('blood_pressure')) {
      type = VitalType.bloodPressure;
      systolic = _parseDouble(json['systolic'] ?? json['avgSystolic']);
      diastolic = _parseDouble(json['diastolic'] ?? json['avgDiastolic']);
    } else if (typeStr.contains('glucose')) {
      type = VitalType.glucose;
      value = _parseDouble(json['value'] ?? json['glucoseValue']);
    } else if (typeStr.contains('weight')) {
      type = VitalType.weight;
      value = _parseDouble(json['value'] ?? json['weight']);
    } else if (typeStr.contains('height')) {
      type = VitalType.height;
      value = _parseDouble(json['value'] ?? json['height']);
    } else if (typeStr.contains('temp')) {
      type = VitalType.temperature;
      value = _parseDouble(json['value'] ?? json['temperature']);
    } else if (typeStr.contains('spo2') || typeStr.contains('oxygen')) {
      type = VitalType.spO2;
      value = _parseDouble(json['value'] ?? json['spO2']);
    } else if (typeStr.contains('rr') || typeStr.contains('respiratory')) {
      type = VitalType.respiratoryRate;
      value = _parseDouble(json['value'] ?? json['respiratoryRate']);
    } else if (typeStr.contains('bmi')) {
      type = VitalType.bmi;
      value = _parseDouble(json['value'] ?? json['bmi']);
    } else if (typeStr.contains('muac')) {
      type = VitalType.muac;
      value = _parseDouble(json['value'] ?? json['muac']);
    }

    if (type == null) return null;

    return VitalReading(
      type: type,
      date: date,
      value: value,
      systolic: systolic,
      diastolic: diastolic,
      unit: json['unit']?.toString(),
      classification: json['classification']?.toString() ??
          json['status']?.toString(),
      rawJson: json,
    );
  }

  VitalReading? _parseBpReading(Map<String, dynamic> json) {
    DateTime? date;
    final dateVal = json['createdAt'] ?? json['bpTakenOn'] ?? json['date'];
    if (dateVal is String) {
      date = DateTime.tryParse(dateVal);
    } else if (dateVal is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateVal);
    }
    date ??= DateTime.now();

    final systolic = _parseDouble(json['avgSystolic'] ?? json['systolic']);
    final diastolic = _parseDouble(json['avgDiastolic'] ?? json['diastolic']);

    if (systolic == null && diastolic == null) return null;

    return VitalReading(
      type: VitalType.bloodPressure,
      date: date,
      systolic: systolic,
      diastolic: diastolic,
      unit: 'mmHg',
      classification: json['bpClassification']?.toString() ??
          json['riskLevel']?.toString(),
      rawJson: json,
    );
  }

  VitalReading? _parseGlucoseReading(Map<String, dynamic> json) {
    DateTime? date;
    final dateVal = json['createdAt'] ?? json['glucoseLogDate'] ?? json['date'];
    if (dateVal is String) {
      date = DateTime.tryParse(dateVal);
    } else if (dateVal is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateVal);
    }
    date ??= DateTime.now();

    final value = _parseDouble(json['glucoseValue'] ?? json['value']);
    if (value == null) return null;

    return VitalReading(
      type: VitalType.glucose,
      date: date,
      value: value,
      unit: json['glucoseUnit']?.toString() ?? 'mg/dL',
      classification: json['glucoseClassification']?.toString() ??
          json['diabetesStatus']?.toString(),
      rawJson: json,
    );
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
