// ignore_for_file: avoid_print
import 'dart:math';

/// Prints a four-column status table and entry lists for the voice model catalog.
///
/// Columns: ASR and TTS counts for the language filter vs all entries.
/// Pass an empty [languages] set to match all entries (no language filter).
class VoiceCatalogStatusReporter {
  final Set<String> languages;

  VoiceCatalogStatusReporter({required this.languages});

  void report(List<Map<String, dynamic>> entries) {
    final allAsr = _count(entries, typeFilter: 'asr');
    final allTts = _count(entries, typeFilter: 'tts');

    if (languages.isEmpty) {
      _printTable('All', allAsr, allTts, allAsr, allTts, showSelected: false);
    } else {
      final selected = entries.where(_matchesLanguage).toList();
      final selAsr = _count(selected, typeFilter: 'asr');
      final selTts = _count(selected, typeFilter: 'tts');
      final selLabel = '[${(languages.toList()..sort()).join(',')}]';
      _printTable(selLabel, selAsr, selTts, allAsr, allTts);
    }
  }

  /// Print all entries matching [state] and the language filter.
  ///
  /// Valid states: ignored, pending, failed, approved.
  /// When [namesOnly] is true, prints just the id per line for shell piping.
  void list(List<Map<String, dynamic>> entries, String state,
      {bool namesOnly = false, bool withNotes = false, String? typeFilter}) {
    final candidates = entries
        .where(_matchesLanguage)
        .where((e) =>
            typeFilter == null || (e['type'] as String? ?? '') == typeFilter)
        .toList();

    bool matches(Map<String, dynamic> e) {
      final status = e['status'] as String? ?? '';
      final notes = e['notes'] as String? ?? '';
      final isExcluded = status == 'untested' &&
          (notes.startsWith('excluded:') || notes.startsWith('skipped:'));
      return switch (state) {
        'ignored' => isExcluded,
        'pending' => status == 'untested' && !isExcluded,
        'failed' => status == 'failed',
        'approved' => status == 'approved',
        _ => false,
      };
    }

    final matching = candidates.where(matches).toList()
      ..sort((a, b) {
        // Group by notes first (clusters same exclusion reasons), then by id.
        final notesCmp = (a['notes'] as String? ?? '')
            .compareTo(b['notes'] as String? ?? '');
        if (notesCmp != 0) return notesCmp;
        return (a['id'] as String).compareTo(b['id'] as String);
      });

    if (matching.isEmpty) {
      if (!namesOnly) print('No $state entries.');
      return;
    }

    if (namesOnly) {
      for (final e in matching) {
        final id = e['id'] as String;
        if (withNotes) {
          final notes = e['notes'] as String? ?? '';
          print(notes.isNotEmpty ? '$id ($notes)' : id);
        } else {
          print(id);
        }
      }
      return;
    }

    for (final e in matching) {
      final id = e['id'] as String;
      final type = e['type'] as String? ?? '';
      final notes = e['notes'] as String? ?? '';
      final langs =
          (e['languages'] as List<dynamic>? ?? []).cast<String>().join(',');
      final langStr = langs.isNotEmpty ? ' [$langs]' : '';
      final noteStr = notes.isNotEmpty ? '  $notes' : '';
      print('  [$type] $id$langStr$noteStr');
    }
  }

  void _printTable(
    String selLabel,
    _Counts selAsr,
    _Counts selTts,
    _Counts allAsr,
    _Counts allTts, {
    bool showSelected = true,
  }) {
    const lw = 30; // label column width
    const cw = 6; // per-type count column width
    const groupW = cw * 2 + 1; // width per filter group (ASR + space + TTS)

    String center(String s, int width) {
      final spaces = max(0, width - s.length);
      return ' ' * (spaces ~/ 2) + s + ' ' * (spaces - spaces ~/ 2);
    }

    String row(
      String label,
      String v1,
      String v2,
      String v3,
      String v4, {
      int indent = 0,
    }) {
      final pad = ' ' * indent;
      final selCols =
          showSelected ? ' ${v1.padLeft(cw)} ${v2.padLeft(cw)}' : '';
      return '  ${(pad + label).padRight(lw)}'
          '$selCols'
          ' ${v3.padLeft(cw)} ${v4.padLeft(cw)}';
    }

    String numRow(
      String label,
      int n1,
      int n2,
      int n3,
      int n4, {
      bool naInSel = false,
      int indent = 0,
    }) =>
        row(
          label,
          naInSel ? '-' : n1.toString(),
          naInSel ? '-' : n2.toString(),
          n3.toString(),
          n4.toString(),
          indent: indent,
        );

    final divWidth =
        showSelected ? lw + groupW * 2 + 3 : lw + groupW + 1;
    final div = '  ${'─' * divWidth}';

    print('=== Catalog Status ===');
    print('');
    if (showSelected) {
      print('  ${' ' * lw} ${center(selLabel, groupW)} ${center('All', groupW)}');
    } else {
      print('  ${' ' * lw} ${center(selLabel, groupW)}');
    }
    print(row('', 'ASR', 'TTS', 'ASR', 'TTS'));
    print(div);
    print(numRow('Discovered',
        selAsr.discovered, selTts.discovered,
        allAsr.discovered, allTts.discovered));
    print(div);
    print(numRow('Ignored',
        selAsr.ignored, selTts.ignored,
        allAsr.ignored, allTts.ignored));

    const _ignoredCategories = [
      ('unsupported architecture', false),
      ('fp16 not supported', false),
      ('quality below medium', false),
      ('size > 1GB', false),
      ('int8 variant preferred', false),
    ];
    for (final (label, naInSel) in _ignoredCategories) {
      final allCount = (allAsr.ignoredReasons[label] ?? 0) +
          (allTts.ignoredReasons[label] ?? 0);
      if (allCount == 0) continue;
      print(numRow(
        label,
        selAsr.ignoredReasons[label] ?? 0,
        selTts.ignoredReasons[label] ?? 0,
        allAsr.ignoredReasons[label] ?? 0,
        allTts.ignoredReasons[label] ?? 0,
        naInSel: naInSel,
        indent: 2,
      ));
    }

    print(numRow('Pending (D-I)',
        selAsr.pending - selAsr.ignored, selTts.pending - selTts.ignored,
        allAsr.pending - allAsr.ignored, allTts.pending - allTts.ignored));
    print(div);
    print(numRow('Failed',
        selAsr.failed, selTts.failed,
        allAsr.failed, allTts.failed));
    print(div);
    print(numRow('Approved',
        selAsr.approved, selTts.approved,
        allAsr.approved, allTts.approved));
    print(numRow('Recommended',
        selAsr.recommended, selTts.recommended,
        allAsr.recommended, allTts.recommended));
    print(div);
    print('');
  }

  bool _matchesLanguage(Map<String, dynamic> entry) {
    if (languages.isEmpty) return true;
    final entryLangs =
        (entry['languages'] as List<dynamic>? ?? []).cast<String>().toSet();
    if (entryLangs.isEmpty) return false;
    return entryLangs.intersection(languages).isNotEmpty;
  }

  _Counts _count(List<Map<String, dynamic>> entries, {String? typeFilter}) {
    var discovered = 0;
    var ignored = 0;
    var pending = 0;
    var failed = 0;
    var approved = 0;
    var recommended = 0;
    final reasons = <String, int>{};

    for (final e in entries) {
      if (typeFilter != null && (e['type'] as String? ?? '') != typeFilter) {
        continue;
      }
      discovered++;
      final status = e['status'] as String? ?? '';
      final notes = e['notes'] as String? ?? '';
      // Only count as ignored when still untested — approved/failed entries with
      // skipped: notes were evaluated and should not inflate the ignored count.
      final isExcluded = status == 'untested' &&
          (notes.startsWith('excluded:') || notes.startsWith('skipped:'));

      if (isExcluded) {
        ignored++;
        final reason = _exclusionCategory(notes);
        reasons[reason] = (reasons[reason] ?? 0) + 1;
      }
      switch (status) {
        case 'untested':
          pending++;
        case 'failed':
          failed++;
        case 'approved':
          approved++;
          if (e['recommended'] == true) recommended++;
      }
    }

    return _Counts(
      discovered: discovered,
      ignored: ignored,
      ignoredReasons: reasons,
      pending: pending,
      failed: failed,
      approved: approved,
      recommended: recommended,
    );
  }

  String _exclusionCategory(String notes) {
    if (notes.contains('architecture')) return 'unsupported architecture';
    if (notes.contains('fp16')) return 'fp16 not supported';
    if (notes.contains('quality')) return 'quality below medium';
    if (notes.contains('size')) return 'size > 1GB';
    if (notes.contains('int8 variant')) return 'int8 variant preferred';
    return 'other';
  }
}

class _Counts {
  final int discovered;
  final int ignored;
  final Map<String, int> ignoredReasons;
  final int pending;
  final int failed;
  final int approved;
  final int recommended;

  _Counts({
    required this.discovered,
    required this.ignored,
    required this.ignoredReasons,
    required this.pending,
    required this.failed,
    required this.approved,
    required this.recommended,
  });
}
