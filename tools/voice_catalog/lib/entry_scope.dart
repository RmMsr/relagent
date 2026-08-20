/// Constrains which catalog entries a command operates on, via --type,
/// --lang, and --arch.
///
/// Applied uniformly across every command (--discover, --relabel, --filter,
/// --eval, --list, --list-architectures, --status) — an entry outside the
/// scope is left untouched/unlisted, never removed from the catalog. Callers
/// must always save the full, unfiltered entries list; only iterate the
/// scoped subset.
class EntryScope {
  /// Model type to match, or null for "all".
  final String? type;

  /// Language codes to match (entry must have at least one in common).
  /// Empty means "all" (no language constraint).
  final Set<String> languages;

  /// Architecture values to match. Empty means "all" (no constraint).
  final Set<String> architectures;

  const EntryScope({
    this.type,
    this.languages = const {},
    this.architectures = const {},
  });

  /// A copy of this scope with the language constraint cleared. Useful for
  /// views that show a language-narrowed subset alongside a type/arch-scoped
  /// "all languages" baseline (see VoiceCatalogStatusReporter.report).
  EntryScope withoutLanguage() =>
      EntryScope(type: type, architectures: architectures);

  /// One "label: value" line per dimension — type/lang/arch are all
  /// included, even at their unconstrained "all" value, so a default like
  /// --lang's "en" doesn't silently narrow results while type/arch look
  /// scoped too. One dimension per line (rather than packed onto one line)
  /// so a non-default value like "en" visually stands out against the
  /// "all" rows. Printed at the start of a run.
  List<String> describeLines() {
    final langDesc = languages.isEmpty
        ? 'all'
        : (languages.toList()..sort()).join(',');
    final archDesc = architectures.isEmpty
        ? 'all'
        : (architectures.toList()..sort()).join(',');
    return ['type: ${type ?? 'all'}', 'lang: $langDesc', 'arch: $archDesc'];
  }

  bool matches(Map<String, dynamic> entry) {
    if (type != null && (entry['type'] as String? ?? '') != type) {
      return false;
    }
    if (architectures.isNotEmpty &&
        !architectures.contains(entry['architecture'] as String? ?? '')) {
      return false;
    }
    if (languages.isNotEmpty) {
      final entryLangs = (entry['languages'] as List<dynamic>? ?? [])
          .cast<String>()
          .toSet();
      // 'multi' is a wildcard sentinel for models with too many supported
      // languages to enumerate (e.g. Omnilingual ASR's 1600) — treat it as
      // matching any requested language.
      final isMulti = entryLangs.contains('multi');
      if (!isMulti &&
          (entryLangs.isEmpty || entryLangs.intersection(languages).isEmpty)) {
        return false;
      }
    }
    return true;
  }
}
