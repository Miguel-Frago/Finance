import 'package:intl/intl.dart';
import 'audit.dart';
import 'db.dart';
import 'employees_repo.dart';

/// Effective-dated rate and position history. Old entries are never
/// overwritten, so past payrolls can always use the rate that applied then.
class RatesRepo {
  static const reasons = ['Promotion', 'Performance adjustment', 'Correction', 'Other'];

  static String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  static Future<List<DbRow>> list(int empId) => AppDb.db.query(
        'employee_rates',
        where: 'employee_id = ?',
        whereArgs: [empId],
        orderBy: 'effective_date DESC, id DESC',
      );

  /// The entry in effect on [date] (yyyy-MM-dd). Payroll uses this per day.
  static Future<DbRow?> effectiveOn(int empId, String date) async {
    final r = await AppDb.db.query(
      'employee_rates',
      where: 'employee_id = ? AND effective_date <= ?',
      whereArgs: [empId, date],
      orderBy: 'effective_date DESC, id DESC',
      limit: 1,
    );
    return r.isEmpty ? null : r.first;
  }

  static Future<void> addInitial(int empId, DbRow emp) async {
    await AppDb.db.insert('employee_rates', {
      'employee_id': empId,
      'effective_date': emp['date_hired'],
      'position': emp['position'],
      'department': emp['department'],
      'pay_type': emp['pay_type'],
      'rate_centavos': emp['rate_centavos'],
      'reason': 'Hired',
      'note': '',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static String _desc(DbRow? r) => r == null
      ? '-'
      : '${r['position']} / ${r['department']} / ${r['pay_type']} ${EmployeesRepo.pesos(r['rate_centavos'] as int)}';

  /// Returns an error message, or null when saved.
  static Future<String?> add({
    required int empId,
    required String date,
    required String position,
    required String department,
    required String payType,
    required int rateCentavos,
    required String reason,
    String note = '',
  }) async {
    final emp = await EmployeesRepo.byId(empId);
    if (emp == null) return 'Employee not found.';
    if (date.compareTo(emp['date_hired'] as String) < 0) {
      return 'The effective date cannot be before the date hired.';
    }
    final same = await AppDb.db.query('employee_rates',
        where: 'employee_id = ? AND effective_date = ?',
        whereArgs: [empId, date],
        limit: 1);
    if (same.isNotEmpty) {
      return 'There is already an entry for that date. Pick another date, or delete that entry first.';
    }
    final before = await effectiveOn(empId, date);
    if (before != null &&
        before['position'] == position &&
        before['department'] == department &&
        before['pay_type'] == payType &&
        before['rate_centavos'] == rateCentavos) {
      return 'Nothing changed compared with what is in effect on that date.';
    }
    await AppDb.db.insert('employee_rates', {
      'employee_id': empId,
      'effective_date': date,
      'position': position,
      'department': department,
      'pay_type': payType,
      'rate_centavos': rateCentavos,
      'reason': reason,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
    await syncCurrent(empId);
    await Audit.log('RATE_CHANGED',
        entity: 'employee',
        entityId: emp['emp_code'] as String,
        oldValue: _desc(before),
        newValue:
            'from $date ($reason): $position / $department / $payType ${EmployeesRepo.pesos(rateCentavos)}');
    return null;
  }

  static Future<void> delete(int id) async {
    final r = await AppDb.db.query('employee_rates', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty || r.first['reason'] == 'Hired') return;
    final emp = await EmployeesRepo.byId(r.first['employee_id'] as int);
    await AppDb.db.delete('employee_rates', where: 'id = ?', whereArgs: [id]);
    await syncCurrent(r.first['employee_id'] as int);
    await Audit.log('RATE_ENTRY_DELETED',
        entity: 'employee',
        entityId: (emp?['emp_code'] as String?) ?? '',
        oldValue: 'from ${r.first['effective_date']}: ${_desc(r.first)}');
  }

  /// Copies the entry in effect today into the employee's "current" fields.
  static Future<void> syncCurrent(int empId) async {
    final e = await effectiveOn(empId, _today());
    if (e == null) return;
    await AppDb.db.update(
        'employees',
        {
          'position': e['position'],
          'department': e['department'],
          'pay_type': e['pay_type'],
          'rate_centavos': e['rate_centavos'],
        },
        where: 'id = ?',
        whereArgs: [empId]);
  }

  /// Run at startup so scheduled (future-dated) changes take over on their day.
  static Future<void> syncAll() async {
    final ids = await AppDb.db.query('employees', columns: ['id']);
    for (final r in ids) {
      await syncCurrent(r['id'] as int);
    }
  }
}
