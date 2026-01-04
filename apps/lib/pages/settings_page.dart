import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/models/settings.dart';
import '/providers/settings_provider.dart';
import '/services/api_health_check.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _primeMessageController;
  late TextEditingController _ttsSpeakerIdController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late double _ttsSpeed;
  late BackgroundListeningDuration _backgroundListeningDuration;
  final _formKey = GlobalKey<FormState>();
  HealthCheckResult? _healthCheckResult;
  bool _isHealthCheckRunning = false;
  bool _obscurePassword = true;
  bool _authenticationExpanded =
      true; // Authentication section expanded by default

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _baseUrlController = TextEditingController(
      text: settings.simpleChatBaseUrl,
    );
    _modelController = TextEditingController(text: settings.simpleChatModel);
    _primeMessageController = TextEditingController(
      text: settings.primeMessage,
    );
    _ttsSpeakerIdController = TextEditingController(
      text: settings.ttsSpeakerId.toString(),
    );
    _usernameController = TextEditingController(text: settings.username ?? '');
    _passwordController = TextEditingController();
    _ttsSpeed = settings.ttsSpeed;
    _backgroundListeningDuration = settings.backgroundListeningDuration;

    // Load saved password asynchronously
    _loadPassword();
  }

  Future<void> _loadPassword() async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final password = await settingsNotifier.getPassword();
    if (password != null && mounted) {
      _passwordController.text = password;
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _primeMessageController.dispose();
    _ttsSpeakerIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (_isHealthCheckRunning) return;

    setState(() {
      _isHealthCheckRunning = true;
      _healthCheckResult = null;
    });

    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    try {
      final service = ApiHealthCheckService();
      final password = await settingsNotifier.getPassword();

      final result = await service.performHealthCheck(
        baseUrl: baseUrl,
        model: model,
        authType: settings.authType,
        username: _usernameController.text.trim(),
        password: password,
      );

      // Auto-update authType if authentication is detected
      if (result.requiresAuth && result.detectedAuthType != null) {
        await settingsNotifier.updateAuthType(result.detectedAuthType!);
      }

      setState(() {
        _healthCheckResult = result;
        _isHealthCheckRunning = false;
      });
    } catch (e) {
      setState(() {
        _healthCheckResult = HealthCheckResult.connectionFailed(e.toString());
        _isHealthCheckRunning = false;
      });
    }
  }

  Future<void> _clearCredentials() async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    await settingsNotifier.clearCredentials();
    await settingsNotifier.updateAuthType(AuthType.none);
    await settingsNotifier.updateUsername('');

    setState(() {
      _usernameController.clear();
      _passwordController.clear();
      _healthCheckResult = null;
    });

    if (mounted) {
      final ThemeData theme = Theme.of(context);
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: const Text('Credentials cleared'),
          backgroundColor: theme.colorScheme.secondaryContainer,
          actions: [
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              },
              child: Text(
                'OK',
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
        }
      });
    }
  }

  Widget _buildDebugInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final settingsNotifier = ref.read(settingsProvider.notifier);
    final settings = ref.read(settingsProvider);

    // Save authentication credentials if changed
    if (_usernameController.text.trim() != (settings.username ?? '')) {
      await settingsNotifier.updateUsername(_usernameController.text.trim());
    }

    if (_passwordController.text.isNotEmpty) {
      await settingsNotifier.setPassword(_passwordController.text);
      // Keep password in field (already there from secure storage or user entry)
    }

    final success = await settingsNotifier.updateSettings(
      simpleChatBaseUrl: _baseUrlController.text.trim(),
      simpleChatModel: _modelController.text.trim(),
      primeMessage: _primeMessageController.text.trim(),
      ttsSpeakerId: int.parse(_ttsSpeakerIdController.text.trim()),
      ttsSpeed: _ttsSpeed,
      backgroundListeningDuration: _backgroundListeningDuration,
    );

    if (!success) {
      if (mounted) {
        final ThemeData theme = Theme.of(context);
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
      return;
    }

    // Settings saved successfully - run health check
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    final updatedSettings = ref.read(settingsProvider);

    try {
      final service = ApiHealthCheckService();
      final password = await settingsNotifier.getPassword();

      final healthResult = await service.performHealthCheck(
        baseUrl: baseUrl,
        model: model,
        authType: updatedSettings.authType,
        username: _usernameController.text.trim(),
        password: password,
      );

      if (mounted) {
        if (healthResult.isSuccess) {
          // Success - close immediately and show message on previous page
          context.pop('Settings saved and connection verified successfully');
        } else {
          // Health check failed - show warning dialog with option to close anyway
          await _showHealthCheckFailureDialog(
            'Connection test failed: ${healthResult.message}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Health check error - show warning dialog with option to close anyway
        await _showHealthCheckFailureDialog(
          'Connection test encountered an error: $e',
        );
      }
    }
  }

  Future<void> _showHealthCheckFailureDialog(String message) async {
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Test Failed'),
        content: Text(
          'Settings have been saved, but:\n\n$message\n\nDo you want to close the settings page anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Review Settings'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close Anyway'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      context.pop('Settings saved, but connection test failed');
    }
  }

  Future<void> _resetToDefaults() async {
    final success = await ref.read(settingsProvider.notifier).resetToDefaults();
    final settings = ref.read(settingsProvider);
    _baseUrlController.text = settings.simpleChatBaseUrl;
    _modelController.text = settings.simpleChatModel;
    _primeMessageController.text = settings.primeMessage;
    _ttsSpeakerIdController.text = settings.ttsSpeakerId.toString();
    setState(() {
      _ttsSpeed = settings.ttsSpeed;
      _backgroundListeningDuration = settings.backgroundListeningDuration;
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
    final settings = ref.watch(settingsProvider);
    final urlSuggestions = settings.history
        .map((entry) => entry.url)
        .toSet()
        .toList();
    final modelSuggestions = settings.history
        .map((entry) => entry.model)
        .toSet()
        .toList();

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
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                // Always show all URL suggestions, but prioritize matches
                final matches = urlSuggestions.where((String option) {
                  return option.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  );
                }).toList();
                final nonMatches = urlSuggestions.where((String option) {
                  return !option.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  );
                }).toList();

                // Return matches first, then non-matches
                return [...matches, ...nonMatches];
              },
              onSelected: (String selection) {
                _baseUrlController.text = selection;
              },
              fieldViewBuilder:
                  (
                    BuildContext context,
                    TextEditingController fieldTextEditingController,
                    FocusNode fieldFocusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    // Sync with our controller
                    fieldTextEditingController.text = _baseUrlController.text;
                    fieldTextEditingController.addListener(() {
                      _baseUrlController.text = fieldTextEditingController.text;
                    });
                    return TextFormField(
                      controller: fieldTextEditingController,
                      focusNode: fieldFocusNode,
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
                    );
                  },
            ),
            const SizedBox(height: 16),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                // Always show all model suggestions, but prioritize matches
                final matches = modelSuggestions.where((String option) {
                  return option.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  );
                }).toList();
                final nonMatches = modelSuggestions.where((String option) {
                  return !option.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  );
                }).toList();

                // Return matches first, then non-matches
                return [...matches, ...nonMatches];
              },
              onSelected: (String selection) {
                _modelController.text = selection;
              },
              fieldViewBuilder:
                  (
                    BuildContext context,
                    TextEditingController fieldTextEditingController,
                    FocusNode fieldFocusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    // Sync with our controller
                    fieldTextEditingController.text = _modelController.text;
                    fieldTextEditingController.addListener(() {
                      _modelController.text = fieldTextEditingController.text;
                    });
                    return TextFormField(
                      controller: fieldTextEditingController,
                      focusNode: fieldFocusNode,
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
                    );
                  },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _primeMessageController,
              decoration: const InputDecoration(
                labelText: 'Prime Message',
                hintText: 'System prompt sent with every request',
                border: OutlineInputBorder(),
                helperText: 'Customize how the assistant should behave',
              ),
              minLines: 5,
              maxLines: 12,
              textInputAction: TextInputAction.newline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Prime message cannot be empty';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text(
                  'Authentication',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                initiallyExpanded: _authenticationExpanded,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _authenticationExpanded = expanded;
                  });
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            border: OutlineInputBorder(),
                            helperText: 'HTTP Basic Auth username',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            helperText:
                                'Saved password can be revealed with the eye icon',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _clearCredentials,
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear Credentials'),
                        ),
                        if (_healthCheckResult != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _healthCheckResult!.isSuccess
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _healthCheckResult!.isSuccess
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _healthCheckResult!.isSuccess
                                          ? Icons.check_circle
                                          : Icons.error,
                                      color: _healthCheckResult!.isSuccess
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _healthCheckResult!.message,
                                        style: TextStyle(
                                          color: _healthCheckResult!.isSuccess
                                              ? Colors.green
                                              : Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 8),
                                Text(
                                  'Request Details:',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                _buildDebugInfo('Method', 'POST'),
                                _buildDebugInfo(
                                  'URL',
                                  '${_baseUrlController.text.trim()}/chat/completions',
                                ),
                                _buildDebugInfo(
                                  'Body',
                                  '{"messages": [{"role": "user", "content": "test"}], "model": "${_modelController.text.trim()}", "max_completion_tokens": 100}',
                                ),
                                if (_healthCheckResult!.httpStatusCode != null)
                                  _buildDebugInfo(
                                    'Status',
                                    'HTTP ${_healthCheckResult!.httpStatusCode}',
                                  ),
                                if (ref.read(settingsProvider).authType ==
                                    AuthType.basic)
                                  _buildDebugInfo(
                                    'Auth',
                                    'Basic ${_usernameController.text.isNotEmpty ? _usernameController.text : "(no username)"}',
                                  ),
                                if (_healthCheckResult!.requiresAuth) ...[
                                  const SizedBox(height: 8),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  _buildDebugInfo(
                                    'Detected Auth Type',
                                    _healthCheckResult!.detectedAuthType?.name
                                            .toUpperCase() ??
                                        'Unknown',
                                  ),
                                  if (_healthCheckResult!.realm != null)
                                    _buildDebugInfo(
                                      'Realm',
                                      _healthCheckResult!.realm!,
                                    ),
                                  if (_healthCheckResult!.loginUrl != null)
                                    _buildDebugInfo(
                                      'Login URL',
                                      _healthCheckResult!.loginUrl!,
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _isHealthCheckRunning
                              ? null
                              : _testConnection,
                          icon: _isHealthCheckRunning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.health_and_safety),
                          label: Text(
                            _isHealthCheckRunning
                                ? 'Testing...'
                                : 'Test Connection',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
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
            const SizedBox(height: 32),
            const Text(
              'Background Listening',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<BackgroundListeningDuration>(
              initialValue: _backgroundListeningDuration,
              decoration: const InputDecoration(
                labelText: 'Background Listening Duration',
                border: OutlineInputBorder(),
                helperText: 'Maximum time for continuous background listening',
              ),
              items: BackgroundListeningDuration.values.map((duration) {
                return DropdownMenuItem(
                  value: duration,
                  child: Text(duration.displayName),
                );
              }).toList(),
              onChanged: (BackgroundListeningDuration? newValue) {
                if (newValue != null) {
                  setState(() {
                    _backgroundListeningDuration = newValue;
                  });
                }
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
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => context.push('/info'),
              icon: const Icon(Icons.info_outline),
              label: const Text('App Info'),
            ),
          ],
        ),
      ),
    );
  }
}
