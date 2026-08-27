/// A small fixed-capacity pool keyed by [K], evicting the least-recently-used
/// entry via [onEvict] when an insert would exceed [maxSize]. Reading an
/// existing key moves it to most-recently-used.
class LruPool<K, V> {
  final int maxSize;
  final void Function(V value) onEvict;
  final _entries = <K, V>{};

  LruPool({required this.maxSize, required this.onEvict});

  /// Returns the existing entry for [key] (moved to most-recently-used), or
  /// null on a miss.
  V? get(K key) {
    final existing = _entries.remove(key);
    if (existing == null) return null;
    _entries[key] = existing;
    return existing;
  }

  /// Inserts [value] for [key], evicting the least-recently-used entry first
  /// if the pool is already at [maxSize]. Assumes [key] is not already
  /// present — call [get] first to check.
  void put(K key, V value) {
    if (_entries.length >= maxSize) {
      final lruKey = _entries.keys.first;
      final evicted = _entries.remove(lruKey);
      if (evicted != null) onEvict(evicted);
    }
    _entries[key] = value;
  }

  /// Evicts every entry and empties the pool.
  void clear() {
    for (final value in _entries.values) {
      onEvict(value);
    }
    _entries.clear();
  }

  int get length => _entries.length;
  Iterable<K> get keys => _entries.keys;
}
