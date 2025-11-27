enum VoiceMode {
  silent,       // One-shot recording, no auto-playback
  listening,    // Continuous recording, no auto-playback
  conversation, // Continuous recording + auto-playback
  reading,      // One-shot recording + auto-playback
}

class Settings {
  // URL to an legacy OpenAI compatible API endpoint
  final String simpleChatBaseUrl;

  // Model name that is usable with the simple chat API endpoint
  final String simpleChatModel;

  // TTS settings
  final int ttsSpeakerId;
  final double ttsSpeed;

  // Voice mode (replaces ttsAutoQueue)
  final VoiceMode voiceMode;

  const Settings({
    required this.simpleChatBaseUrl,
    required this.simpleChatModel,
    required this.ttsSpeakerId,
    required this.ttsSpeed,
    required this.voiceMode,
  });

  factory Settings.defaults() {
    return const Settings(
      simpleChatBaseUrl: 'http://localhost:1234/api/v1',
      simpleChatModel: 'gpt-oss-20b-mxfp4-GGUF',
      ttsSpeakerId: 0,
      ttsSpeed: 1.0,
      voiceMode: VoiceMode.conversation, // Conversation mode by default
    );
  }

  Settings copyWith({
    String? simpleChatBaseUrl,
    String? simpleChatModel,
    int? ttsSpeakerId,
    double? ttsSpeed,
    VoiceMode? voiceMode,
  }) {
    return Settings(
      simpleChatBaseUrl: simpleChatBaseUrl ?? this.simpleChatBaseUrl,
      simpleChatModel: simpleChatModel ?? this.simpleChatModel,
      ttsSpeakerId: ttsSpeakerId ?? this.ttsSpeakerId,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      voiceMode: voiceMode ?? this.voiceMode,
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
      'ttsSpeakerId': ttsSpeakerId,
      'ttsSpeed': ttsSpeed,
      'voiceMode': voiceMode.name,
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

    return Settings(
      simpleChatBaseUrl: json['simpleChatBaseUrl'] as String,
      simpleChatModel: json['simpleChatModel'] as String,
      ttsSpeakerId: (json['ttsSpeakerId'] as int?) ?? 0,
      ttsSpeed: (json['ttsSpeed'] as num?)?.toDouble() ?? 1.0,
      voiceMode: mode,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Settings &&
        other.simpleChatBaseUrl == simpleChatBaseUrl &&
        other.simpleChatModel == simpleChatModel &&
        other.ttsSpeakerId == ttsSpeakerId &&
        other.ttsSpeed == ttsSpeed &&
        other.voiceMode == voiceMode;
  }

  @override
  int get hashCode => Object.hash(
        simpleChatBaseUrl,
        simpleChatModel,
        ttsSpeakerId,
        ttsSpeed,
        voiceMode,
      );
}
