import '/models/settings.dart';

const _maxHistoryEntries = 5;

class SettingsHistoryManager {
  List<SettingsHistoryEntry> addToHistory(
    List<SettingsHistoryEntry> currentHistory,
    String url,
    String model,
  ) {
    final newEntry = SettingsHistoryEntry(url: url, model: model);

    final newHistory = List<SettingsHistoryEntry>.from(currentHistory);
    newHistory.removeWhere((entry) => entry == newEntry);
    newHistory.insert(0, newEntry);

    if (newHistory.length > _maxHistoryEntries) {
      return newHistory.sublist(0, _maxHistoryEntries);
    }
    return newHistory;
  }
}
