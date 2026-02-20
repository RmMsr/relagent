import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/agentic/health_check.dart';
import '/models/settings.dart';
import '/providers/settings_provider.dart';
import '/providers/voice_service_provider.dart';
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
  bool _authenticationExpanded = false;

  // Engine settings controllers
  late TextEditingController _engineUrlController;
  late TextEditingController _engineUsernameController;
  late TextEditingController _enginePasswordController;
  bool _obscureEnginePassword = true;
  EngineHealthResult? _engineHealthCheckResult;
  bool _isEngineHealthCheckRunning = false;
  late bool _engineBasicAuthEnabled;

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

    // Engine settings
    _engineUrlController = TextEditingController(text: settings.engineBaseUrl);
    _engineUsernameController = TextEditingController(
      text: settings.engineUsername ?? '',
    );
    _enginePasswordController = TextEditingController();
    _engineBasicAuthEnabled = settings.engineAuthType == AuthType.basic;

    // Expand auth section if username is already set
    _authenticationExpanded = settings.username?.isNotEmpty ?? false;

    // Load saved passwords asynchronously (may also expand sections)
    _loadPassword();
    _loadEnginePassword();
  }

  Future<void> _loadEnginePassword() async {
    final password = await ref
        .read(settingsProvider.notifier)
        .getEnginePassword();
    if (password != null && mounted) {
      _enginePasswordController.text = password;
    }
  }

  Future<void> _loadPassword() async {
    final password = await ref.read(settingsProvider.notifier).getPassword();
    if (password != null && mounted) {
      _passwordController.text = password;
      setState(() {
        _authenticationExpanded = true;
      });
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
    _engineUrlController.dispose();
    _engineUsernameController.dispose();
    _enginePasswordController.dispose();
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

    try {
      final service = ApiHealthCheckService();

      final result = await service.performHealthCheck(
        baseUrl: baseUrl,
        model: model,
        authType: settings.authType,
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim().isNotEmpty
            ? _passwordController.text.trim()
            : null,
      );

      // Auto-update authType if authentication is detected
      if (result.requiresAuth && result.detectedAuthType != null) {
        await ref
            .read(settingsProvider.notifier)
            .updateAuthType(result.detectedAuthType!);
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

  Future<void> _testEngineConnection() async {
    if (_isEngineHealthCheckRunning) return;

    setState(() {
      _isEngineHealthCheckRunning = true;
      _engineHealthCheckResult = null;
    });

    final baseUrl = _engineUrlController.text.trim();
    final authType = _engineBasicAuthEnabled ? AuthType.basic : AuthType.none;

    try {
      final service = EngineHealthCheckService();

      final result = await service.checkStatus(
        baseUrl: baseUrl,
        authType: authType,
        username: _engineUsernameController.text.trim(),
        password: _enginePasswordController.text.trim().isNotEmpty
            ? _enginePasswordController.text.trim()
            : null,
      );

      setState(() {
        _engineHealthCheckResult = result;
        _isEngineHealthCheckRunning = false;
      });
    } catch (e) {
      setState(() {
        _engineHealthCheckResult = EngineHealthResult.connectionFailed(
          e.toString(),
        );
        _isEngineHealthCheckRunning = false;
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

    // Save simple chat authentication credentials if changed
    if (_usernameController.text.trim() != (settings.username ?? '')) {
      await settingsNotifier.updateUsername(_usernameController.text.trim());
    }

    if (_passwordController.text.isNotEmpty) {
      await settingsNotifier.setPassword(_passwordController.text);
    }

    // Save engine settings
    await settingsNotifier.updateEngineBaseUrl(
      _engineUrlController.text.trim(),
    );
    final engineAuthType = _engineBasicAuthEnabled
        ? AuthType.basic
        : AuthType.none;
    if (engineAuthType != settings.engineAuthType) {
      await settingsNotifier.updateEngineAuthType(engineAuthType);
    }
    if (_engineUsernameController.text.trim() !=
        (settings.engineUsername ?? '')) {
      await settingsNotifier.updateEngineUsername(
        _engineUsernameController.text.trim(),
      );
    }
    if (_enginePasswordController.text.isNotEmpty) {
      await settingsNotifier.setEnginePassword(_enginePasswordController.text);
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

    // Settings saved successfully - run health check for selected backend
    final updatedSettings = ref.read(settingsProvider);

    try {
      bool isSuccess;
      String failureMessage;

      if (updatedSettings.selectedBackend == ChatBackendType.relagentEngine) {
        // Engine health check
        final service = EngineHealthCheckService();
        final engineAuthType = _engineBasicAuthEnabled
            ? AuthType.basic
            : AuthType.none;
        final result = await service.checkStatus(
          baseUrl: _engineUrlController.text.trim(),
          authType: engineAuthType,
          username: _engineUsernameController.text.trim(),
          password: _enginePasswordController.text.trim().isNotEmpty
              ? _enginePasswordController.text.trim()
              : null,
        );
        isSuccess = result.isSuccess;
        failureMessage = result.message;
      } else {
        // OpenAI-compatible health check
        final service = ApiHealthCheckService();
        final result = await service.performHealthCheck(
          baseUrl: _baseUrlController.text.trim(),
          model: _modelController.text.trim(),
          authType: updatedSettings.authType,
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim().isNotEmpty
              ? _passwordController.text.trim()
              : null,
        );
        isSuccess = result.isSuccess;
        failureMessage = result.message;
      }

      if (mounted) {
        if (isSuccess) {
          // Success - close immediately and show message on previous page
          context.pop('Settings saved and connection verified successfully');
        } else {
          // Health check failed - show warning dialog with option to close anyway
          await _showHealthCheckFailureDialog(
            'Connection test failed: $failureMessage',
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
    _engineUrlController.text = settings.engineBaseUrl;
    _engineUsernameController.text = settings.engineUsername ?? '';
    _enginePasswordController.clear();
    setState(() {
      _ttsSpeed = settings.ttsSpeed;
      _backgroundListeningDuration = settings.backgroundListeningDuration;
      _engineBasicAuthEnabled = settings.engineAuthType == AuthType.basic;
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
              'Chat Backend',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Select which backend to use for chat',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SegmentedButton<ChatBackendType>(
              segments: const [
                ButtonSegment<ChatBackendType>(
                  value: ChatBackendType.relagentEngine,
                  label: Text('Relagent Engine'),
                  icon: Icon(Icons.smart_toy_outlined),
                ),
                ButtonSegment<ChatBackendType>(
                  value: ChatBackendType.openAiCompatible,
                  label: Text('OpenAI-compatible'),
                  icon: Icon(Icons.cloud_outlined),
                ),
              ],
              selected: {settings.selectedBackend},
              onSelectionChanged: (Set<ChatBackendType> newSelection) {
                ref
                    .read(settingsProvider.notifier)
                    .updateSelectedBackend(newSelection.first);
              },
            ),
            const SizedBox(height: 8),
            Text(
              settings.selectedBackend == ChatBackendType.openAiCompatible
                  ? 'Connect to any OpenAI-compatible API server (LM Studio, Ollama, vLLM, etc.)'
                  : 'Connect to the full-featured Relagent engine with persistence and agentic capabilities',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (settings.selectedBackend ==
                ChatBackendType.openAiCompatible) ...[
              const SizedBox(height: 32),
              const Text(
                'Chat API Configuration',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _AutocompleteWithFocusLoss<String>(
                key: ValueKey('openai-url-${settings.selectedBackend}'),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  return urlSuggestions;
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
                      fieldTextEditingController.text = _baseUrlController.text;
                      fieldTextEditingController.addListener(() {
                        _baseUrlController.text =
                            fieldTextEditingController.text;
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
                          onFieldSubmitted();
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
              _AutocompleteWithFocusLoss<String>(
                key: ValueKey('openai-model-${settings.selectedBackend}'),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  return modelSuggestions;
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
                        textInputAction: TextInputAction.next,
                        onEditingComplete: () {
                          onFieldSubmitted();
                          FocusScope.of(context).nextFocus();
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
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
                                  if (_healthCheckResult!.httpStatusCode !=
                                      null)
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
            ],
            if (settings.selectedBackend == ChatBackendType.relagentEngine) ...[
              const SizedBox(height: 32),
              const Text(
                'Engine Configuration',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Agentic chat backend (Relagent engine)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _AutocompleteWithFocusLoss<String>(
                key: ValueKey('engine-url-${settings.selectedBackend}'),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  return settings.engineUrlHistory;
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(
                                option.isEmpty ? '(same origin)' : option,
                                style: option.isEmpty
                                    ? const TextStyle(
                                        fontStyle: FontStyle.italic,
                                      )
                                    : null,
                              ),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                onSelected: (String selection) {
                  _engineUrlController.text = selection;
                },
                fieldViewBuilder:
                    (
                      BuildContext context,
                      TextEditingController fieldTextEditingController,
                      FocusNode fieldFocusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      fieldTextEditingController.text =
                          _engineUrlController.text;
                      fieldTextEditingController.addListener(() {
                        _engineUrlController.text =
                            fieldTextEditingController.text;
                      });
                      return TextFormField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        decoration: InputDecoration(
                          labelText: 'Engine URL',
                          hintText: kIsWeb
                              ? '(empty = same origin)'
                              : 'http://localhost:8000',
                          border: const OutlineInputBorder(),
                          helperText: kIsWeb
                              ? 'Leave empty to use the current origin'
                              : 'Relagent engine base URL',
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        onEditingComplete: () {
                          onFieldSubmitted();
                          FocusScope.of(context).nextFocus();
                        },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            if (kIsWeb) return null;
                            return 'Please enter an engine URL';
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
              SwitchListTile(
                title: const Text('Basic Authentication'),
                subtitle: const Text('Enable HTTP Basic Auth'),
                value: _engineBasicAuthEnabled,
                onChanged: (bool value) {
                  setState(() {
                    _engineBasicAuthEnabled = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),
              if (_engineBasicAuthEnabled) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _engineUsernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _enginePasswordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureEnginePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureEnginePassword = !_obscureEnginePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureEnginePassword,
                  textInputAction: TextInputAction.done,
                ),
              ],
              if (_engineHealthCheckResult != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _engineHealthCheckResult!.isSuccess
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _engineHealthCheckResult!.isSuccess
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _engineHealthCheckResult!.isSuccess
                            ? Icons.check_circle
                            : Icons.error,
                        color: _engineHealthCheckResult!.isSuccess
                            ? Colors.green
                            : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _engineHealthCheckResult!.message,
                          style: TextStyle(
                            color: _engineHealthCheckResult!.isSuccess
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isEngineHealthCheckRunning
                    ? null
                    : _testEngineConnection,
                icon: _isEngineHealthCheckRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.health_and_safety),
                label: Text(
                  _isEngineHealthCheckRunning
                      ? 'Testing...'
                      : 'Test Connection',
                ),
              ),
            ],
            if (ref.read(voiceCapabilitiesProvider).isAsrAvailable ||
                ref.read(voiceCapabilitiesProvider).isTtsAvailable) ...[
              const SizedBox(height: 32),
              const Text(
                'Voice Settings',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (ref.read(voiceCapabilitiesProvider).isTtsAvailable) ...[
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
              ],
              if (ref.read(voiceCapabilitiesProvider).isAsrAvailable) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<BackgroundListeningDuration>(
                  initialValue: _backgroundListeningDuration,
                  decoration: const InputDecoration(
                    labelText: 'Background Listening Duration',
                    border: OutlineInputBorder(),
                    helperText:
                        'Maximum time for continuous background listening',
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
              ],
            ],
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

class _AutocompleteWithFocusLoss<T extends Object> extends StatefulWidget {
  final Iterable<T> Function(TextEditingValue) optionsBuilder;
  final void Function(T) onSelected;
  final Widget Function(
    BuildContext,
    TextEditingController,
    FocusNode,
    VoidCallback,
  )
  fieldViewBuilder;
  final Widget Function(BuildContext, void Function(T), Iterable<T>)?
  optionsViewBuilder;

  const _AutocompleteWithFocusLoss({
    super.key,
    required this.optionsBuilder,
    required this.onSelected,
    required this.fieldViewBuilder,
    this.optionsViewBuilder,
  });

  @override
  State<_AutocompleteWithFocusLoss<T>> createState() =>
      _AutocompleteWithFocusLossState<T>();
}

class _AutocompleteWithFocusLossState<T extends Object>
    extends State<_AutocompleteWithFocusLoss<T>> {
  bool _showOptions = false;
  FocusNode? _internalFocusNode;

  @override
  void dispose() {
    _internalFocusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    final hasFocus = _internalFocusNode?.hasFocus ?? false;
    if (hasFocus != _showOptions) {
      setState(() {
        _showOptions = hasFocus;
      });
    }
  }

  void _onSelected(T value) {
    setState(() {
      _showOptions = false;
    });
    widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<T>(
      optionsBuilder: widget.optionsBuilder,
      onSelected: _onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        if (_internalFocusNode != focusNode) {
          _internalFocusNode?.removeListener(_onFocusChange);
          _internalFocusNode = focusNode;
          focusNode.addListener(_onFocusChange);
        }
        return GestureDetector(
          onTap: () {
            if (!_showOptions) {
              setState(() {
                _showOptions = true;
              });
            }
          },
          child: widget.fieldViewBuilder(
            context,
            controller,
            focusNode,
            onSubmitted,
          ),
        );
      },
      optionsViewBuilder: widget.optionsViewBuilder != null
          ? (context, onSelected, options) {
              if (!_showOptions) return const SizedBox.shrink();
              return widget.optionsViewBuilder!(context, onSelected, options);
            }
          : (context, onSelected, options) {
              if (!_showOptions) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(option.toString()),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
    );
  }
}
