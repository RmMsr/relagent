import '/models/model_catalog.dart';

export '/models/model_catalog.dart' show ModelType, ModelArchitecture;

class ImportedModelEntry {
  final String id;
  final String displayName;
  final ModelType type;
  final ModelArchitecture architecture;
  final List<String> languages;
  final DateTime importedAt;

  const ImportedModelEntry({
    required this.id,
    required this.displayName,
    required this.type,
    required this.architecture,
    required this.languages,
    required this.importedAt,
  });

  factory ImportedModelEntry.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = ModelType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => throw FormatException('Unknown model type: $typeStr'),
    );

    final archStr = json['architecture'] as String;
    final architecture = ModelArchitecture.values.firstWhere(
      (e) => e.name == archStr,
      orElse: () => throw FormatException('Unknown architecture: $archStr'),
    );

    return ImportedModelEntry(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      type: type,
      architecture: architecture,
      languages: List<String>.from(json['languages'] as List? ?? []),
      importedAt: DateTime.parse(json['importedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'type': type.name,
        'architecture': architecture.name,
        'languages': languages,
        'importedAt': importedAt.toIso8601String(),
      };
}
