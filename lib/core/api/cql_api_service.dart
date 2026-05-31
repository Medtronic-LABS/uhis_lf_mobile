import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_repository.dart';
import 'endpoints.dart';

/// API service for CQL (Clinical Quality Language) risk evaluation.
///
/// Wraps the `/cql-service/cql/*` endpoints for server-side risk scoring.
/// Falls back gracefully when offline — callers should catch errors and
/// use on-device [RiskScoringService] as fallback.
///
/// Spec: UHIS architecture.md §3.4 (AI risk scoring contract).
class CqlApiService extends ApiRepository {
  CqlApiService(super.api);

  /// Evaluate risk for a single patient using the server CQL engine.
  ///
  /// If [encounterId] is provided, uses the server-side encounter endpoint.
  /// Otherwise, fetches FHIR resources and sends as a Bundle.
  ///
  /// Returns structured risk assessment or null on failure.
  /// Callers should fall back to [RiskScoringService.score] when this fails.
  Future<CqlRiskResult?> evaluatePatient({
    required String patientId,
    String? encounterId,
  }) async {
    try {
      // If we have an encounter ID, use the server-side endpoint that
      // fetches FHIR resources internally.
      if (encounterId != null) {
        final body = await postOk(
          Endpoints.cqlEvaluateEncounter,
          data: {
            'id': encounterId,
            'tenantId': api.tenantIdAsNum,
          },
          action: 'CQL evaluate encounter',
        );
        return CqlRiskResult.fromJson(body as Map<String, dynamic>);
      }

      // Otherwise, fetch FHIR Patient/$everything and send as Bundle.
      final fhirBundle = await _fetchPatientEverything(patientId);
      if (fhirBundle == null) {
        debugPrint('[CqlApiService] Failed to fetch FHIR bundle for $patientId');
        return null;
      }

      final body = await postOk(
        Endpoints.cqlEvaluate,
        data: {
          'resourceBundle': jsonEncode(fhirBundle),
        },
        action: 'CQL evaluate',
      );

      return CqlRiskResult.fromJson(body as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[CqlApiService] evaluatePatient error: $e');
      return null;
    }
  }

  /// Batch evaluate risk for multiple patients.
  ///
  /// Fetches FHIR resources for each patient and evaluates them one by one.
  /// Returns map of patientId → CqlRiskResult.
  ///
  /// Note: This evaluates patients sequentially to avoid overwhelming the
  /// FHIR server. For large batches, consider using [evaluatePatient] with
  /// encounter IDs when available.
  Future<Map<String, CqlRiskResult>> evaluatePatients(
    List<String> patientIds,
  ) async {
    if (patientIds.isEmpty) return const {};

    final results = <String, CqlRiskResult>{};

    for (final patientId in patientIds) {
      try {
        final result = await evaluatePatient(patientId: patientId);
        if (result != null) {
          results[patientId] = result;
        }
      } catch (e) {
        debugPrint('[CqlApiService] evaluatePatients: Failed for $patientId: $e');
        // Continue with other patients.
      }
    }

    return results;
  }

  /// Fetch FHIR Patient/$everything Bundle for a patient.
  ///
  /// Returns the raw FHIR Bundle as a Map, or null on failure.
  Future<Map<String, dynamic>?> _fetchPatientEverything(
    String patientId,
  ) async {
    try {
      final resp = await api.dio.get(
        Endpoints.fhirPatientEverything(patientId),
      );
      final code = resp.statusCode ?? 0;
      if (code < 200 || code >= 300) {
        debugPrint('[CqlApiService] FHIR fetch failed: $code');
        return null;
      }
      final data = resp.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('[CqlApiService] _fetchPatientEverything error: $e');
      return null;
    }
  }

  /// Get cached CQL result for a patient (if available).
  ///
  /// The CQL service may cache recent evaluations server-side.
  Future<CqlRiskResult?> getCachedResult(String patientId) async {
    try {
      final body = await postOk(
        Endpoints.cqlResult,
        data: {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'CQL cached result',
      );

      if (body is Map<String, dynamic> && body.isNotEmpty) {
        return CqlRiskResult.fromJson(body);
      }
      return null;
    } catch (e) {
      debugPrint('[CqlApiService] getCachedResult error: $e');
      return null;
    }
  }

  /// Evaluate a specific CQL expression against patient data.
  ///
  /// Used for targeted rule evaluation (e.g., ANC risk only).
  Future<Map<String, dynamic>?> evaluateExpression({
    required String patientId,
    required String libraryName,
    required List<String> expressions,
  }) async {
    try {
      final body = await postOk(
        Endpoints.cqlExpression,
        data: {
          'patientId': patientId,
          'libraryName': libraryName,
          'expressions': expressions,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'CQL expression',
      );

      return body is Map<String, dynamic> ? body : null;
    } catch (e) {
      debugPrint('[CqlApiService] evaluateExpression error: $e');
      return null;
    }
  }

  /// Get ANC-specific risk result for a patient.
  Future<CqlAncResult?> getAncResult(String patientId) async {
    try {
      final body = await postOk(
        Endpoints.cqlAncResult,
        data: {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'CQL ANC result',
      );

      if (body is Map<String, dynamic> && body.isNotEmpty) {
        return CqlAncResult.fromJson(body);
      }
      return null;
    } catch (e) {
      debugPrint('[CqlApiService] getAncResult error: $e');
      return null;
    }
  }

  /// Get ANC results aggregated by villages (for dashboard).
  Future<List<CqlAncResult>> getAncResultsByVillages(
    List<int> villageIds,
  ) async {
    if (villageIds.isEmpty) return const [];

    try {
      final body = await postOk(
        Endpoints.cqlAncResultList,
        data: {
          'villageIds': villageIds,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'CQL ANC results list',
      );

      final list = extractList(body);
      return list
          .whereType<Map<String, dynamic>>()
          .map(CqlAncResult.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[CqlApiService] getAncResultsByVillages error: $e');
      return const [];
    }
  }
}

/// Structured CQL risk evaluation result.
///
/// Maps the response from `/cql-service/cql/evaluate` and `/cql-service/cql/result`.
class CqlRiskResult {
  const CqlRiskResult({
    required this.patientId,
    required this.score,
    required this.level,
    required this.drivers,
    this.modelVersion,
    this.computedAt,
    this.confidence,
    this.recommendations = const [],
  });

  factory CqlRiskResult.fromJson(Map<String, dynamic> json) {
    final drivers = <String>[];
    final rawDrivers = json['drivers'] ?? json['riskDrivers'] ?? json['factors'];
    if (rawDrivers is List) {
      for (final d in rawDrivers) {
        if (d is String) {
          drivers.add(d);
        } else if (d is Map) {
          // Handle structured driver objects: { code: 'under-5', weight: 20 }
          final code = d['code'] ?? d['name'] ?? d['driver'];
          if (code is String) drivers.add(code);
        }
      }
    }

    final recommendations = <String>[];
    final rawRecs = json['recommendations'] ?? json['actions'];
    if (rawRecs is List) {
      for (final r in rawRecs) {
        if (r is String) {
          recommendations.add(r);
        } else if (r is Map && r['text'] is String) {
          recommendations.add(r['text'] as String);
        }
      }
    }

    return CqlRiskResult(
      patientId: json['patientId'] as String? ?? '',
      score: _parseScore(json['score'] ?? json['riskScore']),
      level: _parseLevel(json['level'] ?? json['riskLevel']),
      drivers: drivers,
      modelVersion: json['modelVersion'] as String?,
      computedAt: _parseDateTime(json['computedAt'] ?? json['evaluatedAt']),
      confidence: _parseConfidence(json['confidence']),
      recommendations: recommendations,
    );
  }

  final String patientId;

  /// Numeric risk score (0-100).
  final int score;

  /// Risk level: LOW, MODERATE, HIGH, URGENT.
  final CqlRiskLevel level;

  /// Machine-readable risk drivers, e.g. ['under-5', 'missed-visits:3'].
  final List<String> drivers;

  /// CQL model version, e.g. 'cql-risk-v2.1'.
  final String? modelVersion;

  /// When the server computed this result.
  final DateTime? computedAt;

  /// ML confidence score (0.0-1.0), null for rule-based.
  final double? confidence;

  /// Server-generated recommendations/actions.
  final List<String> recommendations;

  /// True if this result indicates critical priority.
  bool get isCritical => level == CqlRiskLevel.urgent || score >= 80;

  /// True if this result indicates high priority.
  bool get isHighPriority =>
      level == CqlRiskLevel.high || level == CqlRiskLevel.urgent || score >= 60;

  static int _parseScore(dynamic raw) {
    if (raw is int) return raw.clamp(0, 100);
    if (raw is double) return raw.round().clamp(0, 100);
    if (raw is String) return int.tryParse(raw)?.clamp(0, 100) ?? 0;
    return 0;
  }

  static CqlRiskLevel _parseLevel(dynamic raw) {
    if (raw is String) {
      switch (raw.toUpperCase()) {
        case 'URGENT':
        case 'CRITICAL':
          return CqlRiskLevel.urgent;
        case 'HIGH':
          return CqlRiskLevel.high;
        case 'MODERATE':
        case 'MEDIUM':
          return CqlRiskLevel.moderate;
        case 'LOW':
        case 'NORMAL':
          return CqlRiskLevel.low;
      }
    }
    return CqlRiskLevel.low;
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }

  static double? _parseConfidence(dynamic raw) {
    if (raw is double) return raw.clamp(0.0, 1.0);
    if (raw is int) return (raw / 100).clamp(0.0, 1.0);
    if (raw is String) return double.tryParse(raw)?.clamp(0.0, 1.0);
    return null;
  }
}

/// CQL risk level enum.
enum CqlRiskLevel {
  low,
  moderate,
  high,
  urgent,
}

/// ANC-specific CQL result.
class CqlAncResult {
  const CqlAncResult({
    required this.patientId,
    this.gestationalWeeks,
    this.riskLevel,
    this.riskFactors = const [],
    this.nextVisitDue,
    this.ancVisitsCompleted = 0,
    this.ancVisitsExpected = 0,
    this.isHighRisk = false,
  });

  factory CqlAncResult.fromJson(Map<String, dynamic> json) {
    final riskFactors = <String>[];
    final rawFactors = json['riskFactors'] ?? json['factors'];
    if (rawFactors is List) {
      for (final f in rawFactors) {
        if (f is String) riskFactors.add(f);
      }
    }

    return CqlAncResult(
      patientId: json['patientId'] as String? ?? '',
      gestationalWeeks: json['gestationalWeeks'] as int?,
      riskLevel: json['riskLevel'] as String?,
      riskFactors: riskFactors,
      nextVisitDue: json['nextVisitDue'] is String
          ? DateTime.tryParse(json['nextVisitDue'] as String)
          : null,
      ancVisitsCompleted: json['ancVisitsCompleted'] as int? ?? 0,
      ancVisitsExpected: json['ancVisitsExpected'] as int? ?? 0,
      isHighRisk: json['isHighRisk'] == true,
    );
  }

  final String patientId;
  final int? gestationalWeeks;
  final String? riskLevel;
  final List<String> riskFactors;
  final DateTime? nextVisitDue;
  final int ancVisitsCompleted;
  final int ancVisitsExpected;
  final bool isHighRisk;

  /// True if ANC visits are behind schedule.
  bool get isBehindSchedule => ancVisitsCompleted < ancVisitsExpected;
}
