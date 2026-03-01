import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/config/app_config.dart';
import '/models/model_catalog.dart';
import '/providers/model_download_provider.dart';
import '/providers/settings_provider.dart';
import '/voice/model_download_service.dart';

/// Full-screen model selection with ASR and TTS tabs.
class ModelSelectionPage extends ConsumerWidget {
  final int initialTab;

  const ModelSelectionPage({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Voice Models'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Speech Recognition'),
              Tab(text: 'Text-to-Speech'),
            ],
          ),
        ),
        body: const TabBarView(children: [_AsrModelList(), _TtsModelList()]),
      ),
    );
  }
}

class _AsrModelList extends ConsumerWidget {
  const _AsrModelList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final downloadState = ref.watch(modelDownloadProvider);
    final asrEntries = ModelCatalog.byType(ModelType.asr);

    return ListView(
      children: [
        if (AppConfig.speechRecognitionStreamingAsrModelName != null)
          _BundledModelTile(
            label:
                'Bundled: ${AppConfig.speechRecognitionStreamingAsrModelName}',
            isSelected: settings.selectedAsrModelId == null,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .updateSelectedAsrModelId(null),
          ),
        ...asrEntries.map(
          (entry) => _CatalogModelTile(
            entry: entry,
            isDownloaded: downloadState.isDownloaded(entry.id),
            isSelected: settings.selectedAsrModelId == entry.id,
            isDownloading: downloadState.activeDownload?.modelId == entry.id,
            progress: downloadState.activeDownload?.modelId == entry.id
                ? downloadState.activeDownload
                : null,
            onSelect: () => ref
                .read(settingsProvider.notifier)
                .updateSelectedAsrModelId(entry.id),
            onDownload: () => ref
                .read(modelDownloadProvider.notifier)
                .downloadModel(entry.id),
            onCancel: () => ref
                .read(modelDownloadProvider.notifier)
                .cancelDownload(entry.id),
            onDelete: () => _confirmDelete(context, ref, entry),
          ),
        ),
        _StorageFooter(downloadState: downloadState),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CatalogEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text(
          'Delete "${entry.displayName}"? You can re-download it later.',
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
      await ref.read(settingsProvider.notifier).clearModelSelection(entry.id);
      await ref.read(modelDownloadProvider.notifier).deleteModel(entry.id);
    }
  }
}

class _TtsModelList extends ConsumerWidget {
  const _TtsModelList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final downloadState = ref.watch(modelDownloadProvider);
    final ttsEntries = ModelCatalog.byType(ModelType.tts);

    return ListView(
      children: [
        if (AppConfig.ttsModelName != null)
          _BundledModelTile(
            label: 'Bundled: ${AppConfig.ttsModelName}',
            isSelected: settings.selectedTtsModelId == null,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .updateSelectedTtsModelId(null),
          ),
        ...ttsEntries.map(
          (entry) => _CatalogModelTile(
            entry: entry,
            isDownloaded: downloadState.isDownloaded(entry.id),
            isSelected: settings.selectedTtsModelId == entry.id,
            isDownloading: downloadState.activeDownload?.modelId == entry.id,
            progress: downloadState.activeDownload?.modelId == entry.id
                ? downloadState.activeDownload
                : null,
            onSelect: () => ref
                .read(settingsProvider.notifier)
                .updateSelectedTtsModelId(entry.id),
            onDownload: () => ref
                .read(modelDownloadProvider.notifier)
                .downloadModel(entry.id),
            onCancel: () => ref
                .read(modelDownloadProvider.notifier)
                .cancelDownload(entry.id),
            onDelete: () => _confirmDelete(context, ref, entry),
          ),
        ),
        _StorageFooter(downloadState: downloadState),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CatalogEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text(
          'Delete "${entry.displayName}"? You can re-download it later.',
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
      await ref.read(settingsProvider.notifier).clearModelSelection(entry.id);
      await ref.read(modelDownloadProvider.notifier).deleteModel(entry.id);
    }
  }
}

/// Tile for the bundled (asset) model option.
class _BundledModelTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BundledModelTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      tileColor: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isSelected ? theme.colorScheme.primary : null,
      ),
      title: Text(label),
      subtitle: const Text('Included with app'),
      onTap: onTap,
    );
  }
}

/// Tile for a downloadable catalog model.
class _CatalogModelTile extends StatelessWidget {
  final CatalogEntry entry;
  final bool isDownloaded;
  final bool isSelected;
  final bool isDownloading;
  final DownloadProgress? progress;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _CatalogModelTile({
    required this.entry,
    required this.isDownloaded,
    required this.isSelected,
    required this.isDownloading,
    this.progress,
    required this.onSelect,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAvailable = isDownloaded;

    return Column(
      children: [
        ListTile(
          tileColor: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : null,
          leading: Icon(
            isSelected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: isSelected
                ? theme.colorScheme.primary
                : (isAvailable ? null : theme.disabledColor),
          ),
          title: Text(
            entry.displayName,
            style: TextStyle(color: isAvailable ? null : theme.disabledColor),
          ),
          subtitle: isDownloading && progress != null
              ? Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(value: progress!.fraction),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${progress!.percent}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                )
              : Text(
                  '${entry.languages.join(", ")} · ${entry.downloadSizeMb.round()} MB',
                  style: TextStyle(
                    color: isAvailable ? null : theme.disabledColor,
                  ),
                ),
          trailing: _buildTrailing(theme),
          onTap: isAvailable ? onSelect : null,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
          child: Text(
            [
              entry.origin,
              entry.license,
              entry.releaseDate,
              if (entry.speakerCount > 1) '${entry.speakerCount} speakers',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget? _buildTrailing(ThemeData theme) {
    if (isDownloading) {
      return IconButton(
        icon: const Icon(Icons.close),
        onPressed: onCancel,
        tooltip: 'Cancel',
      );
    }

    if (isDownloaded) {
      return IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
        tooltip: 'Delete',
      );
    }

    return IconButton(
      icon: const Icon(Icons.download),
      onPressed: onDownload,
      tooltip: 'Download (${entry.downloadSizeMb.round()} MB)',
    );
  }
}

class _StorageFooter extends StatelessWidget {
  final ModelDownloadState downloadState;

  const _StorageFooter({required this.downloadState});

  @override
  Widget build(BuildContext context) {
    if (downloadState.totalStorageBytes <= 0) return const SizedBox.shrink();

    final bytes = downloadState.totalStorageBytes;
    final label = bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

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
