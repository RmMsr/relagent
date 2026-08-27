import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '/models/imported_model.dart';
import '/models/model_catalog.dart';
import '/models/settings.dart';
import '/providers/credentials_pass_provider.dart';
import '/providers/imported_models_provider.dart';
import '/providers/model_download_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/settings_tab_request_provider.dart';
import '/utils/settings_navigation.dart';
import '/voice/imported_model_registry.dart';
import '/voice/imported_model_service.dart';
import '/voice/model_download_service.dart';
import 'import_model_sheet.dart';
import 'settings_apply_bar.dart';

enum _CatalogFilter {
  all,
  downloaded,
  selected;

  String get label => switch (this) {
    _CatalogFilter.all => 'All',
    _CatalogFilter.downloaded => 'Downloaded',
    _CatalogFilter.selected => 'Selected',
  };
}

/// Full-screen catalog browser for downloading and selecting models.
class ModelCatalogBrowser extends ConsumerStatefulWidget {
  final ModelType initialType;

  const ModelCatalogBrowser({super.key, required this.initialType});

  @override
  ConsumerState<ModelCatalogBrowser> createState() =>
      _ModelCatalogBrowserState();
}

class _ModelCatalogBrowserState extends ConsumerState<ModelCatalogBrowser>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;
  String _searchQuery = '';
  _CatalogFilter _filter = _CatalogFilter.all;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialType == ModelType.asr ? 0 : 1,
    );
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (ref.read(credentialsPassProvider)) {
      await commitPendingSettings(ref);
      if (mounted) context.go('/chat');
      return;
    }
    final closeAnyway = await showUnverifiedCredentialsDialog(context);
    if (!mounted) return;
    if (closeAnyway) {
      await commitPendingSettings(ref);
      if (mounted) context.go('/chat');
    } else {
      // Land back on the Connection tab regardless of whichever tab
      // Settings was last showing — that's where the credential/URL
      // fields the user needs to review actually live.
      ref.read(settingsTabRequestProvider.notifier).requestTab(0);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ModelDownloadState>(modelDownloadProvider, (prev, next) {
      final name = next.lastCompletedModelName;
      if (name != null && name != prev?.lastCompletedModelName) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name downloaded'),
            duration: const Duration(seconds: 3),
          ),
        );
        ref.read(modelDownloadProvider.notifier).clearCompletedNotification();
      }
    });

    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          context.pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Voice Models'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          actions: [_ImportModelAction(tabController: _tabController)],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Speech Recognition'),
              Tab(text: 'Text-to-Speech'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Filter by name, language…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<_CatalogFilter>(
                    value: _filter,
                    underline: const SizedBox.shrink(),
                    onChanged: (v) => setState(() => _filter = v!),
                    items: _CatalogFilter.values
                        .map(
                          (f) =>
                              DropdownMenuItem(value: f, child: Text(f.label)),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ModelList(
                    type: ModelType.asr,
                    filterQuery: _searchQuery,
                    filter: _filter,
                  ),
                  _ModelList(
                    type: ModelType.tts,
                    filterQuery: _searchQuery,
                    filter: _filter,
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SettingsApplyBar(onApply: _apply),
      ),
    );
  }
}

class _ModelList extends ConsumerStatefulWidget {
  final ModelType type;
  final String filterQuery;
  final _CatalogFilter filter;

  const _ModelList({
    required this.type,
    this.filterQuery = '',
    this.filter = _CatalogFilter.all,
  });

  @override
  ConsumerState<_ModelList> createState() => _ModelListState();
}

class _ModelListState extends ConsumerState<_ModelList> {
  late final ScrollController _scrollController;

  // Approximate height of a single model card including its vertical margin.
  static const double _cardHeight = 148.0;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    final defaultId = widget.type == ModelType.asr
        ? settings.defaultAsrModelId
        : settings.defaultTtsModelId;

    double initialOffset = 0;
    if (defaultId != null) {
      final index = ModelCatalog.byType(widget.type)
          .indexWhere((e) => e.id == defaultId);
      if (index > 0) initialOffset = index * _cardHeight;
    }

    _scrollController = ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// A model is "selected" (highlighted, and included by the "Selected"
  /// filter) when it's assigned/enabled for the current type or is that
  /// type's device default — the same shape of condition either way.
  bool _isAssignedOrDefault(String modelId, Settings settings) {
    if (widget.type == ModelType.asr) {
      return settings.asrQuickPickModelIds.contains(modelId) ||
          settings.defaultAsrModelId == modelId;
    }
    return settings.ttsLanguagePreferences.containsValue(modelId) ||
        settings.defaultTtsModelId == modelId;
  }

  List<CatalogEntry> _applyFilter(
    List<CatalogEntry> all,
    ModelDownloadState downloadState,
    Settings settings,
  ) {
    var results = all;
    switch (widget.filter) {
      case _CatalogFilter.downloaded:
        results = results
            .where(
              (e) =>
                  downloadState.isDownloaded(e.id) ||
                  downloadState.isDownloadingModel(e.id),
            )
            .toList();
      case _CatalogFilter.selected:
        results = results
            .where((e) => _isAssignedOrDefault(e.id, settings))
            .toList();
      case _CatalogFilter.all:
        break;
    }
    if (widget.filterQuery.isEmpty) return results;
    final q = widget.filterQuery.toLowerCase();
    return results
        .where(
          (e) =>
              e.displayName.toLowerCase().contains(q) ||
              e.languages.any((l) => l.toLowerCase().contains(q)) ||
              e.id.toLowerCase().contains(q),
        )
        .toList();
  }

  List<ImportedModelEntry> _applyImportedFilter(
    List<ImportedModelEntry> all,
    Settings settings,
  ) {
    // Imported models are always locally available (never affected by the
    // "Downloaded" filter, only "Selected").
    var results = all;
    if (widget.filter == _CatalogFilter.selected) {
      results = results
          .where((e) => _isAssignedOrDefault(e.id, settings))
          .toList();
    }
    if (widget.filterQuery.isEmpty) return results;
    final q = widget.filterQuery.toLowerCase();
    return results
        .where(
          (e) =>
              e.displayName.toLowerCase().contains(q) ||
              e.languages.any((l) => l.toLowerCase().contains(q)) ||
              e.id.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(modelDownloadProvider);
    final importedState = ref.watch(importedModelsProvider);
    final settings = ref.watch(settingsProvider);

    final catalogEntries = _applyFilter(
      ModelCatalog.byType(widget.type),
      downloadState,
      settings,
    );
    final importedEntries = _applyImportedFilter(
      ImportedModelRegistry.byType(widget.type),
      settings,
    );

    bool isSelected(String id) => _isAssignedOrDefault(id, settings);

    if (downloadState.isScanning) {
      return const Center(child: CircularProgressIndicator());
    }

    // Imported models first, then catalog entries.
    final totalCount = importedEntries.length + catalogEntries.length;

    return Column(
      children: [
        if (importedState.isImporting) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: totalCount,
            itemBuilder: (context, index) {
              if (index < importedEntries.length) {
                final entry = importedEntries[index];
                return _ImportedModelCard(
                  entry: entry,
                  isSelected: isSelected(entry.id),
                );
              }
              final entry = catalogEntries[index - importedEntries.length];
              return _ModelEntryCard(
                entry: entry,
                isDownloaded: downloadState.isDownloaded(entry.id),
                isSelected: isSelected(entry.id),
                isDownloading: downloadState.isDownloadingModel(entry.id),
                progress: downloadState.progressFor(entry.id),
              );
            },
          ),
        ),
        _StorageFooter(totalBytes: downloadState.totalStorageBytes),
      ],
    );
  }
}

/// Matches [CatalogEntry.languages] entries that can't be individually
/// assigned — mirrors `ModelCatalog._multiLanguageSentinel`.
const _multiLanguageSentinel = 'multi';

List<String> _concreteLanguages(List<String> languages) =>
    languages.where((l) => l != _multiLanguageSentinel).toList();

void _toggleTtsLanguageAssignment(
  SettingsNotifier notifier,
  String language,
  String modelId,
  bool checked,
) {
  checked
      ? notifier.assignTtsModelToLanguage(language, modelId)
      : notifier.removeTtsLanguagePreference(language);
}

/// Wildcard (star) control marking a model as its type's persisted device
/// default — the same widget for ASR and TTS (design D14/D17). Meaning
/// differs by type: for TTS, the model used when no language assignment
/// matches a response; for ASR, the model used when no session-only
/// quick-pick override is active.
class _DefaultModelButton extends ConsumerWidget {
  final String modelId;
  final ModelType type;

  const _DefaultModelButton({required this.modelId, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final isTts = type == ModelType.tts;
    final isDefault = isTts
        ? settings.defaultTtsModelId == modelId
        : settings.defaultAsrModelId == modelId;
    final label = isTts ? 'TTS voice' : 'ASR model';

    return IconButton(
      icon: Icon(isDefault ? Icons.star : Icons.star_border),
      iconSize: 20,
      color: isDefault ? theme.colorScheme.primary : null,
      onPressed: () {
        final newDefault = isDefault ? null : modelId;
        isTts
            ? notifier.setDefaultTtsModel(newDefault)
            : notifier.setDefaultAsrModel(newDefault);
      },
      visualDensity: VisualDensity.compact,
      tooltip: isDefault
          ? 'Remove as default $label'
          : 'Mark as default $label',
    );
  }
}

/// Single checkbox shown on every downloaded/available model card — the same
/// widget for ASR and TTS, one per model regardless of how many languages it
/// declares (design D15/D18). Meaning differs by type: for TTS, assigns the
/// model to its first declared language; for ASR, adds it to the mic
/// long-press quick-pick set. A TTS model whose only declared language is
/// the unenumerable "multi" sentinel has nothing concrete to assign, so it
/// gets no checkbox at all.
class _ModelToggleCheckbox extends ConsumerWidget {
  final String modelId;
  final ModelType type;
  final List<String> languages;

  const _ModelToggleCheckbox({
    required this.modelId,
    required this.type,
    required this.languages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final isTts = type == ModelType.tts;

    if (isTts) {
      final concrete = _concreteLanguages(languages);
      if (concrete.isEmpty) return const SizedBox.shrink();
      final language = concrete.first;
      final isAssigned = settings.ttsLanguagePreferences[language] == modelId;
      return Checkbox(
        value: isAssigned,
        onChanged: (checked) => _toggleTtsLanguageAssignment(
          notifier,
          language,
          modelId,
          checked == true,
        ),
        visualDensity: VisualDensity.compact,
      );
    }

    final isEnabled = settings.asrQuickPickModelIds.contains(modelId);
    return Checkbox(
      value: isEnabled,
      onChanged: (checked) =>
          notifier.setAsrQuickPickEnabled(modelId, checked == true),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StorageFooter extends StatelessWidget {
  final int totalBytes;

  const _StorageFooter({required this.totalBytes});

  @override
  Widget build(BuildContext context) {
    if (totalBytes <= 0) return const SizedBox.shrink();

    final label = totalBytes < 1024 * 1024
        ? '${(totalBytes / 1024).toStringAsFixed(1)} KB'
        : '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Total storage used by voice models: $label',
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ModelEntryCard extends ConsumerWidget {
  final CatalogEntry entry;
  final bool isDownloaded;
  final bool isSelected;
  final bool isDownloading;
  final DownloadProgress? progress;

  const _ModelEntryCard({
    required this.entry,
    required this.isDownloaded,
    required this.isSelected,
    required this.isDownloading,
    this.progress,
  });

  String? _modeLabel() {
    if (entry.type == ModelType.tts) return null;
    if (entry.supportsStreaming) return 'mode: live';
    if (entry.architecture == ModelArchitecture.offlineNemoTransducer ||
        entry.architecture == ModelArchitecture.whisper) {
      return 'mode: chunked';
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final modeLabel = _modeLabel();
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected ? theme.colorScheme.primaryContainer : null,
      elevation: isSelected ? 4 : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (entry.recommended)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.star,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      entry.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isDownloaded)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DefaultModelButton(
                          modelId: entry.id,
                          type: entry.type,
                        ),
                        _ModelToggleCheckbox(
                          modelId: entry.id,
                          type: entry.type,
                          languages: entry.languages,
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(entry.id, style: muted),
                  Text(architectureLabel(entry.architecture), style: muted),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                entry.languages.join(', '),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (isDownloading && progress != null)
                // Download in progress: full-width progress bar, no meta text.
                if (progress!.isExtracting)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text('Preparing…', style: muted),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: progress!.fraction,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${progress!.percent}%',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => _cancelDownload(ref),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Cancel',
                      ),
                    ],
                  )
              else ...[
                // Meta info and action button on separate lines to avoid
                // overflow when the button is wide relative to card width.
                Text(
                  [
                    '${entry.downloadSizeMb.round()} MB',
                    ?modeLabel,
                  ].join(' · '),
                  style: muted,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: isDownloaded
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _deleteModel(context, ref),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Delete',
                        )
                      : FilledButton.tonalIcon(
                          onPressed: () => _downloadModel(ref),
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Download'),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _downloadModel(WidgetRef ref) {
    ref.read(modelDownloadProvider.notifier).downloadModel(entry.id);
  }

  void _cancelDownload(WidgetRef ref) {
    ref.read(modelDownloadProvider.notifier).cancelDownload(entry.id);
  }

  Future<void> _deleteModel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text(
          'Delete "${entry.displayName}"? '
          'You can re-download it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Clear selection if this was the active model
      await ref.read(settingsProvider.notifier).clearModelSelection(entry.id);
      await ref.read(modelDownloadProvider.notifier).deleteModel(entry.id);
    }
  }
}

// ─── Imported model card ──────────────────────────────────────────────────────

class _ImportedModelCard extends ConsumerWidget {
  final ImportedModelEntry entry;
  final bool isSelected;

  const _ImportedModelCard({required this.entry, required this.isSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected ? theme.colorScheme.primaryContainer : null,
      elevation: isSelected ? 4 : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: const Text('Imported'),
                      labelStyle: theme.textTheme.labelSmall,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DefaultModelButton(modelId: entry.id, type: entry.type),
                      _ModelToggleCheckbox(
                        modelId: entry.id,
                        type: entry.type,
                        languages: entry.languages,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(entry.id, style: muted),
                  Text(architectureLabel(entry.architecture), style: muted),
                ],
              ),
              if (entry.languages.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  entry.languages.join(', '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _editMetadata(context, ref),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteModel(context, ref),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editMetadata(BuildContext context, WidgetRef ref) async {
    final detected = await ref
        .read(importedModelServiceProvider)
        .detectArchitectureForModel(entry.type, entry.id);
    if (!context.mounted) return;

    final updated = await showImportModelSheet(
      context,
      suggestedName: entry.displayName,
      detectedArchitecture: detected.detectedArchitecture,
      isAmbiguousShape: detected.isAmbiguousShape,
      initialArchitecture: entry.architecture,
      initialType: entry.type,
      initialLanguages: entry.languages,
    );
    if (updated == null || !context.mounted) return;

    await ref
        .read(importedModelsProvider.notifier)
        .updateModel(
          ImportedModelEntry(
            id: entry.id,
            displayName: updated.displayName,
            type: updated.type,
            architecture: updated.architecture,
            languages: updated.languages,
            importedAt: entry.importedAt,
          ),
        );
  }

  Future<void> _deleteModel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Imported Model'),
        content: Text(
          'Delete "${entry.displayName}"? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(settingsProvider.notifier).clearModelSelection(entry.id);
      await ref.read(importedModelsProvider.notifier).deleteModel(entry.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${entry.displayName}" deleted'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

// ─── Import action ─────────────────────────────────────────────────────────────

class _ImportModelAction extends ConsumerStatefulWidget {
  final TabController tabController;

  const _ImportModelAction({required this.tabController});

  @override
  ConsumerState<_ImportModelAction> createState() => _ImportModelActionState();
}

class _ImportModelActionState extends ConsumerState<_ImportModelAction> {
  bool _isPeeking = false;

  @override
  Widget build(BuildContext context) {
    final importedState = ref.watch(importedModelsProvider);
    final busy = _isPeeking || importedState.isImporting;
    return IconButton(
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.file_open),
      tooltip: 'Import from storage',
      onPressed: busy ? null : _startImport,
    );
  }

  Future<void> _startImport() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bz2', 'gz', 'tgz', 'zip', 'tar'],
      allowMultiple: false,
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    if (!mounted) return;

    final archive = File(path);
    final service = ref.read(importedModelServiceProvider);

    setState(() => _isPeeking = true);
    ArchivePeekResult peek;
    try {
      peek = await service.peekArchive(archive);
    } catch (e) {
      if (mounted) {
        setState(() => _isPeeking = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not read archive: $e')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isPeeking = false);

    if (!context.mounted) return;

    final suggestedName = result.files.first.name.replaceAll(
      RegExp(r'\.(tar\.bz2|tbz2|tar\.gz|tgz|tar|zip|bz2|gz)$'),
      '',
    );

    final initialType = widget.tabController.index == 0
        ? ModelType.asr
        : ModelType.tts;
    final template = await showImportModelSheet(
      context,
      suggestedName: suggestedName,
      detectedArchitecture: peek.detectedArchitecture,
      isAmbiguousShape: peek.isAmbiguousShape,
      initialType: initialType,
    );

    if (template == null || !mounted) return;

    await ref
        .read(importedModelsProvider.notifier)
        .importFromFile(archive, template);

    if (!mounted) return;

    final error = ref.read(importedModelsProvider).operationError;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      ref.read(importedModelsProvider.notifier).clearError();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${template.displayName}" imported'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
