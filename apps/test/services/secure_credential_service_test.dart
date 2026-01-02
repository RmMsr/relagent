import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:relagent/services/secure_credential_service.dart';

class MockFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _storage = {};
  bool _shouldFail = false;

  void setShouldFail(bool shouldFail) {
    _shouldFail = shouldFail;
  }

  @override
  void registerListener({
    required String key,
    required void Function(String?) listener,
  }) {
    // Not needed for tests
  }

  @override
  void unregisterListener({
    required String key,
    required void Function(String?) listener,
  }) {
    // Not needed for tests
  }

  @override
  void unregisterAllListenersForKey({required String key}) {
    // Not needed for tests
  }

  @override
  void unregisterAllListeners() {
    // Not needed for tests
  }

  @override
  Future<bool?> isCupertinoProtectedDataAvailable() async {
    return null;
  }

  @override
  Stream<bool>? get onCupertinoProtectedDataAvailabilityChanged => null;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_shouldFail) {
      throw Exception('Secure storage not available');
    }
    if (value != null) {
      _storage[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_shouldFail) {
      throw Exception('Secure storage not available');
    }
    return _storage[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_shouldFail) {
      throw Exception('Secure storage not available');
    }
    _storage.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_shouldFail) {
      throw Exception('Secure storage not available');
    }
    return Map.from(_storage);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_shouldFail) {
      throw Exception('Secure storage not available');
    }
    _storage.clear();
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_shouldFail) {
      throw Exception('Secure storage not available');
    }
    return _storage.containsKey(key);
  }

  @override
  IOSOptions get iOptions => throw UnimplementedError();

  @override
  AndroidOptions get aOptions => throw UnimplementedError();

  @override
  LinuxOptions get lOptions => throw UnimplementedError();

  @override
  WebOptions get webOptions => throw UnimplementedError();

  @override
  MacOsOptions get mOptions => throw UnimplementedError();

  @override
  WindowsOptions get wOptions => throw UnimplementedError();
}

void main() {
  group('SecureCredentialService', () {
    late MockFlutterSecureStorage mockStorage;
    late SecureCredentialService service;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      service = SecureCredentialService(secureStorage: mockStorage);
    });

    group('isSecureStorageAvailable', () {
      test('returns true when secure storage works', () async {
        final result = await service.isSecureStorageAvailable();
        expect(result, true);
      });

      test('returns false when secure storage fails', () async {
        mockStorage.setShouldFail(true);
        final result = await service.isSecureStorageAvailable();
        expect(result, false);
      });

      test('caches result after first check', () async {
        final result1 = await service.isSecureStorageAvailable();
        mockStorage.setShouldFail(true);
        final result2 = await service.isSecureStorageAvailable();
        expect(result1, result2);
      });
    });

    group('password storage', () {
      const testUrl = 'http://example.com/api';
      const testPassword = 'test_password_123';

      test('stores and retrieves password with secure storage', () async {
        await service.storePassword(testUrl, testPassword);
        final retrieved = await service.getPassword(testUrl);
        expect(retrieved, testPassword);
      });

      test('returns null for non-existent password', () async {
        final retrieved = await service.getPassword('http://nonexistent.com');
        expect(retrieved, null);
      });

      test('uses memory storage when secure storage unavailable', () async {
        mockStorage.setShouldFail(true);
        await service.isSecureStorageAvailable(); // Cache the failure

        await service.storePassword(testUrl, testPassword);
        final retrieved = await service.getPassword(testUrl);
        expect(retrieved, testPassword);
      });

      test('scopes passwords by URL', () async {
        const url1 = 'http://example1.com';
        const url2 = 'http://example2.com';
        const password1 = 'password1';
        const password2 = 'password2';

        await service.storePassword(url1, password1);
        await service.storePassword(url2, password2);

        expect(await service.getPassword(url1), password1);
        expect(await service.getPassword(url2), password2);
      });
    });

    group('clearCredentials', () {
      const testUrl = 'http://example.com/api';

      test('clears password', () async {
        await service.storePassword(testUrl, 'password');

        await service.clearCredentials(testUrl);

        expect(await service.getPassword(testUrl), null);
      });

      test('does not affect credentials for other URLs', () async {
        const url1 = 'http://example1.com';
        const url2 = 'http://example2.com';

        await service.storePassword(url1, 'password1');
        await service.storePassword(url2, 'password2');

        await service.clearCredentials(url1);

        expect(await service.getPassword(url1), null);
        expect(await service.getPassword(url2), 'password2');
      });

      test('works with memory storage fallback', () async {
        mockStorage.setShouldFail(true);
        await service.isSecureStorageAvailable(); // Cache the failure

        await service.storePassword(testUrl, 'password');

        await service.clearCredentials(testUrl);

        expect(await service.getPassword(testUrl), null);
      });
    });

    group('credential caching', () {
      const testUrl = 'http://example.com/api';
      const testPassword = 'cached_password_123';

      test('first read populates cache from storage', () async {
        await service.storePassword(testUrl, testPassword);

        // First read should hit storage and populate cache
        final retrieved1 = await service.getPassword(testUrl);
        expect(retrieved1, testPassword);

        // Verify it was stored in underlying storage
        final storageKey = 'auth_password_$testUrl';
        final fromStorage = await mockStorage.read(key: storageKey);
        expect(fromStorage, testPassword);
      });

      test('second read uses cache without hitting storage', () async {
        await service.storePassword(testUrl, testPassword);

        // First read populates cache
        await service.getPassword(testUrl);

        // Make storage unavailable to prove cache is used
        mockStorage.setShouldFail(true);

        // Second read should use cache, not fail
        final retrieved2 = await service.getPassword(testUrl);
        expect(retrieved2, testPassword);
      });

      test('storing password updates cache immediately', () async {
        const newPassword = 'updated_password';

        // Store initial password
        await service.storePassword(testUrl, testPassword);
        await service.getPassword(testUrl); // Populate cache

        // Update password
        await service.storePassword(testUrl, newPassword);

        // Make storage unavailable to prove cache was updated
        mockStorage.setShouldFail(true);

        // Should return updated password from cache
        final retrieved = await service.getPassword(testUrl);
        expect(retrieved, newPassword);
      });

      test('clearCredentials invalidates cache', () async {
        await service.storePassword(testUrl, testPassword);
        await service.getPassword(testUrl); // Populate cache

        // Clear credentials
        await service.clearCredentials(testUrl);

        // Should return null (cache invalidated)
        final retrieved = await service.getPassword(testUrl);
        expect(retrieved, null);
      });

      test('cache is scoped by URL', () async {
        const url1 = 'http://example1.com';
        const url2 = 'http://example2.com';
        const password1 = 'password1';
        const password2 = 'password2';

        await service.storePassword(url1, password1);
        await service.storePassword(url2, password2);

        // Populate cache for both URLs
        await service.getPassword(url1);
        await service.getPassword(url2);

        // Make storage unavailable
        mockStorage.setShouldFail(true);

        // Both should be retrievable from cache
        expect(await service.getPassword(url1), password1);
        expect(await service.getPassword(url2), password2);
      });

      test('cache handles null values correctly', () async {
        // Try to get non-existent password
        final retrieved1 = await service.getPassword(testUrl);
        expect(retrieved1, null);

        // Store a password
        await service.storePassword(testUrl, testPassword);

        // Should return the stored password
        final retrieved2 = await service.getPassword(testUrl);
        expect(retrieved2, testPassword);
      });
    });
  });
}
