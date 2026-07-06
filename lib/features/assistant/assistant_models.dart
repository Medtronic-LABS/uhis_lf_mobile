/// Data models for the conversational AI assistant feature.
library;

enum MessageRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
  });

  final MessageRole role;
  final String text;
  final DateTime timestamp;
}

class AssistantException implements Exception {
  const AssistantException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'AssistantException($statusCode): $message';
}
