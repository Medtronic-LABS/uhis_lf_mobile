import 'console_log.dart';

/// Structured, PHI-safe diagnostic events for the realtime AI Scribe (ASR)
/// pipeline — client-side only, diagnosis, not behavior.
///
/// Single chokepoint so every ASR diagnostic line has the same shape:
/// `[AsrDiag] EVENT_NAME encounter_id=... timestamp=... key=value ...`,
/// correlatable across the whole pipeline by the visit's existing
/// `encounterId` (no separate session id is introduced).
///
/// Callers are responsible for never passing transcript text, patient
/// values, form field values, tokens, or auth headers in [fields] — this
/// class does not (and cannot reliably) scrub content, it only formats
/// whatever it is given. Every call site in this codebase passes only
/// counters, durations, states, booleans, and coarse category strings.
abstract final class AsrDiagnostics {
  AsrDiagnostics._();

  static void event(
    String name, {
    required String? encounterId,
    Map<String, Object?> fields = const {},
  }) {
    final buffer = StringBuffer('[AsrDiag] $name')
      ..write(' encounter_id=${encounterId ?? "unknown"}')
      ..write(' timestamp=${DateTime.now().toIso8601String()}');
    for (final entry in fields.entries) {
      buffer.write(' ${entry.key}=${entry.value}');
    }
    ConsoleLog.step(buffer.toString());
  }
}
