import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/imported_model.dart';
import '/voice/imported_model_registry.dart';
import '/voice/imported_model_service.dart';

class ImportedModelsState {
  final List<ImportedModelEntry> entries;
  final bool isImporting;
  final String? operationError;

  const ImportedModelsState({
    this.entries = const [],
    this.isImporting = false,
    this.operationError,
  });

  ImportedModelsState copyWith({
    List<ImportedModelEntry>? entries,
    bool? isImporting,
    String? Function()? operationError,
  }) {
    return ImportedModelsState(
      entries: entries ?? this.entries,
      isImporting: isImporting ?? this.isImporting,
      operationError:
          operationError != null ? operationError() : this.operationError,
    );
  }
}

final importedModelServiceProvider = Provider<ImportedModelService>(
  (_) => ImportedModelService(),
);

final importedModelsProvider =
    NotifierProvider<ImportedModelsNotifier, ImportedModelsState>(
      ImportedModelsNotifier.new,
    );

class ImportedModelsNotifier extends Notifier<ImportedModelsState> {
  late final ImportedModelService _service;

  @override
  ImportedModelsState build() {
    _service = ref.watch(importedModelServiceProvider);
    return ImportedModelsState(
      entries: ImportedModelRegistry.entries,
    );
  }

  Future<void> importFromFile(File archive, ImportedModelEntry template) async {
    state = state.copyWith(isImporting: true, operationError: () => null);
    try {
      await _service.importModel(archive, template);
      state = state.copyWith(
        entries: ImportedModelRegistry.entries,
        isImporting: false,
      );
    } catch (e) {
      state = state.copyWith(
        isImporting: false,
        operationError: () => 'Import failed: $e',
      );
    }
  }

  Future<void> deleteModel(String id) async {
    try {
      await _service.deleteModel(id);
      state = state.copyWith(entries: ImportedModelRegistry.entries);
    } catch (e) {
      state = state.copyWith(operationError: () => 'Delete failed: $e');
    }
  }

  Future<void> updateModel(ImportedModelEntry entry) async {
    try {
      await ImportedModelRegistry.update(entry);
      state = state.copyWith(entries: ImportedModelRegistry.entries);
    } catch (e) {
      state = state.copyWith(operationError: () => 'Update failed: $e');
    }
  }

  void clearError() {
    state = state.copyWith(operationError: () => null);
  }
}
