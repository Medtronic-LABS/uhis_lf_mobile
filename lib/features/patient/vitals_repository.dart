import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/db/encounter_dao.dart';

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
  VitalsRepository(super.api, {EncounterDao? encounters}) : _encounters = encounters;

  final EncounterDao? _encounters;

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
  /// Tries multiple identifier formats: patientReference, memberReference, patientId.
  Future<RecentVitals> recent(
    String patientId, {
    String? memberReference,
    int limit = 20,
  }) async {
    // ignore: avoid_print
    print('[VitalsRepository] ========== recent START ==========');
    print('[VitalsRepository] patientId=$patientId, memberRef=$memberReference, limit=$limit');
    final readings = <VitalReading>[];

    // Local-first — pull whatever the device already captured before
    // hitting the network. Lets the section render offline; remote calls
    // below just top up any newer rows the server has.
    readings.addAll(await latestFromLocal(patientId));

    // Build patient reference in FHIR format
    String patientRef = patientId;
    if (!patientId.startsWith('Patient/')) {
      patientRef = 'Patient/$patientId';
    }
    // ignore: avoid_print
    print('[VitalsRepository] Using patientRef=$patientRef');

    // Try to fetch from patient vitals endpoint with different ID formats
    await _tryFetchVitals(
      readings,
      {
        'patientReference': patientRef,
        'tenantId': api.tenantIdAsNum,
        'skip': 0,
        'limit': limit,
      },
      'Patient vitals (patientReference)',
    );

    // If no results, try with patientId directly
    if (readings.isEmpty) {
      // ignore: avoid_print
      print('[VitalsRepository] No results with patientReference, trying patientId');
      await _tryFetchVitals(
        readings,
        {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        },
        'Patient vitals (patientId)',
      );
    }

    // Also fetch BP logs
    await _tryFetchBpLogs(readings, patientId, patientRef, memberReference, limit);

    // Fetch glucose logs for NCD patients
    await _tryFetchGlucoseLogs(readings, patientId, patientRef, memberReference, limit);

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

    // ignore: avoid_print
    print('[VitalsRepository] Total readings collected: ${readings.length}');
    print('[VitalsRepository] LatestBP: ${latestBp?.displayValue}, LatestGlucose: ${latestGlucose?.displayValue}');
    print('[VitalsRepository] LatestWeight: ${latestWeight?.displayValue}, LatestTemp: ${latestTemp?.displayValue}');
    print('[VitalsRepository] ========== recent END ==========');

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

  Future<void> _tryFetchVitals(
    List<VitalReading> readings,
    Map<String, dynamic> data,
    String action,
  ) async {
    try {
      // ignore: avoid_print
      print('[VitalsRepository] Calling ${Endpoints.patientVitalsList} - $action');
      print('[VitalsRepository] Request: $data');

      final body = await postOk(
        Endpoints.patientVitalsList,
        data: data,
        action: action,
      );

      // ignore: avoid_print
      print('[VitalsRepository] Response body type: ${body.runtimeType}');
      print('[VitalsRepository] Response: $body');

      final list = extractList(body);
      // ignore: avoid_print
      print('[VitalsRepository] $action returned ${list.length} vitals');
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          // ignore: avoid_print
          print('[VitalsRepository] Vital item: $item');
          final reading = _parseVitalReading(item);
          if (reading != null) readings.add(reading);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[VitalsRepository] $action failed: $e');
    }
  }

  /// Extract BP logs from the nested response structure.
  /// API returns: { entity: { bpLogList: [...], latestBpLog: {...} } }
  List _extractBpLogList(dynamic body) {
    if (body is Map) {
      // Check for entity.bpLogList structure
      final entity = body['entity'];
      if (entity is Map) {
        final bpLogList = entity['bpLogList'];
        if (bpLogList is List && bpLogList.isNotEmpty) {
          return bpLogList;
        }
        // Also check for latestBpLog (single item)
        final latestBpLog = entity['latestBpLog'];
        if (latestBpLog is Map && latestBpLog['avgSystolic'] != null) {
          return [latestBpLog];
        }
      }
      // Fallback to standard extractList behavior
      if (body['entityList'] is List) return body['entityList'] as List;
      if (body['data'] is List) return body['data'] as List;
    }
    if (body is List) return body;
    return const [];
  }

  /// Extract glucose logs from the nested response structure.
  /// API returns: { entity: { glucoseLogList: [...], latestGlucoseLog: {...} } }
  List _extractGlucoseLogList(dynamic body) {
    if (body is Map) {
      // Check for entity.glucoseLogList structure
      final entity = body['entity'];
      if (entity is Map) {
        final glucoseLogList = entity['glucoseLogList'];
        if (glucoseLogList is List && glucoseLogList.isNotEmpty) {
          return glucoseLogList;
        }
        // Also check for latestGlucoseLog (single item)
        final latestGlucoseLog = entity['latestGlucoseLog'];
        if (latestGlucoseLog is Map && latestGlucoseLog['glucoseValue'] != null) {
          return [latestGlucoseLog];
        }
      }
      // Fallback to standard extractList behavior
      if (body['entityList'] is List) return body['entityList'] as List;
      if (body['data'] is List) return body['data'] as List;
    }
    if (body is List) return body;
    return const [];
  }

  Future<void> _tryFetchBpLogs(
    List<VitalReading> readings,
    String patientId,
    String patientRef,
    String? memberReference,
    int limit,
  ) async {
    // ignore: avoid_print
    print('[VitalsRepository] Fetching BP logs...');
    
    // Extract memberId from memberReference (e.g., "RelatedPerson/401" -> "401")
    String? memberId;
    if (memberReference != null) {
      if (memberReference.contains('/')) {
        memberId = memberReference.split('/').last;
      } else {
        memberId = memberReference;
      }
    }
    
    // API requires memberId field (not memberReference)
    if (memberId != null) {
      try {
        final requestData = {
          'memberId': memberId,
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        };
        // ignore: avoid_print
        print('[VitalsRepository] Calling ${Endpoints.bpLogList} with memberId');
        print('[VitalsRepository] Request: $requestData');

        final bpBody = await postOk(
          Endpoints.bpLogList,
          data: requestData,
          action: 'BP logs (memberId)',
        );
        // ignore: avoid_print
        print('[VitalsRepository] BP response: $bpBody');
        final bpList = _extractBpLogList(bpBody);
        // ignore: avoid_print
        print('[VitalsRepository] BP logs returned ${bpList.length} records');
        for (final item in bpList) {
          if (item is Map<String, dynamic>) {
            // ignore: avoid_print
            print('[VitalsRepository] BP item: $item');
            final reading = _parseBpReading(item);
            if (reading != null) readings.add(reading);
          }
        }
        if (bpList.isNotEmpty) return;
      } catch (e) {
        // ignore: avoid_print
        print('[VitalsRepository] BP logs (memberId) failed: $e');
      }
    }

    // Fallback: try with patientId (for patients without member mapping)
    try {
      // ignore: avoid_print
      print('[VitalsRepository] Trying BP logs with patientId...');
      final bpBody = await postOk(
        Endpoints.bpLogList,
        data: {
          'memberId': patientId, // Try patientId as memberId
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        },
        action: 'BP logs (patientId as memberId)',
      );
      final bpList = _extractBpLogList(bpBody);
      // ignore: avoid_print
      print('[VitalsRepository] BP logs (patientId) returned ${bpList.length} records');
      for (final item in bpList) {
        if (item is Map<String, dynamic>) {
          final reading = _parseBpReading(item);
          if (reading != null) readings.add(reading);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[VitalsRepository] BP logs (patientId) failed: $e');
    }
  }

  Future<void> _tryFetchGlucoseLogs(
    List<VitalReading> readings,
    String patientId,
    String patientRef,
    String? memberReference,
    int limit,
  ) async {
    // ignore: avoid_print
    print('[VitalsRepository] Fetching Glucose logs...');
    
    // Extract memberId from memberReference (e.g., "RelatedPerson/401" -> "401")
    String? memberId;
    if (memberReference != null) {
      if (memberReference.contains('/')) {
        memberId = memberReference.split('/').last;
      } else {
        memberId = memberReference;
      }
    }
    
    // API requires memberId field (not memberReference)
    if (memberId != null) {
      try {
        final requestData = {
          'memberId': memberId,
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        };
        // ignore: avoid_print
        print('[VitalsRepository] Calling ${Endpoints.glucoseLogList} with memberId');
        print('[VitalsRepository] Request: $requestData');

        final glucoseBody = await postOk(
          Endpoints.glucoseLogList,
          data: requestData,
          action: 'Glucose logs (memberId)',
        );
        // ignore: avoid_print
        print('[VitalsRepository] Glucose response: $glucoseBody');
        final glucoseList = _extractGlucoseLogList(glucoseBody);
        // ignore: avoid_print
        print('[VitalsRepository] Glucose logs returned ${glucoseList.length} records');
        for (final item in glucoseList) {
          if (item is Map<String, dynamic>) {
            // ignore: avoid_print
            print('[VitalsRepository] Glucose item: $item');
            final reading = _parseGlucoseReading(item);
            if (reading != null) readings.add(reading);
          }
        }
        if (glucoseList.isNotEmpty) return;
      } catch (e) {
        // ignore: avoid_print
        print('[VitalsRepository] Glucose logs (memberId) failed: $e');
      }
    }

    // Fallback: try with patientId as memberId
    try {
      // ignore: avoid_print
      print('[VitalsRepository] Trying Glucose logs with patientId as memberId...');
      final glucoseBody = await postOk(
        Endpoints.glucoseLogList,
        data: {
          'memberId': patientId,
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        },
        action: 'Glucose logs (patientId as memberId)',
      );
      final glucoseList = _extractGlucoseLogList(glucoseBody);
      // ignore: avoid_print
      print('[VitalsRepository] Glucose logs (patientId) returned ${glucoseList.length} records');
      for (final item in glucoseList) {
        if (item is Map<String, dynamic>) {
          final reading = _parseGlucoseReading(item);
          if (reading != null) readings.add(reading);
        }
      }
    } catch (_) {}
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
