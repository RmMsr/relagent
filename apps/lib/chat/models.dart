enum ChatRole { user, assistant, error }

class ChatMessage {
  final String text;
  final ChatRole role;
  late final DateTime timestamp;

  ChatMessage(
    this.text, {
    this.role = ChatRole.assistant,
    DateTime? timestamp,
  }) {
    this.timestamp = timestamp ?? DateTime.now();
  }

  // Factory for creating error messages
  factory ChatMessage.error(String errorText) {
    return ChatMessage(
      errorText,
      role: ChatRole.error,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      json['content'].toString(),
      role: ChatRole.values.byName(json['role']),
    );
  }

  @override
  String toString() {
    return ('${role.name}: $text');
  }
}
