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
  bool _hasPassword = false;
  bool _chatBasicAuthEnabled = false;

  // Engine settings controllers
  late TextEditingController _engineUrlController;
  late TextEditingController _engineUsernameController;
  late TextEditingController _enginePasswordController;
  late TextEditingController _engineApiKeyController;
  bool _hasEnginePassword = false;
  EngineHealthResult? _engineHealthCheckResult;
  bool _isEngineHealthCheckRunning = false;
  bool _engineBasicAuthEnabled = false;

  // Chat API key controller
  late TextEditingController _chatApiKeyController;

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
    _chatBasicAuthEnabled = settings.username?.isNotEmpty ?? false;
    _ttsSpeed = settings.ttsSpeed;
    _backgroundListeningDuration = settings.backgroundListeningDuration;

    // Engine settings
    _engineUrlController = TextEditingController(text: settings.engineBaseUrl);
    _engineUsernameController = TextEditingController(
      text: settings.engineUsername ?? '',
    );
    _enginePasswordController = TextEditingController();
    _engineApiKeyController = TextEditingController();
    _engineBasicAuthEnabled = settings.engineUsername?.isNotEmpty ?? false;

    // Chat API key
    _chatApiKeyController = TextEditingController();

    // Check whether passwords are saved (without loading the value)
    _checkSavedCredentials();
  }

  Future<void> _checkSavedCredentials() async {
    final notifier = ref.read(settingsProvider.notifier);
    final password = await notifier.getPassword();
    final enginePassword = await notifier.getEnginePassword();
    if (mounted) {
      setState(() {
        _hasPassword = password != null;
        _hasEnginePassword = enginePassword != null;
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
    _engineApiKeyController.dispose();
    _chatApiKeyController.dispose();
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
    final notifier = ref.read(settingsProvider.notifier);
    final authType = _chatBasicAuthEnabled ? AuthType.basic : AuthType.none;

    try {
      final service = ApiHealthCheckService();

      final result = await service.performHealthCheck(
        baseUrl: baseUrl,
        model: model,
        authType: authType,
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim().isNotEmpty
            ? _passwordController.text.trim()
            : await notifier.getPassword(),
        apiKey: _chatApiKeyController.text.trim().isNotEmpty
            ? _chatApiKeyController.text.trim()
            : await notifier.getChatApiKey(),
      );

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
    final notifier = ref.read(settingsProvider.notifier);

    try {
      final service = EngineHealthCheckService();

      final result = await service.checkStatus(
        baseUrl: baseUrl,
        authType: authType,
        username: _engineUsernameController.text.trim(),
        password: _enginePasswordController.text.trim().isNotEmpty
            ? _enginePasswordController.text.trim()
            : await notifier.getEnginePassword(),
        apiKey: _engineApiKeyController.text.trim().isNotEmpty
            ? _engineApiKeyController.text.trim()
            : await notifier.getEngineApiKey(),
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

  void _showClearedBanner() {
    if (!mounted) return;
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
      if (mounted) ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    });
  }

  Future<void> _clearCredentials() async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    await settingsNotifier.clearCredentials();
    await settingsNotifier.clearChatApiKey();
    await settingsNotifier.updateAuthType(AuthType.none);
    await settingsNotifier.updateUsername('');

    setState(() {
      _usernameController.clear();
      _passwordController.clear();
      _chatApiKeyController.clear();
      _hasPassword = false;
      _chatBasicAuthEnabled = false;
      _healthCheckResult = null;
    });

    _showClearedBanner();
  }

  Future<void> _clearEngineCredentials() async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    await settingsNotifier.clearEngineCredentials();
    await settingsNotifier.clearEngineApiKey();
    await settingsNotifier.updateEngineAuthType(AuthType.none);
    await settingsNotifier.updateEngineUsername('');

    setState(() {
      _engineUsernameController.clear();
      _enginePasswordController.clear();
      _engineApiKeyController.clear();
      _hasEnginePassword = false;
      _engineBasicAuthEnabled = false;
      _engineHealthCheckResult = null;
    });

    _showClearedBanner();
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

  Widget _buildChatHealthPanel() {
    final result = _healthCheckResult!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.isSuccess
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: result.isSuccess ? Colors.green : Colors.red),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.isSuccess ? Icons.check_circle : Icons.error,
                color: result.isSuccess ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.message,
                  style: TextStyle(
                    color: result.isSuccess ? Colors.green : Colors.red,
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
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _buildDebugInfo('Method', 'POST'),
          _buildDebugInfo(
            'URL',
            '${_baseUrlController.text.trim()}/chat/completions',
          ),
          _buildDebugInfo(
            'Body',
            '{"messages": [{"role": "user", "content": "test"}], '
                '"model": "${_modelController.text.trim()}", '
                '"max_completion_tokens": 100}',
          ),
          if (result.httpStatusCode != null)
            _buildDebugInfo('Status', 'HTTP ${result.httpStatusCode}'),
          if (ref.read(settingsProvider).authType == AuthType.basic)
            _buildDebugInfo(
              'Auth',
              'Basic ${_usernameController.text.isNotEmpty ? _usernameController.text : "(no username)"}',
            ),
          if (result.requiresAuth) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _buildDebugInfo(
              'Detected Auth Type',
              result.detectedAuthType?.name.toUpperCase() ?? 'Unknown',
            ),
            if (result.realm != null) _buildDebugInfo('Realm', result.realm!),
            if (result.loginUrl != null)
              _buildDebugInfo('Login URL', result.loginUrl!),
          ],
        ],
      ),
    );
  }

  Widget _buildEngineHealthPanel() {
    final result = _engineHealthCheckResult!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.isSuccess
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: result.isSuccess ? Colors.green : Colors.red),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.isSuccess ? Icons.check_circle : Icons.error,
                color: result.isSuccess ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.message,
                  style: TextStyle(
                    color: result.isSuccess ? Colors.green : Colors.red,
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
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _buildDebugInfo('Method', 'GET'),
          _buildDebugInfo(
            'URL',
            '${_engineUrlController.text.trim()}/api/v1/status',
          ),
          if (result.httpStatusCode != null)
            _buildDebugInfo('Status', 'HTTP ${result.httpStatusCode}'),
          if (result.engineName != null)
            _buildDebugInfo('Engine', result.engineName!),
          if (result.engineVersion != null)
            _buildDebugInfo('Version', result.engineVersion!),
          if (result.requiresAuth && result.detectedAuthType != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _buildDebugInfo(
              'Detected Auth Type',
              result.detectedAuthType!.name.toUpperCase(),
            ),
          ],
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
      setState(() => _hasPassword = true);
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
      setState(() => _hasEnginePassword = true);
    }

    // Save API keys only when explicitly entered (empty = keep existing)
    if (_engineApiKeyController.text.trim().isNotEmpty) {
      await settingsNotifier.setEngineApiKey(
        _engineApiKeyController.text.trim(),
      );
    }
    if (_chatApiKeyController.text.trim().isNotEmpty) {
      await settingsNotifier.setChatApiKey(_chatApiKeyController.text.trim());
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
        final service = EngineHealthCheckService();
        final result = await service.checkStatus(
          baseUrl: _engineUrlController.text.trim(),
          authType: _engineBasicAuthEnabled ? AuthType.basic : AuthType.none,
          username: _engineUsernameController.text.trim(),
          password: _enginePasswordController.text.trim().isNotEmpty
              ? _enginePasswordController.text.trim()
              : await settingsNotifier.getEnginePassword(),
          apiKey: _engineApiKeyController.text.trim().isNotEmpty
              ? _engineApiKeyController.text.trim()
              : await settingsNotifier.getEngineApiKey(),
        );
        isSuccess = result.isSuccess;
        failureMessage = result.message;
      } else {
        final service = ApiHealthCheckService();
        final result = await service.performHealthCheck(
          baseUrl: _baseUrlController.text.trim(),
          model: _modelController.text.trim(),
          authType: _chatBasicAuthEnabled ? AuthType.basic : AuthType.none,
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim().isNotEmpty
              ? _passwordController.text.trim()
              : await settingsNotifier.getPassword(),
          apiKey: _chatApiKeyController.text.trim().isNotEmpty
              ? _chatApiKeyController.text.trim()
              : await settingsNotifier.getChatApiKey(),
        );
        isSuccess = result.isSuccess;
        failureMessage = result.message;
      }

      if (mounted) {
        if (isSuccess) {
          context.pop('Settings saved and connection verified successfully');
        } else {
          await _showHealthCheckFailureDialog(
            'Connection test failed: $failureMessage',
          );
        }
      }
    } catch (e) {
      if (mounted) {
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
    _engineApiKeyController.clear();
    _chatApiKeyController.clear();
    setState(() {
      _ttsSpeed = settings.ttsSpeed;
      _backgroundListeningDuration = settings.backgroundListeningDuration;
      _hasPassword = false;
      _hasEnginePassword = false;
      _chatBasicAuthEnabled = false;
      _engineBasicAuthEnabled = false;
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
              const Text(
                'Authentication',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _AuthSection(
                apiKeyController: _chatApiKeyController,
                hasApiKey: settings.simpleChatHasApiKey,
                basicAuthEnabled: _chatBasicAuthEnabled,
                onBasicAuthToggleChanged: (v) =>
                    setState(() => _chatBasicAuthEnabled = v),
                usernameController: _usernameController,
                passwordController: _passwordController,
                hasPassword: _hasPassword,
                healthCheckResult: _healthCheckResult != null
                    ? _buildChatHealthPanel()
                    : null,
                isTestRunning: _isHealthCheckRunning,
                onTest: _testConnection,
                onClear: _clearCredentials,
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
                              ? '(empty = this server)'
                              : 'http://localhost:8000/',
                          floatingLabelBehavior: kIsWeb
                              ? FloatingLabelBehavior.always
                              : FloatingLabelBehavior.auto,
                          border: const OutlineInputBorder(),
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
              _AuthSection(
                apiKeyController: _engineApiKeyController,
                hasApiKey: settings.engineHasApiKey,
                basicAuthEnabled: _engineBasicAuthEnabled,
                onBasicAuthToggleChanged: (v) =>
                    setState(() => _engineBasicAuthEnabled = v),
                usernameController: _engineUsernameController,
                passwordController: _enginePasswordController,
                hasPassword: _hasEnginePassword,
                healthCheckResult: _engineHealthCheckResult != null
                    ? _buildEngineHealthPanel()
                    : null,
                isTestRunning: _isEngineHealthCheckRunning,
                onTest: _testEngineConnection,
                onClear: _clearEngineCredentials,
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
                  child: OutlinedButton(
                    onPressed: _resetToDefaults,
                    child: const Text('Reset to Defaults'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Authentication credential fields shared between engine and OpenAI backends.
///
/// Shows API key first, then an optional Basic Auth section (username/password)
/// controlled by a toggle. The toggle defaults to on when a username is saved.
class _AuthSection extends StatelessWidget {
  const _AuthSection({
    required this.apiKeyController,
    required this.hasApiKey,
    required this.basicAuthEnabled,
    required this.onBasicAuthToggleChanged,
    required this.usernameController,
    required this.passwordController,
    required this.hasPassword,
    required this.isTestRunning,
    required this.onTest,
    required this.onClear,
    this.healthCheckResult,
  });

  final TextEditingController apiKeyController;
  final bool hasApiKey;
  final bool basicAuthEnabled;
  final ValueChanged<bool> onBasicAuthToggleChanged;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool hasPassword;
  final Widget? healthCheckResult;
  final bool isTestRunning;
  final VoidCallback onTest;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SecretField(
          controller: apiKeyController,
          labelText: 'API Key',
          isSaved: hasApiKey,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Basic Authentication'),
          subtitle: const Text('HTTP username and password'),
          value: basicAuthEnabled,
          onChanged: onBasicAuthToggleChanged,
          contentPadding: EdgeInsets.zero,
        ),
        if (basicAuthEnabled) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          _SecretField(
            controller: passwordController,
            labelText: 'Password',
            isSaved: hasPassword,
          ),
        ],
        if (healthCheckResult != null) ...[
          const SizedBox(height: 16),
          healthCheckResult!,
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear Credentials'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isTestRunning ? null : onTest,
                icon: isTestRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.health_and_safety),
                label: Text(isTestRunning ? 'Testing...' : 'Test Connection'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// A secret input field with a reveal toggle that only appears while typing.
///
/// When no text has been entered, the field is always obscured and no toggle
/// is shown — preventing reveal of a previously saved credential. Once the
/// user starts typing, the eye icon appears so they can verify the new value.
class _SecretField extends StatefulWidget {
  const _SecretField({
    required this.controller,
    required this.labelText,
    required this.isSaved,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final String labelText;
  final bool isSaved;
  final TextInputAction textInputAction;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _obscure = true;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
        if (!hasText) _obscure = true; // reset when field is cleared
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: widget.labelText,
        border: const OutlineInputBorder(),
        hintText: widget.isSaved && !_hasText ? '••••••••' : null,
        floatingLabelBehavior: widget.isSaved && !_hasText
            ? FloatingLabelBehavior.always
            : FloatingLabelBehavior.auto,
        suffixIcon: _hasText
            ? IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
      ),
      textInputAction: widget.textInputAction,
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
