enum AgenticRole { user, assistant, error }

class AgentStats {
  final String? agentName;
  final String? answeringModelName;
  final double? durationSeconds;
  final int? inputTokens;
  final int? outputTokens;
  final int? requestsCount;
  final int? toolCallsCount;

  const AgentStats({
    this.agentName,
    this.answeringModelName,
    this.durationSeconds,
    this.inputTokens,
    this.outputTokens,
    this.requestsCount,
    this.toolCallsCount,
  });

  factory AgentStats.fromJson(Map<String, dynamic> json) {
    return AgentStats(
      agentName: json['agent_name'] as String?,
      answeringModelName: json['answering_model_name'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      inputTokens: json['input_tokens'] as int?,
      outputTokens: json['output_tokens'] as int?,
      requestsCount: json['requests_count'] as int?,
      toolCallsCount: json['tool_calls_count'] as int?,
    );
  }

  bool get hasData =>
      inputTokens != null ||
      outputTokens != null ||
      toolCallsCount != null ||
      durationSeconds != null;
}

class AgenticMessage {
  final String id;
  final String text;
  final AgenticRole role;
  final DateTime timestamp;
  final String? technicalDetails;
  final String? sessionId; // Returned by engine, used to track conversation
  final AgentStats? stats; // Stats from engine response

  AgenticMessage({
    required this.id,
    required this.text,
    required this.role,
    DateTime? timestamp,
    this.technicalDetails,
    this.sessionId,
    this.stats,
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

    AgentStats? stats;
    if (json['stats'] != null) {
      stats = AgentStats.fromJson(json['stats'] as Map<String, dynamic>);
    }

    return AgenticMessage(
      id: json['id'] as String? ?? _generateId(),
      text: json['content'] as String,
      role: role,
      timestamp: timestamp,
      sessionId: json['session_id'] as String?,
      stats: stats,
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
