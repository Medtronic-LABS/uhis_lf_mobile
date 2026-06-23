import 'package:flutter_test/flutter_test.dart';

// KeyStore key-format validation. We test the _generateKey logic indirectly
// by checking the expected hex format, since the actual storage layer uses
// platform channels (EncryptedSharedPreferences) which are unavailable in
// unit tests. Integration/device tests cover the full read-back cycle.
void main() {
  group('KeyStore key format', () {
    // Mirrors the _generateKey() logic from key_store.dart:
    // 32 random bytes → hex string, each byte zero-padded to 2 chars.
    String generateHexKey(List<int> bytes) {
      assert(bytes.length == 32);
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }

    test('generated key is 64 characters long (256 bits as hex)', () {
      final allZeroes = List<int>.filled(32, 0);
      final key = generateHexKey(allZeroes);
      expect(key.length, equals(64));
    });

    test('generated key contains only lowercase hex characters', () {
      final allZeroes = List<int>.filled(32, 0);
      final key = generateHexKey(allZeroes);
      expect(key, matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('byte values are correctly encoded', () {
      // Known bytes → known hex
      final knownBytes = [0, 1, 15, 16, 127, 128, 255] + List.filled(25, 0);
      final key = generateHexKey(knownBytes);
      expect(key.startsWith('00010f107f80ff'), isTrue);
    });

    test('zero bytes produce all-zero hex string', () {
      final key = generateHexKey(List.filled(32, 0));
      expect(key, equals('0' * 64));
    });

    test('max bytes produce all-f hex string', () {
      final key = generateHexKey(List.filled(32, 255));
      expect(key, equals('f' * 64));
    });

    test('different byte arrays produce different keys', () {
      final key1 = generateHexKey(List.generate(32, (i) => i));
      final key2 = generateHexKey(List.generate(32, (i) => 255 - i));
      expect(key1, isNot(equals(key2)));
    });
  });
}
