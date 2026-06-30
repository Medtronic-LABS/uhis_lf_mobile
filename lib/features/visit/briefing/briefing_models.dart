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

/// AI-generated greeting card content. All three fields may be empty when
/// the upstream API omits them — the screen falls back to the localized
/// static greeting in that case.
class GreetingContent {
  const GreetingContent({
    required this.bangla,
    required this.english,
    required this.hint,
  });

  final String bangla;
  final String english;
  final String hint;

  static const GreetingContent empty =
      GreetingContent(bangla: '', english: '', hint: '');

  bool get isEmpty =>
      bangla.trim().isEmpty &&
      english.trim().isEmpty &&
      hint.trim().isEmpty;

  factory GreetingContent.fromJson(Map<String, dynamic> json) =>
      GreetingContent(
        bangla: (json['bangla'] as String?)?.trim() ?? '',
        english: (json['english'] as String?)?.trim() ?? '',
        hint: (json['hint'] as String?)?.trim() ?? '',
      );
}

class VisitBriefingResponse {
  const VisitBriefingResponse({
    required this.briefingCard,
    required this.suggestedDiscussionPoints,
    required this.greeting,
    required this.transitionPrompt,
  });

  final BriefingCardContent briefingCard;
  final SuggestedDiscussionPoints suggestedDiscussionPoints;
  final GreetingContent greeting;
  final String transitionPrompt;

  factory VisitBriefingResponse.fromJson(Map<String, dynamic> json) =>
      VisitBriefingResponse(
        briefingCard: BriefingCardContent.fromJson(
            json['briefingCard'] as Map<String, dynamic>? ?? {}),
        suggestedDiscussionPoints: SuggestedDiscussionPoints.fromJson(
            json['suggestedDiscussionPoints'] as Map<String, dynamic>? ?? {}),
        greeting: GreetingContent.fromJson(
            json['greeting'] as Map<String, dynamic>? ?? const {}),
        transitionPrompt: json['transitionPrompt'] as String? ?? '',
      );
}
