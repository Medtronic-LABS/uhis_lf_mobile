/// One detected symptom code from a client-vocab-constrained `"symptoms"`
/// reply — see [RealtimeSymptomCodes].
class RealtimeSymptomHit {
  const RealtimeSymptomHit({required this.confidence, this.sourceSegment});

  final double confidence;
  final String? sourceSegment;

  factory RealtimeSymptomHit.fromJson(Map<String, dynamic> j) =>
      RealtimeSymptomHit(
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
        sourceSegment: j['sourceSegment'] as String?,
      );
}

/// Mirrors ai-scribe-service's `run_triage_inference` output shape — the
/// `data` payload of a `{"type": "symptoms", ...}` message on
/// `/scribe/realtime/transcribe` when the session was started with a
/// `symptomVocab`. Every key is guaranteed to be one of the codes this
/// client itself sent — the backend never invents a code outside that list.
///
/// This replaces [RealtimeClinicalFields]/`ChiefComplaintMatcher` for
/// sessions that supply a vocabulary: the server already returns codes with
/// real per-code confidence, so no client-side free-text keyword matching is
/// needed for those sessions.
class RealtimeSymptomCodes {
  const RealtimeSymptomCodes(this.hits);

  final Map<String, RealtimeSymptomHit> hits;

  factory RealtimeSymptomCodes.fromJson(Map<String, dynamic> j) =>
      RealtimeSymptomCodes({
        for (final entry in j.entries)
          entry.key: RealtimeSymptomHit.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          ),
      });

  bool get isEmpty => hits.isEmpty;

  /// Codes at or above [minConfidence] (default matches
  /// `AppConfig.scribeSymptomConfidenceFloor`'s default of 0.7 — callers
  /// should generally pass that value explicitly rather than rely on this
  /// default, so an env-var override actually takes effect).
  List<String> codesAbove(double minConfidence) => [
        for (final entry in hits.entries)
          if (entry.value.confidence >= minConfidence) entry.key,
      ];
}
