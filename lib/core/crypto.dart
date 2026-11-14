import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class BackupPasswordError implements Exception {
  @override
  String toString() => 'Wrong password, or the backup file is damaged.';
}

/// Password protection for backup files (AES-256-GCM, key from the password
/// with PBKDF2-HMAC-SHA256). File layout:
///   "BFMENC1\n" (8 bytes) | salt (16) | iterations (4, big endian) |
///   nonce (12) | encrypted data | tag (16)
/// There is no password reset: without the password the backup cannot be opened.
class BackupCrypto {
  static const _magic = [0x42, 0x46, 0x4D, 0x45, 0x4E, 0x43, 0x31, 0x0A];
  static const defaultIterations = 150000;

  static bool isEncrypted(List<int> head) {
    if (head.length < _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (head[i] != _magic[i]) return false;
    }
    return true;
  }

  static Future<SecretKey> _key(String password, List<int> salt, int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);

  static Future<Uint8List> encrypt(Uint8List data, String password,
      {int iterations = defaultIterations}) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final key = await _key(password, salt, iterations);
    final box = await AesGcm.with256bits().encrypt(data, secretKey: key);
    final out = BytesBuilder()
      ..add(_magic)
      ..add(salt)
      ..add([
        (iterations >> 24) & 0xFF,
        (iterations >> 16) & 0xFF,
        (iterations >> 8) & 0xFF,
        iterations & 0xFF,
      ])
      ..add(box.concatenation());
    return out.toBytes();
  }

  static Future<Uint8List> decrypt(Uint8List file, String password) async {
    if (!isEncrypted(file) || file.length < 8 + 16 + 4 + 12 + 16) {
      throw BackupPasswordError();
    }
    final salt = file.sublist(8, 24);
    final iterations = (file[24] << 24) | (file[25] << 16) | (file[26] << 8) | file[27];
    if (iterations < 1000 || iterations > 5000000) throw BackupPasswordError();
    try {
      final key = await _key(password, salt, iterations);
      final box = SecretBox.fromConcatenation(file.sublist(28), nonceLength: 12, macLength: 16);
      final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
      return Uint8List.fromList(clear);
    } catch (_) {
      throw BackupPasswordError();
    }
  }
}
