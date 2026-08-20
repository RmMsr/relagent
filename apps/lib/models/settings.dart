import 'package:agentic_client/agentic_client.dart' show AuthType;
import 'package:flutter/foundation.dart' show kIsWeb;

export 'package:agentic_client/agentic_client.dart' show AuthType;

// Sentinel value for copyWith to distinguish "not provided" from "explicitly null"
const Object _unset = Object();

/// Platform-aware default engine base URL: empty on web (relative to origin),
/// localhost on native platforms.
String get _defaultEngineBaseUrl => kIsWeb ? '' : 'http://localhost:8000';

enum VoiceMode {
  silent, // Dictation mode, no auto-playback
  listening, // Continuous recording, no auto-playback
  conversation, // Continuous recording + auto-playback
  reading, // Dictation mode + auto-playback
}

enum ChatBackendType {
  openAiCompatible, // Any OpenAI-compatible API server
  relagentEngine, // Full-featured Relagent backend
}

enum BackgroundListeningDuration {
  fiveMinutes(Duration(minutes: 5)),
  fifteenMinutes(Duration(minutes: 15)),
  thirtyMinutes(Duration(minutes: 30)),
  oneHour(Duration(hours: 1)),
  twoHours(Duration(hours: 2)),
  threeHours(Duration(hours: 3)),
  sixHours(Duration(hours: 6)),
  twelveHours(Duration(hours: 12)),
  twentyFourHours(Duration(hours: 24));

  final Duration duration;
  const BackgroundListeningDuration(this.duration);

  String get displayName {
    switch (this) {
      case BackgroundListeningDuration.fiveMinutes:
        return '5 minutes';
      case BackgroundListeningDuration.fifteenMinutes:
        return '15 minutes';
      case BackgroundListeningDuration.thirtyMinutes:
        return '30 minutes';
      case BackgroundListeningDuration.oneHour:
        return '1 hour';
      case BackgroundListeningDuration.twoHours:
        return '2 hours';
      case BackgroundListeningDuration.threeHours:
        return '3 hours';
      case BackgroundListeningDuration.sixHours:
        return '6 hours';
      case BackgroundListeningDuration.twelveHours:
        return '12 hours';
      case BackgroundListeningDuration.twentyFourHours:
        return '24 hours';
    }
  }
}

class SettingsHistoryEntry {
  final String url;
  final String model;

  const SettingsHistoryEntry({required this.url, required this.model});

  Map<String, dynamic> toJson() {
    return {'url': url, 'model': model};
  }

  factory SettingsHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SettingsHistoryEntry(
      url: json['url'] as String,
      model: json['model'] as String,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsHistoryEntry &&
        other.url == url &&
        other.model == model;
  }

  @override
  int get hashCode => Object.hash(url, model);

  @override
  String toString() => '$url ($model)';
}

class EngineUrlEntry {
  final String url;
  final AuthType authType;
  final String? username;
  final bool hasApiKey;

  const EngineUrlEntry({
    required this.url,
    this.authType = AuthType.none,
    this.username,
    this.hasApiKey = false,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'authType': authType.name,
    if (username != null) 'username': username,
    if (hasApiKey) 'hasApiKey': true,
  };

  factory EngineUrlEntry.fromJson(Map<String, dynamic> json) {
    AuthType authType;
    if (json.containsKey('authType')) {
      authType = AuthType.values.firstWhere(
        (e) => e.name == json['authType'],
        orElse: () => AuthType.none,
      );
    } else {
      authType = AuthType.none;
    }
    return EngineUrlEntry(
      url: json['url'] as String,
      authType: authType,
      username: json['username'] as String?,
      hasApiKey: (json['hasApiKey'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EngineUrlEntry &&
        other.url == url &&
        other.authType == authType &&
        other.username == username &&
        other.hasApiKey == hasApiKey;
  }

  @override
  int get hashCode => Object.hash(url, authType, username, hasApiKey);
}

class Settings {
  // URL to an legacy OpenAI compatible API endpoint
  final String simpleChatBaseUrl;

  // Model name that is usable with the simple chat API endpoint
  final String simpleChatModel;

  // Initial prompt sent at the beginning of every chat session
  final String primeMessage;

  // TTS settings
  final int ttsSpeakerId;
  final double ttsSpeed;

  // Voice mode (replaces ttsAutoQueue)
  final VoiceMode voiceMode;

  // Background listening duration limit
  final BackgroundListeningDuration backgroundListeningDuration;

  // Authentication settings (for simple chat)
  final AuthType authType;
  final String? username; // For Basic Auth only

  // History of previously used URL/model combinations for autocomplete
  final List<SettingsHistoryEntry> history;

  // Engine settings (for agentic chat)
  final String engineBaseUrl;
  final AuthType engineAuthType;
  final String? engineUsername;
  final String? agenticSessionId;

  // History of previously used engine URLs with auth config for autocomplete
  final List<EngineUrlEntry> engineUrlHistory;

  // Selected chat backend type
  final ChatBackendType selectedBackend;

  // API key indicator fields (actual keys stored in secure storage)
  final bool engineHasApiKey;
  final bool simpleChatHasApiKey;
  // Continuous voice mode opt-in (experimental)
  final bool continuousVoiceEnabled;

  // Selected voice model IDs (null = no model selected)
  final String? selectedAsrModelId;
  final String? selectedTtsModelId;

  const Settings({
    required this.simpleChatBaseUrl,
    required this.simpleChatModel,
    required this.primeMessage,
    required this.ttsSpeakerId,
    required this.ttsSpeed,
    required this.voiceMode,
    required this.backgroundListeningDuration,
    required this.authType,
    this.username,
    this.history = const [],
    required this.engineBaseUrl,
    required this.engineAuthType,
    this.engineUsername,
    this.agenticSessionId,
    this.engineUrlHistory = const [],
    required this.selectedBackend,
    this.engineHasApiKey = false,
    this.simpleChatHasApiKey = false,
    this.continuousVoiceEnabled = false,
    this.selectedAsrModelId,
    this.selectedTtsModelId,
  });

  factory Settings.defaults() {
    return Settings(
      simpleChatBaseUrl: 'http://localhost:1234/api/v1',
      simpleChatModel: 'gpt-oss-20b-mxfp4-GGUF',
      primeMessage: _defaultPrimeMessage,
      ttsSpeakerId: 0,
      ttsSpeed: 1.0,
      voiceMode: VoiceMode.silent,
      backgroundListeningDuration: BackgroundListeningDuration.oneHour,
      authType: AuthType.none,
      username: null,
      engineBaseUrl: _defaultEngineBaseUrl,
      engineAuthType: AuthType.none,
      engineUsername: null,
      agenticSessionId: null,
      selectedBackend: ChatBackendType.relagentEngine,
      engineHasApiKey: false,
      simpleChatHasApiKey: false,
      continuousVoiceEnabled: false,
    );
  }

  Settings copyWith({
    String? simpleChatBaseUrl,
    String? simpleChatModel,
    String? primeMessage,
    int? ttsSpeakerId,
    double? ttsSpeed,
    VoiceMode? voiceMode,
    BackgroundListeningDuration? backgroundListeningDuration,
    AuthType? authType,
    String? username,
    List<SettingsHistoryEntry>? history,
    String? engineBaseUrl,
    AuthType? engineAuthType,
    String? engineUsername,
    Object? agenticSessionId = _unset,
    List<EngineUrlEntry>? engineUrlHistory,
    ChatBackendType? selectedBackend,
    bool? engineHasApiKey,
    bool? simpleChatHasApiKey,
    bool? continuousVoiceEnabled,
    Object? selectedAsrModelId = _unset,
    Object? selectedTtsModelId = _unset,
  }) {
    return Settings(
      simpleChatBaseUrl: simpleChatBaseUrl ?? this.simpleChatBaseUrl,
      simpleChatModel: simpleChatModel ?? this.simpleChatModel,
      primeMessage: primeMessage ?? this.primeMessage,
      ttsSpeakerId: ttsSpeakerId ?? this.ttsSpeakerId,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      voiceMode: voiceMode ?? this.voiceMode,
      backgroundListeningDuration:
          backgroundListeningDuration ?? this.backgroundListeningDuration,
      authType: authType ?? this.authType,
      username: username ?? this.username,
      history: history ?? this.history,
      engineBaseUrl: engineBaseUrl ?? this.engineBaseUrl,
      engineAuthType: engineAuthType ?? this.engineAuthType,
      engineUsername: engineUsername ?? this.engineUsername,
      agenticSessionId: agenticSessionId == _unset
          ? this.agenticSessionId
          : agenticSessionId as String?,
      engineUrlHistory: engineUrlHistory ?? this.engineUrlHistory,
      selectedBackend: selectedBackend ?? this.selectedBackend,
      engineHasApiKey: engineHasApiKey ?? this.engineHasApiKey,
      simpleChatHasApiKey: simpleChatHasApiKey ?? this.simpleChatHasApiKey,
      continuousVoiceEnabled:
          continuousVoiceEnabled ?? this.continuousVoiceEnabled,
      selectedAsrModelId: selectedAsrModelId == _unset
          ? this.selectedAsrModelId
          : selectedAsrModelId as String?,
      selectedTtsModelId: selectedTtsModelId == _unset
          ? this.selectedTtsModelId
          : selectedTtsModelId as String?,
    );
  }

  // Helper methods for voice mode checks
  bool get isAutoPlayback =>
      voiceMode == VoiceMode.conversation || voiceMode == VoiceMode.reading;

  bool get isContinuousRecording =>
      voiceMode == VoiceMode.listening || voiceMode == VoiceMode.conversation;

  Map<String, dynamic> toJson() {
    return {
      'simpleChatBaseUrl': simpleChatBaseUrl,
      'simpleChatModel': simpleChatModel,
      'primeMessage': primeMessage,
      'ttsSpeakerId': ttsSpeakerId,
      'ttsSpeed': ttsSpeed,
      'voiceMode': voiceMode.name,
      'backgroundListeningDuration': backgroundListeningDuration.name,
      'authType': authType.name,
      'username': username,
      'history': history.map((entry) => entry.toJson()).toList(),
      'engineBaseUrl': engineBaseUrl,
      'engineAuthType': engineAuthType.name,
      'engineUsername': engineUsername,
      'agenticSessionId': agenticSessionId,
      'engineUrlHistory': engineUrlHistory.map((e) => e.toJson()).toList(),
      'selectedBackend': selectedBackend.name,
      'engineHasApiKey': engineHasApiKey,
      'simpleChatHasApiKey': simpleChatHasApiKey,
      'continuousVoiceEnabled': continuousVoiceEnabled,
      'selectedAsrModelId': selectedAsrModelId,
      'selectedTtsModelId': selectedTtsModelId,
    };
  }

  factory Settings.fromJson(Map<String, dynamic> json) {
    // Migration: convert old ttsAutoQueue boolean to voiceMode
    VoiceMode mode;
    if (json.containsKey('voiceMode')) {
      final modeStr = json['voiceMode'] as String;
      mode = VoiceMode.values.firstWhere(
        (e) => e.name == modeStr,
        orElse: () => VoiceMode.silent,
      );
    } else if (json.containsKey('ttsAutoQueue')) {
      // Migrate from old boolean setting
      final autoQueue = json['ttsAutoQueue'] as bool;
      mode = autoQueue ? VoiceMode.conversation : VoiceMode.listening;
    } else {
      mode = VoiceMode.silent;
    }

    // Clamp continuous modes when toggle is off
    final continuousVoiceEnabled =
        (json['continuousVoiceEnabled'] as bool?) ?? false;
    if (!continuousVoiceEnabled &&
        (mode == VoiceMode.listening || mode == VoiceMode.conversation)) {
      mode = VoiceMode.silent;
    }

    // Parse backgroundListeningDuration
    BackgroundListeningDuration duration;
    if (json.containsKey('backgroundListeningDuration')) {
      final durationStr = json['backgroundListeningDuration'] as String;
      duration = BackgroundListeningDuration.values.firstWhere(
        (e) => e.name == durationStr,
        orElse: () => BackgroundListeningDuration.oneHour,
      );
    } else {
      duration = BackgroundListeningDuration.oneHour;
    }

    // Parse authType (defaults to none for existing settings)
    AuthType authType;
    if (json.containsKey('authType')) {
      final authTypeStr = json['authType'] as String;
      authType = AuthType.values.firstWhere(
        (e) => e.name == authTypeStr,
        orElse: () => AuthType.none,
      );
    } else {
      authType = AuthType.none;
    }

    // Parse history (defaults to empty list for existing settings)
    List<SettingsHistoryEntry> history = [];
    if (json.containsKey('history')) {
      final historyJson = json['history'] as List<dynamic>;
      history = historyJson
          .map(
            (item) =>
                SettingsHistoryEntry.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    }

    // Parse engine auth type (defaults to none for existing settings)
    AuthType engineAuthType;
    if (json.containsKey('engineAuthType')) {
      final engineAuthTypeStr = json['engineAuthType'] as String;
      engineAuthType = AuthType.values.firstWhere(
        (e) => e.name == engineAuthTypeStr,
        orElse: () => AuthType.none,
      );
    } else {
      engineAuthType = AuthType.none;
    }

    // Parse selectedBackend (defaults to relagentEngine for new installs)
    ChatBackendType selectedBackend;
    if (json.containsKey('selectedBackend')) {
      final backendStr = json['selectedBackend'] as String;
      selectedBackend = ChatBackendType.values.firstWhere(
        (e) => e.name == backendStr,
        orElse: () => ChatBackendType.relagentEngine,
      );
    } else {
      selectedBackend = ChatBackendType.relagentEngine;
    }

    return Settings(
      simpleChatBaseUrl: json['simpleChatBaseUrl'] as String,
      simpleChatModel: json['simpleChatModel'] as String,
      primeMessage: (json['primeMessage'] as String?) ?? _defaultPrimeMessage,
      ttsSpeakerId: (json['ttsSpeakerId'] as int?) ?? 0,
      ttsSpeed: (json['ttsSpeed'] as num?)?.toDouble() ?? 1.0,
      voiceMode: mode,
      backgroundListeningDuration: duration,
      authType: authType,
      username: json['username'] as String?,
      history: history,
      engineBaseUrl:
          (json['engineBaseUrl'] as String?) ?? _defaultEngineBaseUrl,
      engineAuthType: engineAuthType,
      engineUsername: json['engineUsername'] as String?,
      agenticSessionId: json['agenticSessionId'] as String?,
      engineUrlHistory: () {
        final raw = json['engineUrlHistory'] as List<dynamic>?;
        if (raw == null || raw.isEmpty) return const <EngineUrlEntry>[];
        if (raw.first is String) {
          return raw.cast<String>()
              .map((url) => EngineUrlEntry(url: url))
              .toList();
        }
        return raw.cast<Map<String, dynamic>>()
            .map((e) => EngineUrlEntry.fromJson(e))
            .toList();
      }(),
      selectedBackend: selectedBackend,
      engineHasApiKey: (json['engineHasApiKey'] as bool?) ?? false,
      simpleChatHasApiKey: (json['simpleChatHasApiKey'] as bool?) ?? false,
      continuousVoiceEnabled: continuousVoiceEnabled,
      selectedAsrModelId: json['selectedAsrModelId'] as String?,
      selectedTtsModelId: json['selectedTtsModelId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Settings &&
        other.simpleChatBaseUrl == simpleChatBaseUrl &&
        other.simpleChatModel == simpleChatModel &&
        other.primeMessage == primeMessage &&
        other.ttsSpeakerId == ttsSpeakerId &&
        other.ttsSpeed == ttsSpeed &&
        other.voiceMode == voiceMode &&
        other.backgroundListeningDuration == backgroundListeningDuration &&
        other.authType == authType &&
        other.username == username &&
        _listEquals(other.history, history) &&
        other.engineBaseUrl == engineBaseUrl &&
        other.engineAuthType == engineAuthType &&
        other.engineUsername == engineUsername &&
        other.agenticSessionId == agenticSessionId &&
        _listEquals(other.engineUrlHistory, engineUrlHistory) &&
        other.selectedBackend == selectedBackend &&
        other.engineHasApiKey == engineHasApiKey &&
        other.simpleChatHasApiKey == simpleChatHasApiKey &&
        other.continuousVoiceEnabled == continuousVoiceEnabled &&
        other.selectedAsrModelId == selectedAsrModelId &&
        other.selectedTtsModelId == selectedTtsModelId;
  }

  @override
  int get hashCode => Object.hash(
    Object.hash(
      simpleChatBaseUrl,
      simpleChatModel,
      primeMessage,
      ttsSpeakerId,
      ttsSpeed,
      voiceMode,
      backgroundListeningDuration,
      authType,
      username,
      Object.hashAll(history),
    ),
    Object.hash(
      engineBaseUrl,
      engineAuthType,
      engineUsername,
      agenticSessionId,
      Object.hashAll(engineUrlHistory),
      selectedBackend,
      engineHasApiKey,
      simpleChatHasApiKey,
      continuousVoiceEnabled,
      selectedAsrModelId,
      selectedTtsModelId,
    ),
  );

  // Helper for list equality
  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

const _defaultPrimeMessage = '''
Hi, you are assisting me in daily tasks. Please answer quick and brief in 1-3
sentences unless otherwise specified. Feel free to ask back in order to give
quality answers. Be transparent if you are unsure or need clarification.
''';
