class Settings {
  final String chatBaseUrl;
  final String chatModel;

  const Settings({
    required this.chatBaseUrl,
    required this.chatModel,
  });

  factory Settings.defaults() {
    return const Settings(
      chatBaseUrl: 'http://localhost:1234/v1',
      chatModel: 'qwen2.5-coder:7b',
    );
  }

  Settings copyWith({
    String? chatBaseUrl,
    String? chatModel,
  }) {
    return Settings(
      chatBaseUrl: chatBaseUrl ?? this.chatBaseUrl,
      chatModel: chatModel ?? this.chatModel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chatBaseUrl': chatBaseUrl,
      'chatModel': chatModel,
    };
  }

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      chatBaseUrl: json['chatBaseUrl'] as String,
      chatModel: json['chatModel'] as String,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Settings &&
        other.chatBaseUrl == chatBaseUrl &&
        other.chatModel == chatModel;
  }

  @override
  int get hashCode => Object.hash(chatBaseUrl, chatModel);
}
