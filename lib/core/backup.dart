import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'audit.dart';
import 'crypto.dart';
import 'db.dart';
import 'settings.dart';

class BackupResult {
  final bool ok;
  final String message;
  const BackupResult(this.ok, this.message);
}

class Backup {
  static const _sqliteHeader = 'SQLite format 3';

  /// Saves a copy of the whole database (data + settings + audit trail).
  /// With a [password] the file is encrypted, without one it is a plain copy.
  static Future<BackupResult> create({String? password}) async {
    await AppDb.checkpoint();
    var bytes = await File(AppDb.path).readAsBytes();
    final protect = password != null && password.isNotEmpty;
    if (protect) bytes = await BackupCrypto.encrypt(bytes, password);
    final name =
        'BFM_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.bfm';
    final out = await FilePicker.platform.saveFile(
      dialogTitle: 'Save backup',
      fileName: name,
      bytes: Platform.isAndroid ? bytes : null,
    );
    if (out == null) return const BackupResult(false, 'Backup cancelled.');
    if (!Platform.isAndroid) await File(out).writeAsBytes(bytes);
    await Settings.set('last_backup_at', DateTime.now().toIso8601String(), audit: false);
    await Audit.log('BACKUP_CREATED',
        entity: 'backup', newValue: '$out (${protect ? 'password protected' : 'no password'})');
    return BackupResult(
        true, protect ? 'Encrypted backup saved.' : 'Backup saved (no password).');
  }

  /// Replaces the current database with a backup file. A safety copy of the
  /// current data is kept and restored automatically if anything goes wrong.
  /// [askPassword] is called when the file is password protected.
  static Future<BackupResult> restore({Future<String?> Function()? askPassword}) async {
    final pick = await FilePicker.platform
        .pickFiles(dialogTitle: 'Choose a backup file', withData: false);
    var src = pick?.files.single.path;
    if (src == null) return const BackupResult(false, 'Restore cancelled.');

    String? tmp;
    final head = await File(src).openRead(0, 16).first;
    if (BackupCrypto.isEncrypted(head)) {
      final pw = askPassword == null ? null : await askPassword();
      if (pw == null || pw.isEmpty) {
        return const BackupResult(false, 'Restore cancelled. This backup needs its password.');
      }
      try {
        final Uint8List clear =
            await BackupCrypto.decrypt(await File(src).readAsBytes(), pw);
        tmp = '${AppDb.supportDir}${Platform.pathSeparator}restore_tmp.bfm';
        await File(tmp).writeAsBytes(clear);
        src = tmp;
      } on BackupPasswordError catch (e) {
        return BackupResult(false, '$e');
      }
    }

    try {
      final head2 = await File(src).openRead(0, 16).first;
      if (!String.fromCharCodes(head2).startsWith(_sqliteHeader)) {
        return const BackupResult(false, 'That is not a valid backup file.');
      }

      await AppDb.checkpoint();
      await AppDb.close();
      final safety = File('${AppDb.path}.before_restore');
      await File(AppDb.path).copy(safety.path);
      try {
        for (final ext in ['-wal', '-shm']) {
          final f = File('${AppDb.path}$ext');
          if (await f.exists()) await f.delete();
        }
        await File(src).copy(AppDb.path);
        await AppDb.reopen();
        await Settings.load(); // throws if the file lacks the settings table
        await Audit.log('BACKUP_RESTORED', entity: 'backup', newValue: pick!.files.single.path);
        return const BackupResult(true, 'Data restored from backup.');
      } catch (e) {
        await AppDb.close();
        await safety.copy(AppDb.path);
        await AppDb.reopen();
        await Settings.load();
        return BackupResult(false, 'Restore failed, your data is unchanged. ($e)');
      }
    } finally {
      if (tmp != null) {
        try {
          await File(tmp).delete();
        } catch (_) {}
      }
    }
  }
}
