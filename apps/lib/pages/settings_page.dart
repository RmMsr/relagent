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
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _baseUrlController = TextEditingController(
      text: settings.simpleChatBaseUrl,
    );
    _modelController = TextEditingController(text: settings.simpleChatModel);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          simpleChatBaseUrl: _baseUrlController.text.trim(),
          simpleChatModel: _modelController.text.trim(),
        );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
      context.pop();
    }
  }

  Future<void> _resetToDefaults() async {
    await ref.read(settingsProvider.notifier).resetToDefaults();
    final settings = ref.read(settingsProvider);
    _baseUrlController.text = settings.simpleChatBaseUrl;
    _modelController.text = settings.simpleChatModel;

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reset to defaults')));
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
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a model name';
                }
                return null;
              },
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
