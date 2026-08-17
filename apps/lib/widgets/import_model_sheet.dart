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
  ModelArchitecture? initialArchitecture,
  bool isAmbiguousShape = false,
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
      initialArchitecture: initialArchitecture ?? detectedArchitecture,
      isAmbiguousShape: isAmbiguousShape,
      initialType: initialType,
      initialLanguages: initialLanguages,
    ),
  );
}

class _ImportModelSheet extends StatefulWidget {
  final String suggestedName;
  // What re-running detection against the actual files says right now.
  // Used only to judge/label the current pick — never to silently override it.
  final ModelArchitecture? detectedArchitecture;
  // What the dropdown starts on: the previously-saved pick when editing, or
  // the detected guess when importing fresh.
  final ModelArchitecture? initialArchitecture;
  // Whether the files match the encoder+decoder+joiner layout shared by
  // live Transducer and chunked NeMo Transducer — neither guess is trustworthy
  // here, regardless of which one detection landed on.
  final bool isAmbiguousShape;
  final ModelType initialType;
  final List<String> initialLanguages;

  const _ImportModelSheet({
    required this.suggestedName,
    required this.detectedArchitecture,
    required this.initialArchitecture,
    required this.isAmbiguousShape,
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
    // Only pre-select the initial arch if it is valid for the initial type.
    final allowed = _modelType == ModelType.tts ? _ttsArchitectures : _asrArchitectures;
    _architecture = allowed.contains(widget.initialArchitecture)
        ? widget.initialArchitecture
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

  // Live Transducer and chunked NeMo Transducer share the exact same files,
  // so whichever one detection guessed isn't trustworthy — treat both picks
  // the same way rather than only warning when they differ from the guess.
  bool get _isAmbiguousPick =>
      widget.isAmbiguousShape &&
      (_architecture == ModelArchitecture.transducer ||
          _architecture == ModelArchitecture.offlineNemoTransducer);

  Widget _noteRow((String, String) labelAndRest, Color? color) {
    final (label, rest) = labelAndRest;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: style),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  TextSpan(
                    text: '$label ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: rest),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
            if (_isAmbiguousPick)
              _noteRow(
                (
                  'Ambiguous format:',
                  'if it leads to app crash, try the other Transducer.',
                ),
                theme.colorScheme.error,
              ),
            if (_isAmbiguousPick || _architecture == widget.detectedArchitecture)
              _noteRow(
                ('Detected:', architectureFamilyLabel(widget.detectedArchitecture!)),
                _isAmbiguousPick
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
              )
            else
              _noteRow(
                (
                  'Architecture mismatch:',
                  'Detected ${architectureFamilyLabel(widget.detectedArchitecture!)}',
                ),
                theme.colorScheme.error,
              ),
          ],
          if (_architecture != null && architectureHint(_architecture!) != null)
            _noteRow(
              architectureHint(_architecture!)!,
              theme.colorScheme.onSurfaceVariant,
            ),
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
      return 'Transducer (live)';
    case ModelArchitecture.ctc:
      return 'CTC (live)';
    case ModelArchitecture.vitsPiper:
      return 'Piper VITS (TTS)';
    case ModelArchitecture.kokoro:
      return 'Kokoro (TTS)';
    case ModelArchitecture.onlineNemoCtc:
      return 'NeMo CTC (live)';
    case ModelArchitecture.offlineNemoTransducer:
      return 'NeMo Transducer (chunked)';
    case ModelArchitecture.pocket:
      return 'Pocket (TTS)';
  }
}

/// Bare architecture family name, without the live/chunked/TTS qualifier —
/// used for "Detected: …" since detection only found a file shape, not a
/// confirmed behavior (the shape can be ambiguous between two behaviors).
String architectureFamilyLabel(ModelArchitecture a) {
  switch (a) {
    case ModelArchitecture.transducer:
      return 'Transducer';
    case ModelArchitecture.ctc:
      return 'CTC';
    case ModelArchitecture.vitsPiper:
      return 'Piper VITS';
    case ModelArchitecture.kokoro:
      return 'Kokoro';
    case ModelArchitecture.onlineNemoCtc:
      return 'NeMo CTC';
    case ModelArchitecture.offlineNemoTransducer:
      return 'NeMo Transducer';
    case ModelArchitecture.pocket:
      return 'Pocket';
  }
}

/// (label, description) explaining what picking this architecture means for
/// recognition behavior, shown as a list row in the import sheet. Null for
/// architectures with nothing behavior-relevant to add (the TTS ones).
(String, String)? architectureHint(ModelArchitecture a) {
  switch (a) {
    case ModelArchitecture.transducer:
    case ModelArchitecture.ctc:
    case ModelArchitecture.onlineNemoCtc:
      return ('Live:', 'text appears continuously as you speak.');
    case ModelArchitecture.offlineNemoTransducer:
      return ('Chunked:', 'waits for a pause, then transcribes a few words at once.');
    case ModelArchitecture.vitsPiper:
    case ModelArchitecture.kokoro:
    case ModelArchitecture.pocket:
      return null;
  }
}
