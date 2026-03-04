// ignore_for_file: avoid_print
/// Applies hard filter criteria to untested voice model entries.
///
/// Entries that fail a criterion have their `notes` field updated with an
/// exclusion reason. The `status` field is not changed. The evaluator uses
/// the notes field to decide which entries to skip.
class VoiceCatalogFilter {
  static const _supportedLanguages = {
    'en', 'de', 'fr', 'es', 'it', 'nl', 'pl', 'ru', 'sv', 'pt', 'cs',
  };
  static const _maxDownloadSizeMb = 1000;
  static const _knownArchitectures = {
    'transducer', 'ctc', 'vitsPiper', 'kokoro', 'onlineNemoCtc',
    'offlineNemoTransducer',
  };

  /// Apply all filter criteria to [entries], returning the updated list.
  List<Map<String, dynamic>> filter(List<Map<String, dynamic>> entries) {
    var excluded = 0;

    for (final entry in entries) {
      if (entry['status'] != 'untested') continue;
      // Skip entries already excluded by a previous run.
      final existingNotes = entry['notes'] as String? ?? '';
      if (existingNotes.startsWith('excluded:')) continue;

      final reason = _checkExclusion(entry);
      if (reason != null) {
        entry['notes'] = reason;
        excluded++;
      }
    }

    print('[Filter] Excluded $excluded untested entries');
    return entries;
  }

  String? _checkExclusion(Map<String, dynamic> entry) {
    final sizeMb = entry['downloadSizeMb'] as int? ?? 0;
    if (sizeMb > _maxDownloadSizeMb) {
      return 'excluded: size ${sizeMb}MB exceeds 1GB limit';
    }

    final languages = (entry['languages'] as List<dynamic>? ?? [])
        .cast<String>()
        .toSet();
    if (languages.isNotEmpty &&
        languages.intersection(_supportedLanguages).isEmpty) {
      return 'excluded: no supported language';
    }

    final arch = entry['architecture'] as String? ?? '';
    if (arch.isNotEmpty && !_knownArchitectures.contains(arch)) {
      return 'excluded: unsupported architecture';
    }

    // Piper quality check: x_low or _low suffix in the download URL.
    if (arch == 'vitsPiper') {
      final url = entry['downloadUrl'] as String? ?? '';
      final id = entry['id'] as String? ?? '';
      if (id.contains('_low') || id.contains('x_low') ||
          url.contains('_low') || url.contains('x_low')) {
        return 'excluded: quality below medium';
      }
    }

    return null;
  }
}
