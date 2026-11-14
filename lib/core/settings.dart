import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'audit.dart';
import 'db.dart';

/// Key/value app settings, cached in memory. Every change is audited.
class Settings {
  static final Map<String, String> _c = {};
  static const _hidden = {'lock_hash', 'lock_salt', 'recovery_hash'};

  static Future<void> load() async {
    _c.clear();
    for (final r in await AppDb.db.query('settings')) {
      _c[r['key'] as String] = r['value'] as String;
    }
  }

  static String get(String key, [String def = '']) => _c[key] ?? def;
  static int getInt(String key, int def) => int.tryParse(_c[key] ?? '') ?? def;

  static Future<void> set(String key, String value, {bool audit = true}) async {
    final old = _c[key];
    if (old == value) return;
    await AppDb.db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _c[key] = value;
    if (audit) {
      final h = _hidden.contains(key);
      await Audit.log('SETTING_CHANGED',
          entity: 'settings',
          entityId: key,
          oldValue: h ? '(hidden)' : old,
          newValue: h ? '(hidden)' : value);
    }
  }
}
