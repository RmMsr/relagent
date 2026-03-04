import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/model_catalog.dart';
import '/voice/model_download_service.dart';

/// State for the model download manager.
class ModelDownloadState {
  /// IDs of fully downloaded models.
  final Set<String> downloadedModels;

  /// Per-model download progress. Empty when no downloads are active.
  final Map<String, DownloadProgress> activeDownloads;

  /// Error message from last failed operation.
  final String? error;

  /// Total storage used by downloaded models in bytes.
  final int totalStorageBytes;

  /// Display name of the most recently completed download, or null if none.
  /// Consumed once by the UI via [ModelDownloadNotifier.clearCompletedNotification].
  final String? lastCompletedModelName;

  /// Whether the initial filesystem scan is still in progress.
  final bool isScanning;

  const ModelDownloadState({
    this.downloadedModels = const {},
    this.activeDownloads = const {},
    this.error,
    this.totalStorageBytes = 0,
    this.lastCompletedModelName,
    this.isScanning = false,
  });

  ModelDownloadState copyWith({
    Set<String>? downloadedModels,
    Map<String, DownloadProgress>? activeDownloads,
    String? Function()? error,
    int? totalStorageBytes,
    String? Function()? lastCompletedModelName,
    bool? isScanning,
  }) {
    return ModelDownloadState(
      downloadedModels: downloadedModels ?? this.downloadedModels,
      activeDownloads: activeDownloads ?? this.activeDownloads,
      error: error != null ? error() : this.error,
      totalStorageBytes: totalStorageBytes ?? this.totalStorageBytes,
      lastCompletedModelName: lastCompletedModelName != null
          ? lastCompletedModelName()
          : this.lastCompletedModelName,
      isScanning: isScanning ?? this.isScanning,
    );
  }

  bool isDownloaded(String modelId) => downloadedModels.contains(modelId);
  bool isDownloadingModel(String modelId) => activeDownloads.containsKey(modelId);
  DownloadProgress? progressFor(String modelId) => activeDownloads[modelId];
}

final modelDownloadServiceProvider = Provider<ModelDownloadService>((ref) {
  return ModelDownloadService();
});

final modelDownloadProvider =
    NotifierProvider<ModelDownloadNotifier, ModelDownloadState>(() {
      return ModelDownloadNotifier();
    });

class ModelDownloadNotifier extends Notifier<ModelDownloadState> {
  late final ModelDownloadService _service;

  @override
  ModelDownloadState build() {
    _service = ref.watch(modelDownloadServiceProvider);
    _refreshDownloadedModels(initialScan: true);
    return const ModelDownloadState(isScanning: true);
  }

  Future<void> _refreshDownloadedModels({bool initialScan = false}) async {
    final downloaded = await _service.listDownloadedModels();
    final storage = await _service.totalStorageUsed();
    state = state.copyWith(
      downloadedModels: downloaded,
      totalStorageBytes: storage,
      isScanning: initialScan ? false : null,
    );
  }

  /// Start downloading a model. Multiple downloads can run concurrently.
  Future<void> downloadModel(String modelId) async {
    final entry = ModelCatalog.findById(modelId);
    if (entry == null) {
      state = state.copyWith(error: () => 'Model $modelId not found in catalog');
      return;
    }

    if (state.isDownloadingModel(modelId)) return;

    _updateProgress(modelId, DownloadProgress(
      modelId: modelId,
      bytesReceived: 0,
      totalBytes: 0,
    ));
    state = state.copyWith(error: () => null);

    try {
      await _service.downloadModel(
        entry,
        onProgress: (progress) => _updateProgress(modelId, progress),
      );

      // Signal extracting phase while scanning filesystem.
      _updateProgress(modelId, DownloadProgress(
        modelId: modelId,
        bytesReceived: 0,
        totalBytes: 0,
        isExtracting: true,
      ));
      await _refreshDownloadedModels();
      _removeProgress(modelId);
      state = state.copyWith(
        lastCompletedModelName: () => entry.displayName,
      );
    } catch (e) {
      _removeProgress(modelId);
      state = state.copyWith(error: () => 'Download failed: $e');
    }
  }

  /// Cancel a specific download.
  void cancelDownload(String modelId) {
    _service.cancelDownload(modelId);
    _removeProgress(modelId);
  }

  /// Delete a downloaded model.
  Future<void> deleteModel(String modelId) async {
    try {
      await _service.deleteModel(modelId);
      await _refreshDownloadedModels();
    } catch (e) {
      state = state.copyWith(error: () => 'Delete failed: $e');
    }
  }

  /// Clear the current error.
  void clearError() {
    state = state.copyWith(error: () => null);
  }

  /// Consume the last completed download notification.
  void clearCompletedNotification() {
    state = state.copyWith(lastCompletedModelName: () => null);
  }

  void _updateProgress(String modelId, DownloadProgress progress) {
    final updated = Map<String, DownloadProgress>.from(state.activeDownloads);
    updated[modelId] = progress;
    state = state.copyWith(activeDownloads: updated);
  }

  void _removeProgress(String modelId) {
    final updated = Map<String, DownloadProgress>.from(state.activeDownloads);
    updated.remove(modelId);
    state = state.copyWith(activeDownloads: updated);
  }
}
