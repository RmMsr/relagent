class Settings {
  // URL to an legacy OpenAI compatible API endpoint
  final String simpleChatBaseUrl;

  // Model name that is usable with the simple chat API endpoint
  final String simpleChatModel;

  const Settings({
    required this.simpleChatBaseUrl,
    required this.simpleChatModel,
  });

  factory Settings.defaults() {
    return const Settings(
      simpleChatBaseUrl: 'http://localhost:1234/api/v1',
      simpleChatModel: 'gpt-oss-20b-mxfp4-GGUF',
    );
  }

  Settings copyWith({String? simpleChatBaseUrl, String? simpleChatModel}) {
    return Settings(
      simpleChatBaseUrl: simpleChatBaseUrl ?? this.simpleChatBaseUrl,
      simpleChatModel: simpleChatModel ?? this.simpleChatModel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'simpleChatBaseUrl': simpleChatBaseUrl,
      'simpleChatModel': simpleChatModel,
    };
  }

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      simpleChatBaseUrl: json['simpleChatBaseUrl'] as String,
      simpleChatModel: json['simpleChatModel'] as String,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Settings &&
        other.simpleChatBaseUrl == simpleChatBaseUrl &&
        other.simpleChatModel == simpleChatModel;
  }

  @override
  int get hashCode => Object.hash(simpleChatBaseUrl, simpleChatModel);
}
