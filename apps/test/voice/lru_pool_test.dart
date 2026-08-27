import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/voice/lru_pool.dart';

void main() {
  group('LruPool', () {
    test('get on an empty pool is a miss', () {
      final pool = LruPool<String, int>(maxSize: 3, onEvict: (_) {});
      expect(pool.get('a'), isNull);
    });

    test('get after put is a hit and does not evict', () {
      final evicted = <int>[];
      final pool = LruPool<String, int>(maxSize: 3, onEvict: evicted.add);

      pool.put('a', 1);
      expect(pool.get('a'), 1);
      expect(evicted, isEmpty);
    });

    test('inserting beyond capacity evicts the least-recently-used entry', () {
      final evicted = <int>[];
      final pool = LruPool<String, int>(maxSize: 2, onEvict: evicted.add);

      pool.put('a', 1);
      pool.put('b', 2);
      pool.put('c', 3); // pool full at 2 — evicts 'a' (never touched again)

      expect(evicted, [1]);
      expect(pool.get('a'), isNull);
      expect(pool.get('b'), 2);
      expect(pool.get('c'), 3);
    });

    test('reading an entry protects it from eviction (moves it to MRU)', () {
      final evicted = <int>[];
      final pool = LruPool<String, int>(maxSize: 2, onEvict: evicted.add);

      pool.put('a', 1);
      pool.put('b', 2);
      pool.get('a'); // touch 'a' — now 'b' is the least-recently-used
      pool.put('c', 3);

      expect(evicted, [2]);
      expect(pool.get('a'), 1);
      expect(pool.get('b'), isNull);
      expect(pool.get('c'), 3);
    });

    test('clear evicts every entry and empties the pool', () {
      final evicted = <int>[];
      final pool = LruPool<String, int>(maxSize: 3, onEvict: evicted.add);

      pool.put('a', 1);
      pool.put('b', 2);
      pool.clear();

      expect(evicted, unorderedEquals([1, 2]));
      expect(pool.length, 0);
      expect(pool.get('a'), isNull);
    });
  });
}
