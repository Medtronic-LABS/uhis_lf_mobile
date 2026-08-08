/// Resolves each patient's scheduled follow-up from visit rows (assessment
/// history and/or local assessments).
///
/// Rule: use the **latest visit only**. If that visit has no
/// `nextFollowUpDate`, the patient has no due date — never fall back to an
/// older visit's date.
abstract final class LatestVisitFollowUp {
  LatestVisitFollowUp._();

  /// [patientId] → follow-up epoch ms when the latest visit stamped one.
  /// Patients whose latest visit has a null follow-up are **absent**.
  static Map<String, int> resolveNonNull({
    required Iterable<LatestVisitFollowUpRow> rows,
  }) {
    final decided = resolveDecisions(rows: rows);
    return {
      for (final e in decided.entries)
        if (e.value.nextFollowUpMs != null) e.key: e.value.nextFollowUpMs!,
    };
  }

  /// [patientId] → follow-up epoch ms, or `null` when the latest visit has none.
  /// Only patients that appear in [rows] are present in the map.
  static Map<String, int?> resolve({
    required Iterable<LatestVisitFollowUpRow> rows,
  }) {
    final decided = resolveDecisions(rows: rows);
    return {
      for (final e in decided.entries) e.key: e.value.nextFollowUpMs,
    };
  }

  /// Like [resolve] but also returns the latest visit timestamp used.
  static Map<String, LatestVisitFollowUpDecision> resolveDecisions({
    required Iterable<LatestVisitFollowUpRow> rows,
  }) {
    final lockedVisitMs = <String, int>{};
    final out = <String, LatestVisitFollowUpDecision>{};

    for (final row in rows) {
      final visitMs = row.visitDate.millisecondsSinceEpoch;
      final locked = lockedVisitMs[row.patientId];
      final nfdMs = row.nextFollowUpDate?.millisecondsSinceEpoch;

      if (locked == null || visitMs > locked) {
        lockedVisitMs[row.patientId] = visitMs;
        out[row.patientId] = LatestVisitFollowUpDecision(
          visitMs: visitMs,
          nextFollowUpMs: nfdMs,
        );
        continue;
      }

      // Same visit instant: prefer a non-null stamp from any assessment on
      // that visit (e.g. childhood + immunization sharing a timestamp).
      if (visitMs == locked && nfdMs != null) {
        out[row.patientId] = LatestVisitFollowUpDecision(
          visitMs: visitMs,
          nextFollowUpMs: nfdMs,
        );
      }
    }

    return out;
  }
}

/// Result of [LatestVisitFollowUp.resolveDecisions] for one patient.
class LatestVisitFollowUpDecision {
  const LatestVisitFollowUpDecision({
    required this.visitMs,
    required this.nextFollowUpMs,
  });

  final int visitMs;
  final int? nextFollowUpMs;
}

/// Minimal row shape for [LatestVisitFollowUp.resolve].
class LatestVisitFollowUpRow {
  const LatestVisitFollowUpRow({
    required this.patientId,
    required this.visitDate,
    this.nextFollowUpDate,
  });

  final String patientId;
  final DateTime visitDate;
  final DateTime? nextFollowUpDate;
}
