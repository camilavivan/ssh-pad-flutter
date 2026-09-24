import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure vault for passwords / private keys / passphrases (keyed by host id).
class SecretStore {
  SecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _passwordKey(String hostId) => 'secret_pwd_$hostId';
  static String _privateKeyKey(String hostId) => 'secret_key_$hostId';
  static String _passphraseKey(String hostId) => 'secret_pp_$hostId';

  Future<void> writeSecrets({
    required String hostId,
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    if (password != null && password.isNotEmpty) {
      await _storage.write(key: _passwordKey(hostId), value: password);
    } else {
      await _storage.delete(key: _passwordKey(hostId));
    }
    if (privateKey != null && privateKey.isNotEmpty) {
      await _storage.write(key: _privateKeyKey(hostId), value: privateKey);
    } else {
      await _storage.delete(key: _privateKeyKey(hostId));
    }
    if (passphrase != null && passphrase.isNotEmpty) {
      await _storage.write(key: _passphraseKey(hostId), value: passphrase);
    } else {
      await _storage.delete(key: _passphraseKey(hostId));
    }
  }

  Future<({String? password, String? privateKey, String? passphrase})>
      readSecrets(String hostId) async {
    try {
      final password = await _storage.read(key: _passwordKey(hostId));
      final privateKey = await _storage.read(key: _privateKeyKey(hostId));
      final passphrase = await _storage.read(key: _passphraseKey(hostId));
      return (
        password: password,
        privateKey: privateKey,
        passphrase: passphrase,
      );
    } catch (e, st) {
      debugPrint('SecretStore.read failed: $e\n$st');
      return (password: null, privateKey: null, passphrase: null);
    }
  }

  Future<void> deleteAllForHost(String hostId) async {
    await _storage.delete(key: _passwordKey(hostId));
    await _storage.delete(key: _privateKeyKey(hostId));
    await _storage.delete(key: _passphraseKey(hostId));
  }
}
