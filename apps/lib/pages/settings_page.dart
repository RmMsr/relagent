import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/providers/settings_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _ttsSpeakerIdController;
  late double _ttsSpeed;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _baseUrlController = TextEditingController(
      text: settings.simpleChatBaseUrl,
    );
    _modelController = TextEditingController(text: settings.simpleChatModel);
    _ttsSpeakerIdController = TextEditingController(
      text: settings.ttsSpeakerId.toString(),
    );
    _ttsSpeed = settings.ttsSpeed;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _ttsSpeakerIdController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          simpleChatBaseUrl: _baseUrlController.text.trim(),
          simpleChatModel: _modelController.text.trim(),
          ttsSpeakerId: int.parse(_ttsSpeakerIdController.text.trim()),
          ttsSpeed: _ttsSpeed,
        );

    if (mounted) {
      final ThemeData theme = Theme.of(context);
      if (success) {
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            content: const Text('Settings saved successfully'),
            backgroundColor: theme.colorScheme.secondaryContainer,
            actions: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                },
                child: Text(
                  'OK',
                  style: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        );
        // Auto-dismiss after a short delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            context.pop();
          }
        });
      } else {
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            content: const Text(
              'Failed to save settings. Check console for details.',
            ),
            backgroundColor: theme.colorScheme.errorContainer,
            actions: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                },
                child: Text(
                  'DISMISS',
                  style: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _resetToDefaults() async {
    final success = await ref.read(settingsProvider.notifier).resetToDefaults();
    final settings = ref.read(settingsProvider);
    _baseUrlController.text = settings.simpleChatBaseUrl;
    _modelController.text = settings.simpleChatModel;
    _ttsSpeakerIdController.text = settings.ttsSpeakerId.toString();
    setState(() {
      _ttsSpeed = settings.ttsSpeed;
    });

    if (mounted) {
      final ThemeData theme = Theme.of(context);
      if (success) {
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            content: const Text('Reset to defaults successfully'),
            backgroundColor: theme.colorScheme.secondaryContainer,
            actions: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                },
                child: Text(
                  'OK',
                  style: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        );
        // Auto-dismiss after a short delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          }
        });
      } else {
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            content: const Text(
              'Failed to save default settings. Check console for details.',
            ),
            backgroundColor: theme.colorScheme.errorContainer,
            actions: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                },
                child: Text(
                  'DISMISS',
                  style: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text(
              'Chat API Configuration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'http://localhost:1234/v1',
                border: OutlineInputBorder(),
                helperText: 'OpenAI-compatible API endpoint',
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              onEditingComplete: () {
                // Move to next field
                FocusScope.of(context).nextFocus();
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an API base URL';
                }
                if (!value.startsWith('http://') &&
                    !value.startsWith('https://')) {
                  return 'URL must start with http:// or https://';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Model Name',
                hintText: 'qwen2.5-coder:7b',
                border: OutlineInputBorder(),
                helperText: 'Model to use for chat completions',
              ),
              textInputAction: TextInputAction.done,
              onEditingComplete: () {
                // Save settings when pressing Enter on last field
                _saveSettings();
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a model name';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'TTS Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ttsSpeakerIdController,
              decoration: const InputDecoration(
                labelText: 'TTS Speaker ID',
                hintText: '0',
                border: OutlineInputBorder(),
                helperText: 'Voice ID for text-to-speech (0-based)',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a speaker ID';
                }
                final id = int.tryParse(value.trim());
                if (id == null || id < 0) {
                  return 'Speaker ID must be a non-negative integer';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TTS Speed: ${_ttsSpeed.toStringAsFixed(2)}x',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Slider(
                  value: _ttsSpeed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  label: '${_ttsSpeed.toStringAsFixed(2)}x',
                  onChanged: (value) {
                    setState(() {
                      _ttsSpeed = value;
                    });
                  },
                ),
                Text(
                  'Controls playback speed (0.5x - 2.0x)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetToDefaults,
                    child: const Text('Reset to Defaults'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
