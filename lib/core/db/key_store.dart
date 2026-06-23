import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the SQLCipher database encryption key.
///
/// The key is a 256-bit random hex string, generated once and stored in
/// Android EncryptedSharedPreferences (backed by the Android Keystore).
/// Subsequent opens read the same key — the DB is never re-encrypted.
class KeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyAlias = 'uhis_lf.db_key';

  static Future<String> getKey() async {
    String? key = await _storage.read(key: _keyAlias);
    if (key == null) {
      key = _generateKey();
      await _storage.write(key: _keyAlias, value: key);
    }
    return key;
  }

  static String _generateKey() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
