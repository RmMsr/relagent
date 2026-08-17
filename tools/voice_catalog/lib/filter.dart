// ignore_for_file: avoid_print
import 'entry_scope.dart';
import 'supported_architectures.dart';

/// Applies filter criteria to untested voice model entries.
///
/// Filter criteria (applied to all untested, non-excluded entries):
///   - Download size must be ≤ 1 GB
///   - Architecture must be runtime-supported, or genuinely unknown
///     (see [supportedArchitectures])
///   - Rockchip NPU models excluded (rk3xxx): contain .rknn files, not ONNX
///   - fp16 models excluded: ONNX Runtime crashes (SIGABRT) on float16 tensors
///   - Piper models: quality must be medium or higher (excludes _low / x_low)
///   - float32 models skipped when an int8 variant exists in the catalog
///
/// A catalog architecture of exactly 'unknown' is NOT excluded here — the
/// evaluator will attempt to infer the architecture from the downloaded
/// model's file structure as a last resort. But a *specific*, catalog-only
/// architecture label (e.g. 'senseVoice', 'zipformerOfflineTransducer') that
/// isn't in [supportedArchitectures] means we already know what the model
/// is and that this app can't run it — falling through to file-structure
/// guessing in that case is actively dangerous: the guess can't distinguish
/// e.g. an offline-exported Zipformer transducer from an online one (both
/// have encoder+decoder+joiner files), and forcing the wrong one through the
/// online recognizer builder is an uncatchable native crash, not a
/// recoverable Dart exception.
///
/// Checking these criteria is free — a pure function of fields already in
/// the catalog (size, architecture, id, whether an int8 sibling id exists),
/// no network or download involved. So every 'untested' entry in [scope] is
/// always re-checked fresh, including ones already marked excluded/skipped:
/// if the reason no longer applies (e.g. --classify just relabeled the
/// entry to a now-supported architecture), the note is cleared instead of
/// staying stuck forever. allIds (used for the int8-preferred check) always
/// covers the whole catalog regardless of scope.
class VoiceCatalogFilter {
  static const _maxDownloadSizeMb = 1000;

  VoiceCatalogFilter();

  /// Apply all filter criteria to [entries] within [scope].
  ///
  /// Prints a breakdown of exclusion counts per criterion.
  List<Map<String, dynamic>> filter(
    List<Map<String, dynamic>> entries, {
    EntryScope scope = const EntryScope(),
  }) {
    final allIds = {for (final e in entries) e['id'] as String? ?? ''};

    final untested = entries
        .where((e) => e['status'] == 'untested')
        .where(scope.matches)
        .toList();

    final exclusionCounts = <String, int>{};
    var cleared = 0;

    for (final entry in untested) {
      final currentNotes = entry['notes'] as String? ?? '';
      final wasExcluded = currentNotes.startsWith('excluded:') ||
          currentNotes.startsWith('skipped:');

      final reason = _checkExclusion(entry, allIds);
      if (reason != null) {
        entry['notes'] = reason;
        exclusionCounts[reason] = (exclusionCounts[reason] ?? 0) + 1;
      } else if (wasExcluded) {
        entry['notes'] = '';
        cleared++;
      }
    }

    final totalExcluded = exclusionCounts.values.fold(0, (a, b) => a + b);
    final candidates = untested.length - totalExcluded;

    print('[Filter] Criteria applied to ${untested.length} untested entries '
        'in scope:');
    for (final entry in exclusionCounts.entries) {
      print('[Filter]   ${entry.key.padRight(40)} ${entry.value}');
    }
    print('[Filter] ─────────────────────────────────────────');
    print('[Filter]   Total excluded:                   $totalExcluded');
    if (cleared > 0) {
      print('[Filter]   Re-included (no longer excluded):  $cleared');
    }
    print('[Filter]   Remaining:                         $candidates');

    return entries;
  }

  String? _checkExclusion(Map<String, dynamic> entry, Set<String> allIds) {
    final sizeMb = entry['downloadSizeMb'] as int? ?? 0;
    if (sizeMb > _maxDownloadSizeMb) {
      return 'excluded: size ${sizeMb}MB exceeds 1GB limit';
    }

    final arch = entry['architecture'] as String? ?? '';
    final id = entry['id'] as String? ?? '';

    // A specific, known-unsupported architecture label — don't let the
    // evaluator's file-structure guess near it (see class doc for why).
    if (arch.isNotEmpty &&
        arch != 'unknown' &&
        !supportedArchitectures.contains(arch)) {
      return 'excluded: architecture not yet supported ($arch)';
    }

    // Rockchip NPU models contain only .rknn files — not ONNX-compatible.
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
