import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  /// Max attempts for a single downloadModel() call, including the first.
  /// Downloads resume from where they left off (ModelDownloadService keeps
  /// the partial file between attempts), so a retry here just continues an
  /// interrupted transfer instead of redoing it from scratch.
  static const _maxAttempts = 4;
  static const _retryDelay = Duration(seconds: 2);

  late final ModelDownloadService _service;

  /// Model IDs whose in-progress download was cancelled by the user, so the
  /// retry loop in [downloadModel] knows to stop even if cancellation lands
  /// during the delay between attempts rather than mid-request.
  final _cancelledIds = <String>{};

  /// Number of downloads currently holding the wakelock. Downloads can run
  /// concurrently, so this is reference-counted rather than a plain bool —
  /// the lock should only release once every active download is done.
  int _wakelockHolders = 0;

  Future<void> _acquireWakelock() async {
    _wakelockHolders++;
    if (_wakelockHolders == 1) await WakelockPlus.enable();
  }

  Future<void> _releaseWakelock() async {
    if (_wakelockHolders > 0) _wakelockHolders--;
    if (_wakelockHolders == 0) await WakelockPlus.disable();
  }

  @override
  ModelDownloadState build() {
    _service = ref.watch(modelDownloadServiceProvider);
    _refreshDownloadedModels(initialScan: true);
    return const ModelDownloadState(isScanning: true);
  }

  Future<void> _refreshDownloadedModels({bool initialScan = false}) async {
    final downloaded = await _service.listDownloadedModels();
    final storage = await _service.totalStorageUsed();
    if (!ref.mounted) return;
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

    _cancelledIds.remove(modelId);
    _updateProgress(modelId, DownloadProgress(
      modelId: modelId,
      bytesReceived: 0,
      totalBytes: 0,
    ));
    state = state.copyWith(error: () => null);

    Object? lastError;
    // Held for the whole retry loop: on Android, the CPU going into deep
    // sleep once the screen locks can pause an in-flight socket, which is a
    // common cause of a long download dying partway through.
    await _acquireWakelock();
    try {
      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        if (_cancelledIds.contains(modelId)) break;
        try {
          await _service.downloadModel(
            entry,
            onProgress: (progress) => _updateProgress(modelId, progress),
          );
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          if (attempt == _maxAttempts || _cancelledIds.contains(modelId)) {
            break;
          }
          // The service keeps the partial file on disk, so this retry
          // resumes the transfer instead of starting over.
          await Future<void>.delayed(_retryDelay);
        }
      }
    } finally {
      await _releaseWakelock();
    }

    if (lastError != null) {
      _removeProgress(modelId);
      state = state.copyWith(error: () => 'Download failed: $lastError');
      return;
    }

    // Signal extracting phase while scanning filesystem.
    _updateProgress(modelId, DownloadProgress(
      modelId: modelId,
      bytesReceived: 0,
      totalBytes: 0,
      isExtracting: true,
    ));
    await _refreshDownloadedModels();
    _removeProgress(modelId);

    // downloadModel() also returns normally on a deliberate cancellation
    // (nothing thrown, nothing extracted), so only report completion if the
    // model actually ended up downloaded — otherwise a cancelled transfer
    // would show a misleading "downloaded" notification.
    if (state.isDownloaded(modelId)) {
      state = state.copyWith(lastCompletedModelName: () => entry.displayName);
    }
  }

  /// Cancel a specific download.
  void cancelDownload(String modelId) {
    _cancelledIds.add(modelId);
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
