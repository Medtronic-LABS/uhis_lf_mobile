/// Shared request-field builders for AI service payloads (Visit Briefing,
/// patient-scoped Assistant) that need the same "recent vitals" / "open
/// follow-ups" summary shape out of [VisitVitals]/[FollowUp] rows.
library;

import '../../features/patient/followup_repository.dart';
import '../../features/patient/vitals_repository.dart';

/// Flat map of the most recent visit's key vitals, e.g.
/// `{'bloodPressureSystolic': 130, 'weight': 58.0}`. Null when there's no
/// vitals history, or the latest visit has none of these reading types.
Map<String, dynamic>? buildRecentVitalsSummary(
  List<VisitVitals> visitsByVisit,
) {
  if (visitsByVisit.isEmpty) return null;
  final latest = visitsByVisit.first;
  final bp =
      latest.readings.where((r) => r.type == VitalType.bloodPressure).firstOrNull;
  final weight =
      latest.readings.where((r) => r.type == VitalType.weight).firstOrNull;
  final glucose =
      latest.readings.where((r) => r.type == VitalType.glucose).firstOrNull;
  final spo2 =
      latest.readings.where((r) => r.type == VitalType.spO2).firstOrNull;
  final bmi = latest.readings.where((r) => r.type == VitalType.bmi).firstOrNull;
  final map = <String, dynamic>{
    if (bp?.systolic != null) 'bloodPressureSystolic': bp!.systolic!.toInt(),
    if (bp?.diastolic != null) 'bloodPressureDiastolic': bp!.diastolic!.toInt(),
    if (weight?.value != null) 'weight': weight!.value,
    if (glucose?.value != null) 'glucose': glucose!.value,
    if (spo2?.value != null) 'spO2': spo2!.value!.toInt(),
    if (bmi?.value != null) 'bmi': bmi!.value,
  };
  return map.isEmpty ? null : map;
}

/// Flat summary of open follow-ups: type, days overdue (if any), reason.
List<Map<String, dynamic>> buildFollowUpSummaries(List<FollowUp> followUps) {
  return followUps.map((f) {
    final daysOverdue =
        f.isOverdue ? DateTime.now().difference(f.dueDate).inDays : null;
    return {
      'type': f.type.name,
      'daysOverdue': daysOverdue,
      'reason': f.reason,
    };
  }).toList();
}
