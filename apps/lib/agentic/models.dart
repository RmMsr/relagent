import 'dart:math';

import 'package:flutter/material.dart';

enum AgenticRole { user, assistant, system, error }

enum SensitivityLevel {
  openInformation(
    1,
    'Open Information',
    'O',
    Colors.green,
    'Public information. No strong personal relevance, information could be related to anyone',
  ),
  specific(
    2,
    'Specific',
    'S',
    Colors.teal,
    'Information is relevant to a group, but does not include personally identifiable information',
  ),
  personal(
    3,
    'Personal',
    'P',
    Colors.orange,
    'May contain information identifying one person',
  ),
  confidential(
    4,
    'Confidential',
    'C',
    Colors.deepOrange,
    'Clearly sensitive information',
  ),
  internal(
    5,
    'Internal',
    'I',
    Colors.red,
    'Data not meant to be shared',
  );

  final int value;
  final String label;
  final String shortLabel;
  final Color color;
  final String description;

  const SensitivityLevel(
    this.value,
    this.label,
    this.shortLabel,
    this.color,
    this.description,
  );

  static SensitivityLevel fromValue(int value) {
    return SensitivityLevel.values.firstWhere(
      (l) => l.value == value,
      orElse: () => SensitivityLevel.personal,
    );
  }

  static SensitivityLevel fromName(String name) {
    // Handles engine enum names like "OpenInformation", "Specific", etc.
    final normalized = name.toLowerCase().replaceAll('_', '');
    for (final level in SensitivityLevel.values) {
      if (level.name.toLowerCase() == normalized) return level;
    }
    return SensitivityLevel.personal;
  }
}

enum ApprovalType {
  none('none'),
  outgoingData('data/out');

  final String value;

  const ApprovalType(this.value);

  static ApprovalType fromValue(String value) {
    return ApprovalType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => ApprovalType.none,
    );
  }
}

enum ApprovalResolution { pending, granted, declined, stale }

class ApprovalData {
  final String id;
  final ApprovalType type;
  final String? component;
  final String purpose;
  final Map<String, dynamic> allowedParameters;
  final SensitivityLevel sensitivity;
  final bool granted;
  final DateTime? expiresAt;
  final String? note;
  final ApprovalResolution resolution;

  ApprovalData({
    required this.id,
    required this.type,
    this.component,
    required this.purpose,
    this.allowedParameters = const {},
    this.sensitivity = SensitivityLevel.openInformation,
    this.granted = false,
    this.expiresAt,
    this.note,
    this.resolution = ApprovalResolution.pending,
  });

  ApprovalData copyWith({ApprovalResolution? resolution, DateTime? expiresAt}) {
    return ApprovalData(
      id: id,
      type: type,
      component: component,
      purpose: purpose,
      allowedParameters: allowedParameters,
      sensitivity: sensitivity,
      granted: granted,
      expiresAt: expiresAt ?? this.expiresAt,
      note: note,
      resolution: resolution ?? this.resolution,
    );
  }

  factory ApprovalData.fromJson(Map<String, dynamic> json) {
    return ApprovalData(
      id: json['id'] as String,
      type: ApprovalType.fromValue(json['type'] as String? ?? 'none'),
      component: json['component'] as String?,
      purpose: json['purpose'] as String? ?? '',
      allowedParameters:
          (json['allowed_parameters'] as Map<String, dynamic>?) ?? {},
      sensitivity: json['sensitivity'] is int
          ? SensitivityLevel.fromValue(json['sensitivity'] as int)
          : SensitivityLevel.fromName(json['sensitivity'] as String? ?? ''),
      granted: json['granted'] as bool? ?? false,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      note: json['note'] as String?,
      resolution: switch (json['granted'] as bool?) {
        true => ApprovalResolution.granted,
        false => ApprovalResolution.declined,
        null => ApprovalResolution.pending,
      },
    );
  }
}

class GrantRequest {
  final ApprovalType approvalType;
  final String? component;
  /// Parameters constrained to specific values. The wildcarded parameter key,
  /// if any, is excluded from this map and placed in [wildcardParameter].
  final Map<String, dynamic> allowedParameters;
  /// When non-null, this parameter key may have any value at execution time.
  /// Only one parameter may be wildcarded per grant.
  final String? wildcardParameter;
  final SensitivityLevel maxSensitivity;
  final DateTime? expiresAt;

  const GrantRequest({
    required this.approvalType,
    this.component,
    this.allowedParameters = const {},
    this.wildcardParameter,
    this.maxSensitivity = SensitivityLevel.openInformation,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'approval_type': approvalType.value,
      if (component != null) 'component': component,
      'allowed_parameters': allowedParameters,
      if (wildcardParameter != null) 'wildcard_parameter': wildcardParameter,
      'max_sensitivity': maxSensitivity.value,
      if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
    };
  }

  factory GrantRequest.fromApproval(
    ApprovalData approval, {
    required SensitivityLevel maxSensitivity,
    String? wildcardParameter,
    DateTime? expiresAt,
  }) {
    // Remove the wildcarded key from allowed_parameters — engine expects it
    // absent from the map and named separately in wildcard_parameter.
    final params = wildcardParameter != null
        ? (Map<String, dynamic>.from(approval.allowedParameters)
            ..remove(wildcardParameter))
        : approval.allowedParameters;
    return GrantRequest(
      approvalType: approval.type,
      component: approval.component,
      allowedParameters: params,
      wildcardParameter: wildcardParameter,
      maxSensitivity: maxSensitivity,
      expiresAt: expiresAt,
    );
  }
}

class SessionInfo {
  final String sessionId;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SessionInfo({
    required this.sessionId,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      sessionId: json['session_id'] as String,
      title: json['title'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

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
  final String messageId; // Non-nullable UUID: generated locally or read from engine
  final String localId; // Internal ID for UI tracking (TTS, etc.)
  final String text;
  final AgenticRole role;
  final DateTime timestamp;
  final String? technicalDetails;
  final String? sessionId; // Returned by engine, used to track conversation
  final AgentStats? stats; // Stats from engine response
  final List<ApprovalData>? approvals; // SystemAction approvals
  final String? notification; // SystemAction notification
  final SensitivityLevel? sensitivityLevel; // From ChatResponse or approval
  final bool isStale; // Marks invalidated approval groups
  /// True once the cycle this message belongs to has settled — settled
  /// messages are immutable and SHALL NOT be overwritten on incremental
  /// refresh. Mirrors the engine's universal `final` flag.
  final bool isFinal;

  AgenticMessage({
    required this.messageId,
    required this.localId,
    required this.text,
    required this.role,
    DateTime? timestamp,
    this.technicalDetails,
    this.sessionId,
    this.stats,
    this.approvals,
    this.notification,
    this.sensitivityLevel,
    this.isStale = false,
    this.isFinal = false,
  }) : timestamp = timestamp ?? DateTime.now();

  AgenticMessage copyWith({
    bool? isStale,
    List<ApprovalData>? approvals,
    bool? isFinal,
  }) {
    return AgenticMessage(
      messageId: messageId,
      localId: localId,
      text: text,
      role: role,
      timestamp: timestamp,
      technicalDetails: technicalDetails,
      sessionId: sessionId,
      stats: stats,
      approvals: approvals ?? this.approvals,
      notification: notification,
      sensitivityLevel: sensitivityLevel,
      isStale: isStale ?? this.isStale,
      isFinal: isFinal ?? this.isFinal,
    );
  }

  factory AgenticMessage.user(String text) {
    return AgenticMessage(
      messageId: _generateUuid(),
      localId: _generateLocalId(),
      text: text,
      role: AgenticRole.user,
    );
  }

  factory AgenticMessage.assistant(String text) {
    return AgenticMessage(
      messageId: _generateUuid(),
      localId: _generateLocalId(),
      text: text,
      role: AgenticRole.assistant,
      isFinal: true,
    );
  }

  factory AgenticMessage.error(String text, {String? technicalDetails}) {
    return AgenticMessage(
      messageId: _generateUuid(),
      localId: _generateLocalId(),
      text: text,
      role: AgenticRole.error,
      technicalDetails: technicalDetails,
      isFinal: true,
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
      case 'system':
        role = AgenticRole.system;
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

    // Parse SystemAction fields for system role
    List<ApprovalData>? approvals;
    String? notification;
    if (role == AgenticRole.system) {
      if (json['approvals'] is List) {
        approvals = (json['approvals'] as List)
            .map((a) => ApprovalData.fromJson(a as Map<String, dynamic>))
            .toList();
      }
      notification = json['notification'] as String?;
    }

    // System messages may not have 'content', use notification as fallback text
    final text = json['content'] as String? ??
        notification ??
        (role == AgenticRole.system ? '' : '');

    return AgenticMessage(
      messageId: json['message_id'] as String? ?? _generateUuid(),
      localId: _generateLocalId(),
      text: text,
      role: role,
      timestamp: timestamp,
      sessionId: json['session_id'] as String?,
      stats: stats,
      approvals: approvals,
      notification: notification,
      // Engine omits `final` for pre-cutover records; assume settled.
      isFinal: json['final'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'content': text,
      'role': role.name,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static int _localIdCounter = 0;

  static String _generateLocalId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final counter = (_localIdCounter++).toRadixString(36);
    return '$timestamp-$counter';
  }

  static final _rng = Random.secure();

  static String _generateUuid() {
    final bytes = List.generate(16, (_) => _rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
