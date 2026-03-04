// ignore_for_file: avoid_print

/// Applies filter criteria to untested voice model entries.
///
/// Filter criteria (applied to all untested, non-excluded entries):
///   - Download size must be ≤ 1 GB
///   - Rockchip NPU models excluded (rk3xxx): contain .rknn files, not ONNX
///   - fp16 models excluded: ONNX Runtime crashes (SIGABRT) on float16 tensors
///   - Piper models: quality must be medium or higher (excludes _low / x_low)
///   - float32 models skipped when an int8 variant exists in the catalog
///
/// Unknown architectures are NOT excluded here — the evaluator will attempt
/// to infer the architecture from the downloaded model's file structure.
///
/// Language filtering is intentionally excluded here — it is run-dependent
/// and applied at evaluation time by the evaluator instead.
class VoiceCatalogFilter {
  static const _maxDownloadSizeMb = 1000;

  VoiceCatalogFilter();

  /// Apply all filter criteria to [entries].
  ///
  /// Prints a breakdown of exclusion counts per criterion.
  List<Map<String, dynamic>> filter(List<Map<String, dynamic>> entries) {
    final allIds = {for (final e in entries) e['id'] as String? ?? ''};

    final untested = entries
        .where((e) => e['status'] == 'untested')
        .where((e) => !(e['notes'] as String? ?? '').startsWith('excluded:'))
        .where((e) => !(e['notes'] as String? ?? '').startsWith('skipped:'))
        .toList();

    final exclusionCounts = <String, int>{};

    for (final entry in untested) {
      final reason = _checkExclusion(entry, allIds);
      if (reason != null) {
        entry['notes'] = reason;
        exclusionCounts[reason] = (exclusionCounts[reason] ?? 0) + 1;
      }
    }

    final totalExcluded = exclusionCounts.values.fold(0, (a, b) => a + b);
    final candidates = untested.length - totalExcluded;

    print('[Filter] Criteria applied to ${untested.length} untested entries:');
    for (final entry in exclusionCounts.entries) {
      print('[Filter]   ${entry.key.padRight(40)} ${entry.value}');
    }
    print('[Filter] ─────────────────────────────────────────');
    print('[Filter]   Total excluded:                   $totalExcluded');
    print('[Filter]   Candidates for evaluation:        $candidates');

    return entries;
  }

  String? _checkExclusion(Map<String, dynamic> entry, Set<String> allIds) {
    final sizeMb = entry['downloadSizeMb'] as int? ?? 0;
    if (sizeMb > _maxDownloadSizeMb) {
      return 'excluded: size ${sizeMb}MB exceeds 1GB limit';
    }

    // Rockchip NPU models contain only .rknn files — not ONNX-compatible.
    final arch = entry['architecture'] as String? ?? '';
    final id = entry['id'] as String? ?? '';
    if (RegExp(r'-rk\d{4}-').hasMatch(id)) {
      return 'excluded: unsupported architecture';
    }

    // fp16 models cause ONNX Runtime to call terminate() (SIGABRT) — uncatchable.
    final url = entry['downloadUrl'] as String? ?? '';
    if (id.contains('-fp16') || url.contains('-fp16')) {
      return 'excluded: fp16 not supported';
    }

    if (arch == 'vitsPiper') {
      if (id.contains('_low') ||
          id.contains('x_low') ||
          url.contains('_low') ||
          url.contains('x_low')) {
        return 'excluded: quality below medium';
      }
    }

    // Skip float32 when a better int8 variant exists in the catalog.
    if (allIds.contains('$id-int8')) {
      return 'skipped: int8 variant preferred';
    }

    return null;
  }
}
