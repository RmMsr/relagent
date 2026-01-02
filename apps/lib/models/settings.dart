enum VoiceMode {
  silent, // One-shot recording, no auto-playback
  listening, // Continuous recording, no auto-playback
  conversation, // Continuous recording + auto-playback
  reading, // One-shot recording + auto-playback
}

enum AuthType {
  none, // No authentication required
  basic, // HTTP Basic authentication
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

  // Authentication settings
  final AuthType authType;
  final String? username; // For Basic Auth only

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
  });

  factory Settings.defaults() {
    return const Settings(
      simpleChatBaseUrl: 'http://localhost:1234/api/v1',
      simpleChatModel: 'gpt-oss-20b-mxfp4-GGUF',
      primeMessage: _defaultPrimeMessage,
      ttsSpeakerId: 0,
      ttsSpeed: 1.0,
      voiceMode: VoiceMode.conversation, // Conversation mode by default
      backgroundListeningDuration: BackgroundListeningDuration.oneHour,
      authType: AuthType.none,
      username: null,
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
    };
  }

  factory Settings.fromJson(Map<String, dynamic> json) {
    // Migration: convert old ttsAutoQueue boolean to voiceMode
    VoiceMode mode;
    if (json.containsKey('voiceMode')) {
      final modeStr = json['voiceMode'] as String;
      mode = VoiceMode.values.firstWhere(
        (e) => e.name == modeStr,
        orElse: () => VoiceMode.conversation,
      );
    } else if (json.containsKey('ttsAutoQueue')) {
      // Migrate from old boolean setting
      final autoQueue = json['ttsAutoQueue'] as bool;
      mode = autoQueue ? VoiceMode.conversation : VoiceMode.listening;
    } else {
      mode = VoiceMode.conversation;
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
        other.username == username;
  }

  @override
  int get hashCode => Object.hash(
    simpleChatBaseUrl,
    simpleChatModel,
    primeMessage,
    ttsSpeakerId,
    ttsSpeed,
    voiceMode,
    backgroundListeningDuration,
    authType,
    username,
  );
}

const _defaultPrimeMessage = '''
Hi, you can call me Jane. We communicate via audio. Please expect some
spelling problems, incomplete messages or repetition. Often this is due to
text recognition or connection errors. Please assume repetition of content
from the last message is not needed.

Example: The video game name "Zelda" might be falsely recognized as "sel da"
or "cell da". Still you should be able to figure out what was actually meant.

Example: You receive a simple "?" or just words that does not form a sentence
or choice in the current context like "green" or "when I". Then just ignore it
or let me know you got an incomplete message.

You are assisting me in daily tasks. Please answer quick and brief in 1-3
sentences unless otherwise specified. Feel free to ask back in order to give
quality answers. Be transparent if you are unsure or need clarification.

Example: You recognize I am asking about snow cat. Before telling me much about
the animal, ask me if I want to learn more about the animal. Maybe I meant the
transportation vehicle instead. Be mindfull of the time it takes to listen to
the wrong answer.
''';
