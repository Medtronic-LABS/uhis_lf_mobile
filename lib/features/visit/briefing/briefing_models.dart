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

class SuggestedDiscussionPoints {
  const SuggestedDiscussionPoints({
    required this.openingLine,
    required this.sections,
  });

  final String openingLine;
  final List<ConversationSection> sections;

  factory SuggestedDiscussionPoints.fromJson(Map<String, dynamic> json) =>
      SuggestedDiscussionPoints(
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
    required this.suggestedDiscussionPoints,
    required this.transitionPrompt,
  });

  final BriefingCardContent briefingCard;
  final SuggestedDiscussionPoints suggestedDiscussionPoints;
  final String transitionPrompt;

  factory VisitBriefingResponse.fromJson(Map<String, dynamic> json) =>
      VisitBriefingResponse(
        briefingCard: BriefingCardContent.fromJson(
            json['briefingCard'] as Map<String, dynamic>? ?? {}),
        suggestedDiscussionPoints: SuggestedDiscussionPoints.fromJson(
            json['suggestedDiscussionPoints'] as Map<String, dynamic>? ?? {}),
        transitionPrompt: json['transitionPrompt'] as String? ?? '',
      );
}
