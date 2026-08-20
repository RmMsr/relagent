import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:agentic_client/agentic_client.dart';
import '/models/model_catalog.dart';
import '/voice/imported_model_registry.dart';
import '/models/settings.dart';
import '/providers/credentials_pass_provider.dart';
import '/providers/pending_settings_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/settings_tab_request_provider.dart';
import '/providers/voice_service_provider.dart';
import '/services/api_health_check.dart';
import '/utils/settings_navigation.dart';
import '/voice/model_resolver.dart';
import '/widgets/error_copy_button.dart';
import '/widgets/import_model_sheet.dart' show architectureLabel;
import '/widgets/settings_apply_bar.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _tabControllerLength = 0;

  // Track each Autocomplete field's underlying controller instance so its
  // change-listener is attached exactly once, not re-added on every
  // rebuild — RawAutocomplete keeps this controller alive across rebuilds
  // of this State, so re-registering in fieldViewBuilder (which runs every
  // rebuild) would otherwise leak a duplicate listener each time. The
  // paired "_isSyncing*" flag distinguishes a programmatic resync (this
  // field being brought back in line with the shared draft, e.g. on first
  // build) from a genuine user edit, so only real edits invalidate
  // credentialsPass — a resync isn't a credential/URL change.
  TextEditingController? _chatUrlFieldController;
  bool _isSyncingChatUrlField = false;
  TextEditingController? _chatModelFieldController;
  bool _isSyncingChatModelField = false;
  TextEditingController? _engineUrlFieldController;
  bool _isSyncingEngineUrlField = false;

  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  final _formKey = GlobalKey<FormState>();
  HealthCheckResult? _healthCheckResult;
  bool _isHealthCheckRunning = false;
  bool _hasPassword = false;
  bool _chatBasicAuthEnabled = false;

  // Engine settings controllers
  late TextEditingController _engineUsernameController;
  late TextEditingController _enginePasswordController;
  late TextEditingController _engineApiKeyController;
  bool _hasEnginePassword = false;
  EngineHealthResult? _engineHealthCheckResult;
  bool _isEngineHealthCheckRunning = false;
  bool _engineBasicAuthEnabled = false;

  // Chat API key controller
  late TextEditingController _chatApiKeyController;

  // Prime message controller — a plain TextEditingController (rather than
  // relying on TextFormField.initialValue) so it can be resynced when the
  // draft is discarded out from under it (the smart-nav "Discard" dialog
  // choice); see the ref.listen in build().
  late TextEditingController _primeMessageController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _usernameController = TextEditingController(text: settings.username ?? '');
    _passwordController = TextEditingController();
    _chatBasicAuthEnabled = settings.username?.isNotEmpty ?? false;

    // Engine settings
    _engineUsernameController = TextEditingController(
      text: settings.engineUsername ?? '',
    );
    _enginePasswordController = TextEditingController();
    _engineApiKeyController = TextEditingController();
    _engineBasicAuthEnabled = settings.engineUsername?.isNotEmpty ?? false;

    // Chat API key
    _chatApiKeyController = TextEditingController();

    // Prime message — seeded once from the draft; kept in sync afterwards
    // via ref.listen in build().
    _primeMessageController = TextEditingController(
      text: ref.read(pendingSettingsProvider).primeMessage,
    );

    _usernameController.addListener(_invalidateCredentialsPass);
    _passwordController.addListener(_invalidateCredentialsPass);
    _chatApiKeyController.addListener(_invalidateCredentialsPass);
    _engineUsernameController.addListener(_invalidateCredentialsPass);
    _enginePasswordController.addListener(_invalidateCredentialsPass);
    _engineApiKeyController.addListener(_invalidateCredentialsPass);

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

  void _invalidateCredentialsPass() {
    ref.read(credentialsPassProvider.notifier).invalidate();
  }

  /// Returns the current [TabController], creating (or recreating, if
  /// `length` changed — e.g. voice capabilities became available while
  /// Settings was open) a fresh one as needed. `TabController.length` is
  /// fixed at construction, so a length change requires a new controller;
  /// this replaces the length-handling `DefaultTabController` used to do
  /// implicitly, now that the controller is explicit (needed so it can be
  /// driven externally via [settingsTabRequestProvider]).
  TabController _ensureTabController(int length) {
    if (_tabController == null || _tabControllerLength != length) {
      _tabController?.dispose();
      _tabController = TabController(length: length, vsync: this);
      _tabControllerLength = length;
    }
    return _tabController!;
  }

  bool _hasUnsavedCredentialChanges() {
    final settings = ref.read(settingsProvider);
    return _usernameController.text.trim() != (settings.username ?? '') ||
        _passwordController.text.isNotEmpty ||
        _chatApiKeyController.text.trim().isNotEmpty ||
        _chatBasicAuthEnabled != (settings.username?.isNotEmpty ?? false) ||
        _engineUsernameController.text.trim() !=
            (settings.engineUsername ?? '') ||
        _enginePasswordController.text.isNotEmpty ||
        _engineApiKeyController.text.trim().isNotEmpty ||
        _engineBasicAuthEnabled !=
            (settings.engineUsername?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _usernameController.removeListener(_invalidateCredentialsPass);
    _usernameController.dispose();
    _passwordController.removeListener(_invalidateCredentialsPass);
    _passwordController.dispose();
    _engineUsernameController.removeListener(_invalidateCredentialsPass);
    _engineUsernameController.dispose();
    _enginePasswordController.removeListener(_invalidateCredentialsPass);
    _enginePasswordController.dispose();
    _engineApiKeyController.removeListener(_invalidateCredentialsPass);
    _engineApiKeyController.dispose();
    _chatApiKeyController.removeListener(_invalidateCredentialsPass);
    _chatApiKeyController.dispose();
    _primeMessageController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (_isHealthCheckRunning) return;

    setState(() {
      _isHealthCheckRunning = true;
      _healthCheckResult = null;
    });

    final pending = ref.read(pendingSettingsProvider);
    final baseUrl = pending.simpleChatBaseUrl;
    final model = pending.simpleChatModel;
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

      ref.read(credentialsPassProvider.notifier).markVerified(result.isSuccess);
      setState(() {
        _healthCheckResult = result;
        _isHealthCheckRunning = false;
      });
    } catch (e) {
      ref.read(credentialsPassProvider.notifier).markVerified(false);
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

    final baseUrl = ref.read(pendingSettingsProvider).engineBaseUrl;
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
            : await notifier.getEnginePassword(url: baseUrl),
        apiKey: _engineApiKeyController.text.trim().isNotEmpty
            ? _engineApiKeyController.text.trim()
            : await notifier.getEngineApiKey(url: baseUrl),
      );

      ref.read(credentialsPassProvider.notifier).markVerified(result.isSuccess);
      setState(() {
        _engineHealthCheckResult = result;
        _isEngineHealthCheckRunning = false;
      });
    } catch (e) {
      ref.read(credentialsPassProvider.notifier).markVerified(false);
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
    _invalidateCredentialsPass();
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
    _invalidateCredentialsPass();
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
    final pending = ref.read(pendingSettingsProvider);
    final body =
        '{"messages": [{"role": "user", "content": "test"}], '
        '"model": "${pending.simpleChatModel}", '
        '"max_completion_tokens": 100}';
    final url = '${pending.simpleChatBaseUrl}/chat/completions';
    final usesBasicAuth = ref.read(settingsProvider).authType == AuthType.basic;

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: result.isSuccess
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: result.isSuccess ? Colors.green : Colors.red,
            ),
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
              _buildDebugInfo('URL', url),
              _buildDebugInfo('Body', body),
              if (result.httpStatusCode != null)
                _buildDebugInfo('Status', 'HTTP ${result.httpStatusCode}'),
              if (usesBasicAuth)
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
                if (result.realm != null)
                  _buildDebugInfo('Realm', result.realm!),
                if (result.loginUrl != null)
                  _buildDebugInfo('Login URL', result.loginUrl!),
              ],
              if (!result.isSuccess) const SizedBox(height: 16),
            ],
          ),
        ),
        if (!result.isSuccess)
          Positioned(
            right: 4,
            bottom: 4,
            child: ErrorCopyButton(
              text: [
                result.message,
                'Method: POST',
                'URL: $url',
                'Body: $body',
                if (result.httpStatusCode != null)
                  'Status: HTTP ${result.httpStatusCode}',
                if (usesBasicAuth)
                  'Auth: Basic ${_usernameController.text.isNotEmpty ? _usernameController.text : "(no username)"}',
                if (result.requiresAuth) ...[
                  'Detected Auth Type: ${result.detectedAuthType?.name.toUpperCase() ?? "Unknown"}',
                  if (result.realm != null) 'Realm: ${result.realm}',
                  if (result.loginUrl != null) 'Login URL: ${result.loginUrl}',
                ],
              ].join('\n'),
            ),
          ),
      ],
    );
  }

  Widget _buildEngineHealthPanel() {
    final result = _engineHealthCheckResult!;
    final pending = ref.read(pendingSettingsProvider);
    final url = '${pending.engineBaseUrl}/api/v1/status';

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: result.isSuccess
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: result.isSuccess ? Colors.green : Colors.red,
            ),
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
              _buildDebugInfo('URL', url),
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
              if (!result.isSuccess) const SizedBox(height: 16),
            ],
          ),
        ),
        if (!result.isSuccess)
          Positioned(
            right: 4,
            bottom: 4,
            child: ErrorCopyButton(
              text: [
                result.message,
                'Method: GET',
                'URL: $url',
                if (result.httpStatusCode != null)
                  'Status: HTTP ${result.httpStatusCode}',
                if (result.engineName != null) 'Engine: ${result.engineName}',
                if (result.engineVersion != null)
                  'Version: ${result.engineVersion}',
                if (result.requiresAuth && result.detectedAuthType != null)
                  'Detected Auth Type: ${result.detectedAuthType!.name.toUpperCase()}',
              ].join('\n'),
            ),
          ),
      ],
    );
  }

  Future<void> _apply() async {
    if (_formKey.currentState != null && !_formKey.currentState!.validate())
      return;

    final settingsNotifier = ref.read(settingsProvider.notifier);
    final settings = ref.read(settingsProvider);
    final pending = ref.read(pendingSettingsProvider);

    // Save simple chat authentication credentials if changed
    if (_usernameController.text.trim() != (settings.username ?? '')) {
      await settingsNotifier.updateUsername(_usernameController.text.trim());
    }

    if (_passwordController.text.isNotEmpty) {
      await settingsNotifier.setPassword(_passwordController.text);
      setState(() => _hasPassword = true);
    }

    // Commit the engine base URL before any engine credential writes below
    // (matching the original save order): updateEngineBaseUrl resets
    // engineAuthType/engineUsername/engineHasApiKey when the URL changes
    // (settings_provider.dart), and setEnginePassword/setEngineApiKey store
    // secrets keyed by the *current* engineBaseUrl. Committing it here first
    // means those writes land under the new URL and don't get clobbered by
    // commitPendingSettings' own engineBaseUrl commit — which becomes a
    // no-op below since settings.engineBaseUrl already matches
    // pending.engineBaseUrl by the time commitPendingSettings reads it.
    if (pending.engineBaseUrl != settings.engineBaseUrl) {
      await settingsNotifier.updateEngineBaseUrl(pending.engineBaseUrl);
    }

    // Save engine credential fields (not part of the shared draft — see
    // Global Constraints)
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

    // Everything else still staged — engine URL (above), chat base
    // URL/model/prime message — is the shared draft, committed the same
    // way regardless of which screen's Apply button was pressed.
    final success = await commitPendingSettings(ref);

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

    // If the currently-active connection settings are already trusted (no
    // relevant field changed since the last time they passed), skip the
    // live check entirely and just leave — this is what keeps Apply a true
    // single tap on the common "nothing credential-relevant changed" path.
    if (ref.read(credentialsPassProvider)) {
      if (mounted) context.go('/chat');
      return;
    }

    // Not yet verified since the last relevant change — run a live health
    // check for the active backend before leaving.
    final updatedSettings = ref.read(settingsProvider);

    try {
      bool isSuccess;
      String failureMessage;

      if (updatedSettings.selectedBackend == ChatBackendType.relagentEngine) {
        final service = EngineHealthCheckService();
        final result = await service.checkStatus(
          baseUrl: updatedSettings.engineBaseUrl,
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
          baseUrl: updatedSettings.simpleChatBaseUrl,
          model: updatedSettings.simpleChatModel,
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

      ref.read(credentialsPassProvider.notifier).markVerified(isSuccess);

      if (mounted) {
        if (isSuccess) {
          context.go('/chat');
        } else {
          await _showHealthCheckFailureDialog(
            'Connection test failed: $failureMessage',
          );
        }
      }
    } catch (e) {
      ref.read(credentialsPassProvider.notifier).markVerified(false);
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
      context.go('/chat');
    }
  }

  Widget _modelSubtitle(BuildContext context, String? id) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    if (id == null) {
      return const Text('None');
    }
    final entry = ModelCatalog.findById(id);
    if (entry != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${entry.displayName} · ${entry.downloadSizeMb.round()} MB'),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(id, style: muted),
              Text(architectureLabel(entry.architecture), style: muted),
            ],
          ),
        ],
      );
    }
    final imported = ImportedModelRegistry.findById(id);
    if (imported != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${imported.displayName} · Imported'),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(id, style: muted),
              Text(architectureLabel(imported.architecture), style: muted),
            ],
          ),
        ],
      );
    }
    return Text(id);
  }

  @override
  Widget build(BuildContext context) {
    // Prime Message has no fieldViewBuilder to hook a post-frame resync
    // into (unlike the Autocomplete-backed fields), so keep its controller
    // in sync with the draft here instead — covers the smart-nav "Discard"
    // dialog choice, which reverts pending.primeMessage out from under the
    // field. The equality guard avoids fighting the user's own typing,
    // which already wrote this same value into the draft via onChanged.
    ref.listen<Settings>(pendingSettingsProvider, (previous, next) {
      if (_primeMessageController.text != next.primeMessage) {
        _primeMessageController.text = next.primeMessage;
      }
    });

    final settings = ref.watch(settingsProvider);
    final pending = ref.watch(pendingSettingsProvider);
    // credentialsPassProvider is autoDispose and only ever ref.read elsewhere
    // (in _apply() and the invalidate/markVerified call sites) — without a
    // watcher it disposes and resets to its default (true) the moment
    // nothing is subscribed, which happens between an invalidating edit and
    // the next Apply tap. Watching it here keeps it alive for the whole
    // Settings flow, the same way `pending` above is kept alive.
    ref.watch(credentialsPassProvider);
    // Kept alive the same way as credentialsPassProvider above. Voice
    // Models' "Review Settings" action sets this to request landing on the
    // Connection tab (index 0) regardless of whichever tab was last active
    // here; consumed and cleared as soon as it's applied below.
    ref.watch(settingsTabRequestProvider);
    ref.listen<int?>(settingsTabRequestProvider, (previous, next) {
      if (next != null) {
        if (_tabController != null && next < _tabController!.length) {
          _tabController!.index = next;
        }
        ref.read(settingsTabRequestProvider.notifier).clear();
      }
    });
    final voiceCapabilities = ref.watch(voiceCapabilitiesProvider);
    final hasVoice =
        voiceCapabilities.isAsrAvailable || voiceCapabilities.isTtsAvailable;
    final hasFeatures = voiceCapabilities.isBackgroundListeningAvailable;
    final urlSuggestions = settings.history
        .map((entry) => entry.url)
        .toSet()
        .toList();
    final modelSuggestions = settings.history
        .map((entry) => entry.model)
        .toSet()
        .toList();

    final tabs = <Tab>[
      const Tab(text: 'Connection'),
      if (hasVoice) const Tab(text: 'Voice'),
      if (hasFeatures) const Tab(text: 'Features'),
    ];

    final tabViews = <Widget>[
      // Connection tab
      Form(
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
                _invalidateCredentialsPass();
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
                  ref
                      .read(pendingSettingsProvider.notifier)
                      .updateDraft(
                        (s) => s.copyWith(simpleChatBaseUrl: selection),
                      );
                  _invalidateCredentialsPass();
                },
                fieldViewBuilder:
                    (
                      BuildContext context,
                      TextEditingController fieldTextEditingController,
                      FocusNode fieldFocusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      if (_chatUrlFieldController !=
                          fieldTextEditingController) {
                        _chatUrlFieldController = fieldTextEditingController;
                        fieldTextEditingController.addListener(() {
                          if (_isSyncingChatUrlField) return;
                          ref
                              .read(pendingSettingsProvider.notifier)
                              .updateDraft(
                                (s) => s.copyWith(
                                  simpleChatBaseUrl:
                                      fieldTextEditingController.text,
                                ),
                              );
                          _invalidateCredentialsPass();
                        });
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (fieldTextEditingController.text !=
                            pending.simpleChatBaseUrl) {
                          _isSyncingChatUrlField = true;
                          fieldTextEditingController.text =
                              pending.simpleChatBaseUrl;
                          _isSyncingChatUrlField = false;
                        }
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
                  ref
                      .read(pendingSettingsProvider.notifier)
                      .updateDraft(
                        (s) => s.copyWith(simpleChatModel: selection),
                      );
                  _invalidateCredentialsPass();
                },
                fieldViewBuilder:
                    (
                      BuildContext context,
                      TextEditingController fieldTextEditingController,
                      FocusNode fieldFocusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      if (_chatModelFieldController !=
                          fieldTextEditingController) {
                        _chatModelFieldController = fieldTextEditingController;
                        fieldTextEditingController.addListener(() {
                          if (_isSyncingChatModelField) return;
                          ref
                              .read(pendingSettingsProvider.notifier)
                              .updateDraft(
                                (s) => s.copyWith(
                                  simpleChatModel:
                                      fieldTextEditingController.text,
                                ),
                              );
                          _invalidateCredentialsPass();
                        });
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (fieldTextEditingController.text !=
                            pending.simpleChatModel) {
                          _isSyncingChatModelField = true;
                          fieldTextEditingController.text =
                              pending.simpleChatModel;
                          _isSyncingChatModelField = false;
                        }
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
                onChanged: (v) => ref
                    .read(pendingSettingsProvider.notifier)
                    .updateDraft((s) => s.copyWith(primeMessage: v)),
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
                onBasicAuthToggleChanged: (v) {
                  setState(() => _chatBasicAuthEnabled = v);
                  _invalidateCredentialsPass();
                },
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
              _AutocompleteWithFocusLoss<EngineUrlEntry>(
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
                                option.url.isEmpty
                                    ? '(same origin)'
                                    : option.url,
                                style: option.url.isEmpty
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
                onSelected: (EngineUrlEntry selection) {
                  ref
                      .read(pendingSettingsProvider.notifier)
                      .updateDraft(
                        (s) => s.copyWith(engineBaseUrl: selection.url),
                      );
                  _engineBasicAuthEnabled =
                      selection.authType == AuthType.basic;
                  _engineUsernameController.text = selection.username ?? '';
                  _enginePasswordController.clear();
                  _engineApiKeyController.clear();
                  _hasEnginePassword = false;
                  _invalidateCredentialsPass();
                },
                fieldViewBuilder:
                    (
                      BuildContext context,
                      TextEditingController fieldTextEditingController,
                      FocusNode fieldFocusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      if (_engineUrlFieldController !=
                          fieldTextEditingController) {
                        _engineUrlFieldController = fieldTextEditingController;
                        fieldTextEditingController.addListener(() {
                          if (_isSyncingEngineUrlField) return;
                          ref
                              .read(pendingSettingsProvider.notifier)
                              .updateDraft(
                                (s) => s.copyWith(
                                  engineBaseUrl:
                                      fieldTextEditingController.text,
                                ),
                              );
                          _invalidateCredentialsPass();
                        });
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (fieldTextEditingController.text !=
                            pending.engineBaseUrl) {
                          _isSyncingEngineUrlField = true;
                          fieldTextEditingController.text =
                              pending.engineBaseUrl;
                          _isSyncingEngineUrlField = false;
                        }
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
                onBasicAuthToggleChanged: (v) {
                  setState(() => _engineBasicAuthEnabled = v);
                  _invalidateCredentialsPass();
                },
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
          ],
        ),
      ),
      // Voice tab (conditional)
      if (hasVoice)
        ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mic),
              title: const Text('Speech Recognition'),
              subtitle: _modelSubtitle(context, settings.selectedAsrModelId),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/voice-models', extra: 0),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.record_voice_over),
              title: const Text('Text-to-Speech'),
              subtitle: _modelSubtitle(context, settings.selectedTtsModelId),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/voice-models', extra: 1),
            ),
            const SizedBox(height: 16),
            Text(
              'TTS Speed: ${settings.ttsSpeed.toStringAsFixed(2)}x',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: settings.ttsSpeed,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              label: '${settings.ttsSpeed.toStringAsFixed(2)}x',
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateTtsSpeed(value);
              },
            ),
            Text(
              'Controls playback speed (0.5x - 2.0x)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (getSelectedTtsSpeakerCount(settings) > 1) ...[
              const SizedBox(height: 16),
              Text(
                'TTS Speaker ID: ${settings.ttsSpeakerId}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: settings.ttsSpeakerId.toDouble(),
                min: 0,
                max: (getSelectedTtsSpeakerCount(settings) - 1).toDouble(),
                divisions: getSelectedTtsSpeakerCount(settings) - 1,
                label: '${settings.ttsSpeakerId}',
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateTtsSpeakerId(v.round()),
              ),
            ],
          ],
        ),
      // Features tab
      if (hasFeatures)
        ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (voiceCapabilities.isBackgroundListeningAvailable) ...[
              SwitchListTile(
                title: Row(
                  children: [
                    const Text('Continuous Voice'),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Experimental',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: const Text(
                  'Enables continuous recording and auto-playback modes',
                ),
                value: settings.continuousVoiceEnabled,
                onChanged: (value) {
                  ref
                      .read(settingsProvider.notifier)
                      .updateContinuousVoiceEnabled(value);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'This feature is experimental and may be unreliable. '
                  'Background service currently implemented on Android only.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (settings.continuousVoiceEnabled) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<BackgroundListeningDuration>(
                    initialValue: settings.backgroundListeningDuration,
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
                    onChanged: (newValue) {
                      if (newValue != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .updateBackgroundListeningDuration(newValue);
                      }
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
    ]; // end tabViews

    final tabController = _ensureTabController(tabs.length);
    final tabBar = TabBar(controller: tabController, tabs: tabs);

    return Focus(
      autofocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          smartBack(
            context,
            ref,
            hasExtraPendingChanges: _hasUnsavedCredentialChanges,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          automaticallyImplyLeading: false,
          leading: ExcludeFocus(
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => smartBack(
                context,
                ref,
                hasExtraPendingChanges: _hasUnsavedCredentialChanges,
              ),
            ),
          ),
          bottom: tabs.length > 1
              ? PreferredSize(
                  preferredSize: tabBar.preferredSize,
                  child: tabBar,
                )
              : null,
        ),
        body: TabBarView(controller: tabController, children: tabViews),
        bottomNavigationBar: SettingsApplyBar(onApply: _apply),
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
    _internalFocusNode?.onKeyEvent = null;
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
          _internalFocusNode?.onKeyEvent = null;
          _internalFocusNode = focusNode;
          focusNode.addListener(_onFocusChange);
          focusNode.onKeyEvent = (node, event) {
            if (event is KeyDownEvent && _showOptions) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                setState(() => _showOptions = false);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.tab) {
                setState(() => _showOptions = false);
                if (HardwareKeyboard.instance.isShiftPressed) {
                  FocusScope.of(context).previousFocus();
                } else {
                  FocusScope.of(context).nextFocus();
                }
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          };
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
