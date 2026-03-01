import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/model_catalog.dart';
import '/providers/model_download_provider.dart';
import '/providers/settings_provider.dart';
import '/voice/model_download_service.dart';

/// Voice Models section for the settings page.
/// Shows current selections and provides access to the model catalog browser.
class ModelManagementSection extends ConsumerWidget {
  const ModelManagementSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final downloadState = ref.watch(modelDownloadProvider);

    final activeAsr = settings.selectedAsrModelId != null
        ? ModelCatalog.findById(settings.selectedAsrModelId!)
        : null;
    final activeTts = settings.selectedTtsModelId != null
        ? ModelCatalog.findById(settings.selectedTtsModelId!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Voice Models',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _ModelStatusTile(
          label: 'Speech Recognition',
          model: activeAsr,
          fallbackLabel: 'Bundled model',
          onBrowse: () => _openCatalogBrowser(context, ModelType.asr),
        ),
        _ModelStatusTile(
          label: 'Text-to-Speech',
          model: activeTts,
          fallbackLabel: 'Bundled model',
          onBrowse: () => _openCatalogBrowser(context, ModelType.tts),
        ),
        if (downloadState.totalStorageBytes > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Storage used: ${_formatBytes(downloadState.totalStorageBytes)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  void _openCatalogBrowser(BuildContext context, ModelType type) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ModelCatalogBrowser(initialType: type),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ModelStatusTile extends StatelessWidget {
  final String label;
  final CatalogEntry? model;
  final String fallbackLabel;
  final VoidCallback onBrowse;

  const _ModelStatusTile({
    required this.label,
    required this.model,
    required this.fallbackLabel,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(model?.displayName ?? fallbackLabel),
      trailing: TextButton(
        onPressed: onBrowse,
        child: const Text('Browse'),
      ),
    );
  }
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialType == ModelType.asr ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _ModelList(type: ModelType.asr),
          _ModelList(type: ModelType.tts),
        ],
      ),
    );
  }
}

class _ModelList extends ConsumerWidget {
  final ModelType type;

  const _ModelList({required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ModelCatalog.byType(type);
    final downloadState = ref.watch(modelDownloadProvider);
    final settings = ref.watch(settingsProvider);

    final selectedId = type == ModelType.asr
        ? settings.selectedAsrModelId
        : settings.selectedTtsModelId;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isDownloaded = downloadState.isDownloaded(entry.id);
        final isSelected = selectedId == entry.id;
        final isDownloading = downloadState.activeDownload?.modelId == entry.id;

        return _ModelEntryCard(
          entry: entry,
          isDownloaded: isDownloaded,
          isSelected: isSelected,
          isDownloading: isDownloading,
          progress: isDownloading ? downloadState.activeDownload : null,
        );
      },
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

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
                  if (entry.supportsStreaming)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Chip(
                        label: const Text('Live'),
                        labelStyle: theme.textTheme.labelSmall,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                entry.languages.join(', '),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${entry.downloadSizeMb.round()} MB',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (isDownloading && progress != null) ...[
                    Expanded(
                      flex: 2,
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
                  ] else if (isDownloaded) ...[
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
                  ] else ...[
                    FilledButton.tonalIcon(
                      onPressed: () => _downloadModel(ref),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download'),
                    ),
                  ],
                ],
              ),
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
