import 'package:flutter/foundation.dart';

import 'api_repository.dart';

/// CQL service stubs — all endpoints removed from approved API set.
/// Methods return null/empty without any network calls.
class CqlApiService extends ApiRepository {
  CqlApiService(super.api);

  Future<CqlRiskResult?> evaluatePatient({
    required String patientId,
    String? encounterId,
  }) async {
    debugPrint('[CqlApiService] disabled — not in approved API set');
    return null;
  }

  Future<Map<String, CqlRiskResult>> evaluatePatients(
    List<String> patientIds,
  ) async =>
      const {};

  Future<CqlRiskResult?> getCachedResult(String patientId) async => null;

  Future<Map<String, dynamic>?> evaluateExpression({
    required String patientId,
    required String libraryName,
    required List<String> expressions,
  }) async =>
      null;

  Future<CqlAncResult?> getAncResult(String patientId) async => null;

  Future<List<CqlAncResult>> getAncResultsByVillages(
    List<int> villageIds,
  ) async =>
      const [];
}

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

  final String patientId;
  final int score;
  final CqlRiskLevel level;
  final List<String> drivers;
  final String? modelVersion;
  final DateTime? computedAt;
  final double? confidence;
  final List<String> recommendations;

  bool get isCritical => level == CqlRiskLevel.urgent || score >= 80;
  bool get isHighPriority =>
      level == CqlRiskLevel.high || level == CqlRiskLevel.urgent || score >= 60;
}

enum CqlRiskLevel { low, moderate, high, urgent }

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

  final String patientId;
  final int? gestationalWeeks;
  final String? riskLevel;
  final List<String> riskFactors;
  final DateTime? nextVisitDue;
  final int ancVisitsCompleted;
  final int ancVisitsExpected;
  final bool isHighRisk;

  bool get isBehindSchedule => ancVisitsCompleted < ancVisitsExpected;
}
