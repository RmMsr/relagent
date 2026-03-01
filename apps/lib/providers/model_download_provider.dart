import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/model_catalog.dart';
import '/voice/model_download_service.dart';

/// State for the model download manager.
class ModelDownloadState {
  /// IDs of fully downloaded models.
  final Set<String> downloadedModels;

  /// Active download progress (null if no download in progress).
  final DownloadProgress? activeDownload;

  /// Error message from last failed operation.
  final String? error;

  /// Total storage used by downloaded models in bytes.
  final int totalStorageBytes;

  const ModelDownloadState({
    this.downloadedModels = const {},
    this.activeDownload,
    this.error,
    this.totalStorageBytes = 0,
  });

  ModelDownloadState copyWith({
    Set<String>? downloadedModels,
    DownloadProgress? Function()? activeDownload,
    String? Function()? error,
    int? totalStorageBytes,
  }) {
    return ModelDownloadState(
      downloadedModels: downloadedModels ?? this.downloadedModels,
      activeDownload: activeDownload != null
          ? activeDownload()
          : this.activeDownload,
      error: error != null ? error() : this.error,
      totalStorageBytes: totalStorageBytes ?? this.totalStorageBytes,
    );
  }

  bool isDownloaded(String modelId) => downloadedModels.contains(modelId);
  bool get isDownloading => activeDownload != null;
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
    // Scan for downloaded models on initialization
    _refreshDownloadedModels();
    return const ModelDownloadState();
  }

  Future<void> _refreshDownloadedModels() async {
    final downloaded = await _service.listDownloadedModels();
    final storage = await _service.totalStorageUsed();
    state = state.copyWith(
      downloadedModels: downloaded,
      totalStorageBytes: storage,
    );
  }

  /// Start downloading a model from the catalog.
  Future<void> downloadModel(String modelId) async {
    final entry = ModelCatalog.findById(modelId);
    if (entry == null) {
      state = state.copyWith(
        error: () => 'Model $modelId not found in catalog',
      );
      return;
    }

    if (state.isDownloading) {
      state = state.copyWith(error: () => 'A download is already in progress');
      return;
    }

    state = state.copyWith(
      activeDownload: () =>
          DownloadProgress(modelId: modelId, bytesReceived: 0, totalBytes: 0),
      error: () => null,
    );

    try {
      await _service.downloadModel(
        entry,
        onProgress: (progress) {
          state = state.copyWith(activeDownload: () => progress);
        },
      );

      // Download complete - refresh model list
      state = state.copyWith(activeDownload: () => null);
      await _refreshDownloadedModels();
    } catch (e) {
      state = state.copyWith(
        activeDownload: () => null,
        error: () => 'Download failed: $e',
      );
    }
  }

  /// Cancel the active download.
  void cancelDownload(String modelId) {
    _service.cancelDownload(modelId);
    state = state.copyWith(activeDownload: () => null);
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
}
