import 'dart:math';

import '/agentic/models.dart';

enum ChatRole { user, assistant, error }

enum PendingAssistantState { waiting, delayed, error }

/// Generate a random 8-character hexadecimal message ID
/// Format: lowercase hex (e.g., "a3f7e2b9")
/// Uniqueness: 2^32 = 4,294,967,296 combinations
String generateMessageId() {
  final random = Random();
  final bytes = List<int>.generate(4, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class ChatMessage {
  final String id;
  final String text;
  final ChatRole role;
  final String? technicalDetails;
  final AgentStats? stats;
  late final DateTime timestamp;

  ChatMessage(
    this.text, {
    String? id,
    this.role = ChatRole.assistant,
    this.technicalDetails,
    this.stats,
    DateTime? timestamp,
  }) : id = id ?? generateMessageId(),
       timestamp = timestamp ?? DateTime.now().toUtc();

  // Factory for creating error messages
  factory ChatMessage.error(String errorText, {String? technicalDetails}) {
    return ChatMessage(
      errorText,
      role: ChatRole.error,
      technicalDetails: technicalDetails,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      json['content'].toString(),
      role: ChatRole.values.byName(json['role']),
      technicalDetails: json['technicalDetails']?.toString(),
    );
  }

  ChatMessage copyWith({
    String? id,
    String? text,
    ChatRole? role,
    AgentStats? stats,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      text ?? this.text,
      id: id ?? this.id,
      role: role ?? this.role,
      stats: stats ?? this.stats,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return ('${role.name}: $text');
  }
}
