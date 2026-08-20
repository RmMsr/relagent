import 'dart:convert';

import 'package:freedesktop_secret/freedesktop_secret.dart';

/// Storage for the CLI's engine auth token. The default implementation uses
/// the Linux Secret Service (GNOME Keyring / KWallet); its absence or the
/// unavailability of that secure storage is surfaced as "no token" (`null`
/// from [readToken], `false` from [writeToken]) rather than as a fatal
/// error — see the `Secure storage unavailable` scenario in the cli-config
/// spec.
abstract class TokenStore {
  Future<String?> readToken();

  /// Returns whether the token was stored successfully.
  Future<bool> writeToken(String token);

  /// Removes the stored token, if any. Returns whether the operation
  /// completed without error (true even when there was nothing to delete).
  Future<bool> deleteToken();
}

class SecretServiceTokenStore implements TokenStore {
  static const _attributes = {
    'service': 'org.venkado.relagent-cli',
    'kind': 'engine-token',
  };
  static const _label = 'Relagent CLI engine token';

  @override
  Future<String?> readToken() async {
    final secret = FreeDesktopSecret();
    try {
      await secret.initialize();
      final item = await secret.lookupSecret(attributes: _attributes);
      if (item == null) return null;
      return utf8.decode(item.secretBytes);
    } catch (_) {
      return null;
    } finally {
      try {
        await secret.close();
      } catch (_) {}
    }
  }

  @override
  Future<bool> writeToken(String token) async {
    final secret = FreeDesktopSecret();
    try {
      await secret.initialize();
      await secret.storeSecretText(
        attributes: _attributes,
        secret: token,
        label: _label,
        replace: true,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await secret.close();
      } catch (_) {}
    }
  }

  @override
  Future<bool> deleteToken() async {
    final secret = FreeDesktopSecret();
    try {
      await secret.initialize();
      await secret.deleteSecret(attributes: _attributes);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await secret.close();
      } catch (_) {}
    }
  }
}
