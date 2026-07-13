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

/// A parsed assistant reply — the prose answer plus any suggested actions.
class AssistantAnswer {
  const AssistantAnswer({required this.text, this.actions = const []});

  final String text;
  final List<AssistantAction> actions;
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
    this.actions = const [],
  });

  final MessageRole role;
  final String text;
  final DateTime timestamp;

  /// Suggested actions attached to an assistant message (empty for user
  /// messages).
  final List<AssistantAction> actions;
}

class AssistantException implements Exception {
  const AssistantException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'AssistantException($statusCode): $message';
}
