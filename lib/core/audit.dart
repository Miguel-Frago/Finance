import 'dart:io';
import 'db.dart';

class Audit {
  static Future<void> log(
    String action, {
    String entity = '',
    String entityId = '',
    String? oldValue,
    String? newValue,
  }) async {
    await AppDb.db.insert('audit_log', {
      'at': DateTime.now().toIso8601String(),
      'device': Platform.localHostname,
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'old_value': oldValue,
      'new_value': newValue,
    });
  }

  static Future<List<Map<String, Object?>>> recent(
      {String q = '', int limit = 300}) {
    if (q.trim().isEmpty) {
      return AppDb.db.query('audit_log', orderBy: 'id DESC', limit: limit);
    }
    final like = '%${q.trim()}%';
    return AppDb.db.query(
      'audit_log',
      where:
          'action LIKE ? OR entity LIKE ? OR entity_id LIKE ? OR new_value LIKE ?',
      whereArgs: [like, like, like, like],
      orderBy: 'id DESC',
      limit: limit,
    );
  }
}
