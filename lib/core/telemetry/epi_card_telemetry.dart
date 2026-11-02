/// EPI card scan telemetry — payloads and classification (no PHI on the wire).
library;

import '../../features/visit/immunisation/epi_schedule_engine.dart'
    show VaccineMilestone, VaccineStatus;

/// Server feature registry key for EPI card OCR telemetry.
const String kTelemetryAiFeatureEpiCard = 'epi_card';

/// Payload schema version for EPI card events (independent of visit_completed).
const int kEpiCardTelemetryPayloadVersion = 1;

/// Wire values for [EpiVaccinationChangeType].
abstract final class EpiVaccinationChangeTypeWire {
  EpiVaccinationChangeTypeWire._();

  static const String correct = 'correct';
  static const String dateFixed = 'date_fixed';
  static const String wronglyMarked = 'wrongly_marked';
  static const String missed = 'missed';
}

enum EpiVaccinationChangeType {
  correct,
  dateFixed,
  wronglyMarked,
  missed,
}

String epiVaccinationChangeTypeWire(EpiVaccinationChangeType type) =>
    switch (type) {
      EpiVaccinationChangeType.correct =>
        EpiVaccinationChangeTypeWire.correct,
      EpiVaccinationChangeType.dateFixed =>
        EpiVaccinationChangeTypeWire.dateFixed,
      EpiVaccinationChangeType.wronglyMarked =>
        EpiVaccinationChangeTypeWire.wronglyMarked,
      EpiVaccinationChangeType.missed =>
        EpiVaccinationChangeTypeWire.missed,
    };

/// Classifies one dose save on the immunisation update sheet.
///
/// [hadScanPrefill] is true when the sheet opened with a scan pre-filled date
/// for this milestone. Dates are compared locally only — telemetry emits
/// booleans, never calendar values.
EpiVaccinationChangeType classifyEpiVaccinationUpdate({
  required bool ocrDetected,
  required bool hadScanPrefill,
  required bool sameCalendarDayAsPrefill,
  required bool dateChangedFromPrefill,
}) {
  if (!ocrDetected) return EpiVaccinationChangeType.missed;
  if (!hadScanPrefill) return EpiVaccinationChangeType.correct;
  if (sameCalendarDayAsPrefill) return EpiVaccinationChangeType.correct;
  // OCR proposed a date; SK kept vaccinated but picked a different day.
  return EpiVaccinationChangeType.dateFixed;
}

String? epiCardCaptureQualityWire({required bool isBlurry, required bool hasGlare}) {
  if (isBlurry && hasGlare) return EpiCardCaptureQualityWire.blurryAndGlare;
  if (isBlurry) return EpiCardCaptureQualityWire.blurry;
  if (hasGlare) return EpiCardCaptureQualityWire.glare;
  return null;
}

bool epiSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Pending vaccine codes on the timeline (not yet completed).
List<String> epiPendingVaccineKeys(List<VaccineMilestone> milestones) {
  final keys = <String>[];
  for (final milestone in milestones) {
    for (final v in milestone.vaccines) {
      if (v.status != VaccineStatus.completed) {
        keys.add(v.code);
      }
    }
  }
  return keys;
}

List<String> epiDetectedPendingKeys({
  required List<String> pendingKeys,
  required Iterable<String> matchedCodes,
}) {
  final matched = matchedCodes.toSet();
  return pendingKeys.where(matched.contains).toList();
}

abstract final class EpiCardScanSessionOutcomeWire {
  EpiCardScanSessionOutcomeWire._();

  static const String success = 'success';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';
}

/// Advisory capture-quality flags (pre-OCR), when the SK proceeded anyway.
abstract final class EpiCardCaptureQualityWire {
  EpiCardCaptureQualityWire._();

  static const String blurry = 'blurry';
  static const String glare = 'glare';
  static const String blurryAndGlare = 'blurry_and_glare';
}

abstract final class EpiCardScanFailureReasonWire {
  EpiCardScanFailureReasonWire._();

  static const String noMatch = 'no_match';
  static const String network = 'network';
  static const String timeout = 'timeout';
  static const String serverError = 'server_error';
  static const String exception = 'exception';
  static const String offlineFallbackEmpty = 'offline_fallback_empty';
}

Map<String, dynamic> epiCardScanSessionPayload({
  required String scanSessionId,
  required String outcome,
  required int attemptCount,
  required int successfulAttemptCount,
  required bool appliedToApp,
  String cardType = 'epi',
}) =>
    {
      'scanSessionId': scanSessionId,
      'cardType': cardType,
      'outcome': outcome,
      'attemptCount': attemptCount,
      'successfulAttemptCount': successfulAttemptCount,
      'appliedToApp': appliedToApp,
    };

Map<String, dynamic> epiCardScanAttemptPayload({
  required String scanSessionId,
  required int attemptIndex,
  required bool success,
  required String failureReason,
  required String engine,
  required int matchedVaccineCount,
  String? captureQuality,
  String cardType = 'epi',
}) =>
    {
      'scanSessionId': scanSessionId,
      'cardType': cardType,
      'attemptIndex': attemptIndex,
      'success': success,
      if (!success) 'failureReason': failureReason,
      if (captureQuality != null) 'captureQuality': captureQuality,
      'engine': engine,
      'matchedVaccineCount': matchedVaccineCount,
    };

Map<String, dynamic> epiScanDetectionPayload({
  required String scanSessionId,
  required List<String> pendingVaccineKeys,
  required List<String> detectedVaccineKeys,
  String cardType = 'epi',
}) =>
    {
      'scanSessionId': scanSessionId,
      'cardType': cardType,
      'pendingVaccineKeys': pendingVaccineKeys,
      'detectedVaccineKeys': detectedVaccineKeys,
      'pendingCount': pendingVaccineKeys.length,
      'detectedCount': detectedVaccineKeys.length,
    };

Map<String, dynamic> epiVaccinationUpdatePayload({
  required String? scanSessionId,
  required String vaccineKey,
  required String changeType,
  required bool ocrDetected,
  required bool hadScanPrefill,
  required bool dateChangedFromPrefill,
  required int updateDurationMs,
  required bool ocrAssisted,
  String cardType = 'epi',
}) =>
    {
      if (scanSessionId != null) 'scanSessionId': scanSessionId,
      'cardType': cardType,
      'vaccineKey': vaccineKey,
      'changeType': changeType,
      'ocrDetected': ocrDetected,
      'hadScanPrefill': hadScanPrefill,
      'dateChangedFromPrefill': dateChangedFromPrefill,
      'updateDurationMs': updateDurationMs,
      'ocrAssisted': ocrAssisted,
    };
