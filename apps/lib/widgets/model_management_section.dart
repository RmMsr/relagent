import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/model_catalog.dart';
import '/providers/model_download_provider.dart';
import '/providers/settings_provider.dart';
import '/voice/model_download_service.dart';

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
  bool _downloadedOnly = false;

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Models'),
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
                FilterChip(
                  label: const Text('Downloaded'),
                  selected: _downloadedOnly,
                  onSelected: (v) => setState(() => _downloadedOnly = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ModelList(type: ModelType.asr, filterQuery: _searchQuery, downloadedOnly: _downloadedOnly),
                _ModelList(type: ModelType.tts, filterQuery: _searchQuery, downloadedOnly: _downloadedOnly),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelList extends ConsumerStatefulWidget {
  final ModelType type;
  final String filterQuery;
  final bool downloadedOnly;

  const _ModelList({required this.type, this.filterQuery = '', this.downloadedOnly = false});

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
    final selectedId = widget.type == ModelType.asr
        ? settings.selectedAsrModelId
        : settings.selectedTtsModelId;

    double initialOffset = 0;
    if (selectedId != null) {
      final index = ModelCatalog.byType(widget.type)
          .indexWhere((e) => e.id == selectedId);
      if (index > 0) initialOffset = index * _cardHeight;
    }

    _scrollController = ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<CatalogEntry> _applyFilter(
    List<CatalogEntry> all,
    ModelDownloadState downloadState,
  ) {
    var results = all;
    if (widget.downloadedOnly) {
      results = results
          .where((e) =>
              downloadState.isDownloaded(e.id) ||
              downloadState.isDownloadingModel(e.id))
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
    final settings = ref.watch(settingsProvider);
    final entries = _applyFilter(ModelCatalog.byType(widget.type), downloadState);

    final selectedId = widget.type == ModelType.asr
        ? settings.selectedAsrModelId
        : settings.selectedTtsModelId;

    if (downloadState.isScanning) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final isDownloaded = downloadState.isDownloaded(entry.id);
              final isSelected = selectedId == entry.id;
              final isDownloading = downloadState.isDownloadingModel(entry.id);

              return _ModelEntryCard(
                entry: entry,
                isDownloaded: isDownloaded,
                isSelected: isSelected,
                isDownloading: isDownloading,
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
    if (entry.architecture == ModelArchitecture.offlineNemoTransducer) {
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
      child: InkWell(
        onTap: isDownloaded ? () => _selectModel(ref) : null,
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
                  if (isSelected)
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                ],
              ),
              const SizedBox(height: 2),
              Text(entry.id, style: muted),
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
                      Text('${progress!.percent}%',
                          style: theme.textTheme.bodySmall),
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
                  alignment: Alignment.centerRight,
                  child: isDownloaded
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isSelected)
                              TextButton(
                                onPressed: () => _selectModel(ref),
                                child: const Text('Select'),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _deleteModel(context, ref),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Delete',
                            ),
                          ],
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

  void _selectModel(WidgetRef ref) {
    final notifier = ref.read(settingsProvider.notifier);
    if (entry.type == ModelType.asr) {
      notifier.updateSelectedAsrModelId(entry.id);
    } else {
      notifier.updateSelectedTtsModelId(entry.id);
    }
  }

  Future<void> _deleteModel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text('Delete "${entry.displayName}"? '
            'You can re-download it later.'),
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
