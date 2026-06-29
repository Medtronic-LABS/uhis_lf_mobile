/// Data models for the AI visit briefing response.
class BriefingCardContent {
  const BriefingCardContent({required this.headline, required this.points});

  final String headline;
  final List<String> points;

  factory BriefingCardContent.fromJson(Map<String, dynamic> json) =>
      BriefingCardContent(
        headline: json['headline'] as String? ?? '',
        points: (json['points'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}

class ConversationSection {
  const ConversationSection({
    required this.topic,
    required this.icon,
    required this.questions,
  });

  final String topic;
  final String icon;
  final List<String> questions;

  factory ConversationSection.fromJson(Map<String, dynamic> json) =>
      ConversationSection(
        topic: json['topic'] as String? ?? '',
        icon: json['icon'] as String? ?? 'checkup',
        questions: (json['questions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}

class ConversationGuide {
  const ConversationGuide({
    required this.openingLine,
    required this.sections,
  });

  final String openingLine;
  final List<ConversationSection> sections;

  factory ConversationGuide.fromJson(Map<String, dynamic> json) =>
      ConversationGuide(
        openingLine: json['openingLine'] as String? ?? '',
        sections: (json['sections'] as List<dynamic>?)
                ?.map((e) =>
                    ConversationSection.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class VisitBriefingResponse {
  const VisitBriefingResponse({
    required this.briefingCard,
    required this.conversationGuide,
    required this.transitionPrompt,
  });

  final BriefingCardContent briefingCard;
  final ConversationGuide conversationGuide;
  final String transitionPrompt;

  factory VisitBriefingResponse.fromJson(Map<String, dynamic> json) =>
      VisitBriefingResponse(
        briefingCard: BriefingCardContent.fromJson(
            json['briefingCard'] as Map<String, dynamic>? ?? {}),
        conversationGuide: ConversationGuide.fromJson(
            json['conversationGuide'] as Map<String, dynamic>? ?? {}),
        transitionPrompt: json['transitionPrompt'] as String? ?? '',
      );
}
