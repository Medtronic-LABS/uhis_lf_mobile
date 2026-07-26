import '../../../core/debug/console_log.dart';
import '../../training/offline_llm_service.dart';
import 'briefing_models.dart';

/// Generates a minimal offline visit briefing using Gemma 270M on-device.
///
/// Only populates [VisitBriefingResponse.briefingCard] (2-sentence headline).
/// All other fields are empty — graceful degradation is handled by the UI.
class OfflineBriefingService {
  const OfflineBriefingService(this._llm);
  final OfflineLlmService _llm;

  static const int _maxContextChars = 800;

  Future<String> summary(Map<String, dynamic> ctx) async {
    final prompt = _buildSummaryPrompt(ctx);
    ConsoleLog.step('[OfflineBriefingService] generating offline summary');
    try {
      final raw = await _llm.ask(prompt);
      final text = raw
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('Summary:', '')
          .trim();
      return text.isEmpty ? _fallbackSummary(ctx) : text;
    } on OfflineLlmException catch (e) {
      ConsoleLog.warn('[OfflineBriefingService] Gemma failed: $e');
      return _fallbackSummary(ctx);
    }
  }

  Future<VisitBriefingResponse> generate(Map<String, dynamic> ctx) async {
    final headline = await summary(ctx);
    return VisitBriefingResponse(
      briefingCard: BriefingCardContent(headline: headline, points: const []),
      suggestedDiscussionPoints:
          const SuggestedDiscussionPoints(openingLine: '', sections: []),
      greeting: GreetingContent.empty,
      transitionPrompt: '',
    );
  }

  String _buildSummaryPrompt(Map<String, dynamic> ctx) {
    final name = ctx['patientName'] as String? ?? 'Patient';
    final age = ctx['ageYears']?.toString() ?? '';
    final gender = ctx['gender'] as String? ?? '';
    final programmes =
        (ctx['activeProgrammes'] as List<dynamic>?)?.join(', ') ?? '';
    final vitals = ctx['recentVitals']?.toString() ?? '';
    final followups = ctx['openFollowUps']?.toString() ?? '';
    final risk = ctx['riskIndicators']?.toString() ?? '';

    final raw = 'Patient: $name${age.isNotEmpty ? ", ${age}yo" : ""}'
        '${gender.isNotEmpty ? " $gender" : ""}. '
        'Programmes: $programmes. '
        'Vitals: $vitals. '
        'Follow-ups: $followups. '
        'Risk: $risk.';

    final context =
        raw.length > _maxContextChars ? raw.substring(0, _maxContextChars) : raw;

    return 'You are a clinical assistant for a community health worker in Bangladesh. '
        'Write 2 sentences summarizing this patient. Mention the most important clinical concern first. '
        'Plain English only.\n\n$context\n\nSummary:';
  }

  String _fallbackSummary(Map<String, dynamic> ctx) {
    final name = ctx['patientName'] as String? ?? 'Patient';
    final programmes =
        (ctx['activeProgrammes'] as List<dynamic>?)?.join(', ') ?? '';
    return '$name is enrolled in $programmes. '
        'Review vitals and follow-up history during this visit.';
  }
}
