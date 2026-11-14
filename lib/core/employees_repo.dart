import 'audit.dart';
import 'db.dart';
import 'rates_repo.dart';

typedef DbRow = Map<String, Object?>;

class EmployeesRepo {
  static const payTypes = ['Daily', 'Weekly', 'Monthly', 'Annual'];
  static const payUnit = {
    'Daily': 'day',
    'Weekly': 'week',
    'Monthly': 'month',
    'Annual': 'year',
  };

  static String code(int id) => 'EMP-${id.toString().padLeft(4, '0')}';
  static String fullName(DbRow r) => '${r['last_name']}, ${r['first_name']}';

  static String pesos(int centavos) {
    final s = (centavos / 100).toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return '\u20b1$whole.${parts[1]}';
  }

  static Future<List<DbRow>> list({String q = '', String status = 'All'}) {
    final where = <String>[];
    final args = <Object?>[];
    if (status != 'All') {
      where.add('status = ?');
      args.add(status);
    }
    if (q.trim().isNotEmpty) {
      where.add(
          '(first_name LIKE ? OR last_name LIKE ? OR emp_code LIKE ? OR department LIKE ? OR position LIKE ?)');
      final l = '%${q.trim()}%';
      args.addAll([l, l, l, l, l]);
    }
    return AppDb.db.query(
      'employees',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE',
    );
  }

  static Future<DbRow?> byId(int id) async {
    final r = await AppDb.db.query('employees', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  /// Returns the employee code of another employee with the same name, if any.
  static Future<String?> duplicateName(String first, String last,
      {int? exceptId}) async {
    final r = await AppDb.db.query(
      'employees',
      columns: ['emp_code'],
      where: 'lower(first_name) = ? AND lower(last_name) = ? AND id != ?',
      whereArgs: [first.trim().toLowerCase(), last.trim().toLowerCase(), exceptId ?? -1],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['emp_code'] as String;
  }

  static Future<List<String>> distinct(String column) async {
    assert(column == 'position' || column == 'department');
    final r = await AppDb.db.rawQuery(
        "SELECT DISTINCT $column AS v FROM employees WHERE $column != '' ORDER BY $column COLLATE NOCASE");
    return r.map((e) => e['v'] as String).toList();
  }

  static Future<int> create(DbRow v) async {
    final id = await AppDb.db.transaction((txn) async {
      final id = await txn.insert('employees', {
        ...v,
        'emp_code': 'PENDING',
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.update('employees', {'emp_code': code(id)},
          where: 'id = ?', whereArgs: [id]);
      return id;
    });
    final created = await byId(id);
    if (created != null) await RatesRepo.addInitial(id, created);
    await Audit.log('EMPLOYEE_CREATED',
        entity: 'employee',
        entityId: code(id),
        newValue: '${v['last_name']}, ${v['first_name']}');
    return id;
  }

  static String _show(String key, Object? val) {
    if (key == 'rate_centavos') return pesos((val as int?) ?? 0);
    return val?.toString() ?? '';
  }

  static Future<void> update(int id, DbRow v) async {
    final old = await byId(id);
    if (old == null) return;
    final oldParts = <String>[];
    final newParts = <String>[];
    for (final k in v.keys) {
      if ((old[k]?.toString() ?? '') != (v[k]?.toString() ?? '')) {
        oldParts.add('$k=${_show(k, old[k])}');
        newParts.add('$k=${_show(k, v[k])}');
      }
    }
    if (newParts.isEmpty) return;
    await AppDb.db.update('employees', v, where: 'id = ?', whereArgs: [id]);
    if (v.containsKey('date_hired')) {
      // keep the starting history entry on the hire date
      await AppDb.db.update('employee_rates', {'effective_date': v['date_hired']},
          where: "employee_id = ? AND reason = 'Hired'", whereArgs: [id]);
    }
    await Audit.log('EMPLOYEE_UPDATED',
        entity: 'employee',
        entityId: old['emp_code'] as String,
        oldValue: oldParts.join('; '),
        newValue: newParts.join('; '));
  }
}
