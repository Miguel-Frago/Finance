import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'settings.dart';

/// Puzzle (pattern) lock helpers. The pattern is stored only as a salted hash.
/// NOTE: this is a convenience lock for an offline app. It keeps casual users
/// out but does not encrypt the database file (see README, "Security notes").
class Security {
  static bool get hasLock => Settings.get('lock_hash').isNotEmpty;

  static String _salt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static String _hash(String secret, String salt) =>
      sha256.convert(utf8.encode('$salt:$secret')).toString();

  static String _key(List<int> pattern) => pattern.join('-');

  static String newRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    String group() =>
        List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return '${group()}-${group()}-${group()}';
  }

  /// Saves a new pattern and returns a fresh one-time recovery code.
  static Future<String> savePattern(List<int> pattern) async {
    final salt = _salt();
    final code = newRecoveryCode();
    await Settings.set('lock_salt', salt);
    await Settings.set('lock_hash', _hash(_key(pattern), salt));
    await Settings.set('recovery_hash', _hash(code, salt));
    return code;
  }

  static bool verifyPattern(List<int> pattern) =>
      _hash(_key(pattern), Settings.get('lock_salt')) ==
      Settings.get('lock_hash');

  static bool verifyRecovery(String code) =>
      _hash(code.trim().toUpperCase(), Settings.get('lock_salt')) ==
      Settings.get('recovery_hash');
}
