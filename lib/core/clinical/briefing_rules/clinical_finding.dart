/// A single deterministically-computed clinical fact for the AI visit
/// briefing ("Before You Knock" card + siblings).
///
/// [ClinicalFinding]s are the ONLY facts the AI briefing service is allowed
/// to draw its headline/priorities/discussion-points from — the LLM selects,
/// prioritizes, and phrases from this list, never inventing its own clinical
/// observations. See `docs`/plan for the full per-programme rule table this
/// implements.
library;

class ClinicalFinding {
  const ClinicalFinding({
    required this.code,
    required this.message,
    required this.programme,
  });

  /// Stable identifier for this rule (e.g. `anc.dangerSign`,
  /// `ncd.bpAndGlucoseCombined`) — not shown to the user, useful for tests
  /// and for de-duplicating/tracing which rule produced a given message.
  final String code;

  /// The rendered, patient-facing message text for this finding — purely
  /// clinical content, never demographic (age/gender/name).
  final String message;

  /// Which programme produced this finding (`anc`, `pnc`, `pregnancyOutcome`,
  /// `childImmunization`, `ncd`).
  final String programme;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'programme': programme,
      };

  @override
  String toString() => 'ClinicalFinding($code: $message)';

  @override
  bool operator ==(Object other) =>
      other is ClinicalFinding &&
      other.code == code &&
      other.message == message &&
      other.programme == programme;

  @override
  int get hashCode => Object.hash(code, message, programme);
}
