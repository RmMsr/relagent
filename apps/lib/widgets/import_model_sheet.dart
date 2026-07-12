import 'package:flutter/material.dart';

import '/models/imported_model.dart';

/// Bottom sheet for collecting model metadata before import.
///
/// Returns an [ImportedModelEntry] template (without a real id or importedAt)
/// when the user confirms, or null if they cancel.
Future<ImportedModelEntry?> showImportModelSheet(
  BuildContext context, {
  required String suggestedName,
  ModelArchitecture? detectedArchitecture,
  ModelType initialType = ModelType.asr,
  List<String> initialLanguages = const [],
}) {
  return showModalBottomSheet<ImportedModelEntry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ImportModelSheet(
      suggestedName: suggestedName,
      detectedArchitecture: detectedArchitecture,
      initialType: initialType,
      initialLanguages: initialLanguages,
    ),
  );
}

class _ImportModelSheet extends StatefulWidget {
  final String suggestedName;
  final ModelArchitecture? detectedArchitecture;
  final ModelType initialType;
  final List<String> initialLanguages;

  const _ImportModelSheet({
    required this.suggestedName,
    required this.detectedArchitecture,
    required this.initialType,
    required this.initialLanguages,
  });

  @override
  State<_ImportModelSheet> createState() => _ImportModelSheetState();
}

class _ImportModelSheetState extends State<_ImportModelSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _languagesController;
  late ModelType _modelType;
  ModelArchitecture? _architecture;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.suggestedName);
    _languagesController = TextEditingController(
      text: widget.initialLanguages.join(', '),
    );
    _modelType = widget.initialType;
    // Only pre-select the detected arch if it is valid for the initial type.
    final allowed = _modelType == ModelType.tts ? _ttsArchitectures : _asrArchitectures;
    _architecture = allowed.contains(widget.detectedArchitecture)
        ? widget.detectedArchitecture
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _languagesController.dispose();
    super.dispose();
  }

  List<String> get _languages {
    return _languagesController.text
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static const _ttsArchitectures = {
    ModelArchitecture.vitsPiper,
    ModelArchitecture.kokoro,
    ModelArchitecture.pocket,
  };

  static const _asrArchitectures = {
    ModelArchitecture.transducer,
    ModelArchitecture.ctc,
    ModelArchitecture.onlineNemoCtc,
    ModelArchitecture.offlineNemoTransducer,
  };

  Set<ModelArchitecture> get _allowedArchitectures =>
      _modelType == ModelType.tts ? _ttsArchitectures : _asrArchitectures;

  bool get _canImport => _architecture != null;

  void _confirm() {
    final name = _nameController.text.trim().isEmpty
        ? widget.suggestedName
        : _nameController.text.trim();

    Navigator.of(context).pop(
      ImportedModelEntry(
        id: '', // filled in by ImportedModelService
        displayName: name,
        type: _modelType,
        architecture: _architecture!,
        languages: _languages,
        importedAt: DateTime.now(), // placeholder; overwritten by service
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import Model', style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),

          // Display name
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Display name (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Model type toggle
          Text('Model type', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<ModelType>(
            segments: const [
              ButtonSegment(
                value: ModelType.asr,
                label: Text('Speech Recognition'),
              ),
              ButtonSegment(
                value: ModelType.tts,
                label: Text('Text-to-Speech'),
              ),
            ],
            selected: {_modelType},
            onSelectionChanged: (s) => setState(() {
              _modelType = s.first;
              if (_architecture != null &&
                  !_allowedArchitectures.contains(_architecture)) {
                _architecture = null;
              }
            }),
          ),
          const SizedBox(height: 16),

          // Architecture
          DropdownButtonFormField<ModelArchitecture>(
            value: _architecture,
            decoration: InputDecoration(
              labelText: 'Architecture${_architecture == null ? ' (required)' : ''}',
              border: const OutlineInputBorder(),
            ),
            items: _allowedArchitectures.map((a) {
              return DropdownMenuItem(
                value: a,
                child: Text(architectureLabel(a)),
              );
            }).toList(),
            onChanged: (v) => setState(() => _architecture = v),
          ),
          if (widget.detectedArchitecture != null) ...[
            const SizedBox(height: 4),
            if (_architecture != widget.detectedArchitecture)
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Detected: ${architectureLabel(widget.detectedArchitecture!)}. '
                      'Wrong architecture will crash the app.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              )
            else
              Text(
                'Auto-detected from archive',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
          ],
          const SizedBox(height: 16),

          // Languages
          TextField(
            controller: _languagesController,
            decoration: const InputDecoration(
              labelText: 'Language codes (optional, e.g. en, de)',
              border: OutlineInputBorder(),
              helperText: 'Comma-separated ISO 639-1 codes',
            ),
          ),
          const SizedBox(height: 24),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _canImport ? _confirm : null,
                child: const Text('Import'),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

String architectureLabel(ModelArchitecture a) {
  switch (a) {
    case ModelArchitecture.transducer:
      return 'Transducer (Zipformer)';
    case ModelArchitecture.ctc:
      return 'CTC (Paraformer / offline)';
    case ModelArchitecture.vitsPiper:
      return 'Piper VITS (TTS)';
    case ModelArchitecture.kokoro:
      return 'Kokoro (TTS)';
    case ModelArchitecture.onlineNemoCtc:
      return 'NeMo CTC (streaming)';
    case ModelArchitecture.offlineNemoTransducer:
      return 'NeMo Transducer (offline)';
    case ModelArchitecture.pocket:
      return 'Pocket (TTS)';
  }
}
