import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bfm_app/core/crypto.dart';

void main() {
  final data = Uint8List.fromList(List<int>.generate(1000, (i) => i % 251));

  test('encrypt then decrypt returns the same bytes', () async {
    final enc = await BackupCrypto.encrypt(data, 'secret-pass', iterations: 1000);
    expect(BackupCrypto.isEncrypted(enc), isTrue);
    expect(enc.length, greaterThan(data.length));
    final dec = await BackupCrypto.decrypt(enc, 'secret-pass');
    expect(dec, data);
  });

  test('wrong password is refused', () async {
    final enc = await BackupCrypto.encrypt(data, 'secret-pass', iterations: 1000);
    await expectLater(BackupCrypto.decrypt(enc, 'other-pass'), throwsA(isA<BackupPasswordError>()));
  });

  test('a plain file is not treated as encrypted', () {
    expect(BackupCrypto.isEncrypted('SQLite format 3\u0000'.codeUnits), isFalse);
  });
}
