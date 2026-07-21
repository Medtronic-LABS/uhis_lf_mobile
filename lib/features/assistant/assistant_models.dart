/// Data models for the conversational AI assistant feature.
library;

enum MessageRole { user, assistant }

/// Safe, fixed allowlist of actions the assistant may suggest. The LLM only
/// *selects* from this set — it never invents navigation. Every type maps to
/// an existing, reviewed app routine (see PatientAiSheet). Unknown wire values
/// fold to [none] so a future backend addition can't trigger a stray action.
enum AssistantActionType {
  startVisit,
  openReferral,
  scheduleFollowUp,
  callPatient,
  none;

  static AssistantActionType fromWire(String? tag) {
    switch ((tag ?? '').trim().toLowerCase()) {
      case 'start_visit':
      case 'startvisit':
        return AssistantActionType.startVisit;
      case 'open_referral':
      case 'refer':
        return AssistantActionType.openReferral;
      case 'schedule_followup':
      case 'schedule_follow_up':
        return AssistantActionType.scheduleFollowUp;
      case 'call_patient':
      case 'call':
        return AssistantActionType.callPatient;
      default:
        return AssistantActionType.none;
    }
  }
}

/// One suggested action rendered as a button under an assistant answer.
class AssistantAction {
  const AssistantAction({required this.type, required this.label});

  final AssistantActionType type;
  final String label;

  static AssistantAction? fromJson(Map<String, dynamic> j) {
    final type = AssistantActionType.fromWire(j['type'] as String?);
    if (type == AssistantActionType.none) return null;
    final label = (j['label'] as String?)?.trim();
    return AssistantAction(
      type: type,
      label: (label == null || label.isEmpty) ? defaultLabel(type) : label,
    );
  }

  static String defaultLabel(AssistantActionType t) {
    switch (t) {
      case AssistantActionType.startVisit:
        return 'Start visit';
      case AssistantActionType.openReferral:
        return 'Open referral';
      case AssistantActionType.scheduleFollowUp:
        return 'Schedule follow-up';
      case AssistantActionType.callPatient:
        return 'Call patient';
      case AssistantActionType.none:
        return '';
    }
  }
}

/// One module hit retrieved during a coaching RAG lookup.
class RagModuleHit {
  const RagModuleHit({
    required this.moduleId,
    required this.title,
    required this.domain,
  });

  final String moduleId;
  final String title;
  final String domain;
}

/// Source document cited in a coaching RAG answer.
class RagSourceAttribution {
  const RagSourceAttribution({
    required this.title,
    required this.sourceType,
    this.presignedUrl,
  });

  final String title;
  final String sourceType; // pdf | pptx | docx | audio | video
  final String? presignedUrl;
}

/// A parsed assistant reply — prose answer, optional actions, and RAG metadata.
class AssistantAnswer {
  const AssistantAnswer({
    required this.text,
    this.actions = const [],
    this.suggestedQuestions = const [],
    this.retrievedModules = const [],
    this.sourceDocuments = const [],
  });

  final String text;
  final List<AssistantAction> actions;

  /// Follow-up questions answerable from retrieved module content (coaching RAG).
  final List<String> suggestedQuestions;

  /// Modules retrieved by the RAG lookup (coaching RAG path only).
  final List<RagModuleHit> retrievedModules;

  /// Source documents cited in the answer (coaching RAG path only).
  final List<RagSourceAttribution> sourceDocuments;
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
    this.actions = const [],
    this.suggestedQuestions = const [],
  });

  final MessageRole role;
  final String text;
  final DateTime timestamp;

  /// Suggested actions attached to an assistant message (empty for user messages).
  final List<AssistantAction> actions;

  /// Follow-up questions surfaced by coaching RAG (empty for user messages and
  /// non-RAG replies).
  final List<String> suggestedQuestions;
}

class AssistantException implements Exception {
  const AssistantException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'AssistantException($statusCode): $message';
}
