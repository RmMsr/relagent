enum AgenticRole { user, assistant, error }

class AgenticMessage {
  final String id;
  final String text;
  final AgenticRole role;
  final DateTime timestamp;
  final String? technicalDetails;
  final String? sessionId; // Returned by engine, used to track conversation

  AgenticMessage({
    required this.id,
    required this.text,
    required this.role,
    DateTime? timestamp,
    this.technicalDetails,
    this.sessionId,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AgenticMessage.user(String text) {
    return AgenticMessage(
      id: _generateId(),
      text: text,
      role: AgenticRole.user,
    );
  }

  factory AgenticMessage.assistant(String text) {
    return AgenticMessage(
      id: _generateId(),
      text: text,
      role: AgenticRole.assistant,
    );
  }

  factory AgenticMessage.error(String text, {String? technicalDetails}) {
    return AgenticMessage(
      id: _generateId(),
      text: text,
      role: AgenticRole.error,
      technicalDetails: technicalDetails,
    );
  }

  factory AgenticMessage.fromJson(Map<String, dynamic> json) {
    final roleStr = json['role'] as String;
    AgenticRole role;
    switch (roleStr) {
      case 'user':
        role = AgenticRole.user;
      case 'assistant':
        role = AgenticRole.assistant;
      default:
        role = AgenticRole.assistant;
    }

    DateTime? timestamp;
    if (json['timestamp'] != null) {
      timestamp = DateTime.tryParse(json['timestamp'] as String);
    }

    return AgenticMessage(
      id: json['id'] as String? ?? _generateId(),
      text: json['content'] as String,
      role: role,
      timestamp: timestamp,
      sessionId: json['session_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': text,
      'role': role.name,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  }
}
