import 'package:intl/intl.dart';
import 'audit.dart';
import 'db.dart';
import 'employees_repo.dart';
import 'settings.dart';

String _k(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Company holiday calendar. Add the holidays for each year yourself
/// (some dates move every year).
class HolidaysRepo {
  static const types = ['Regular', 'Special'];

  static Future<List<DbRow>> forYear(int year) => AppDb.db.query('holidays',
      where: 'hdate >= ? AND hdate <= ?',
      whereArgs: ['$year-01-01', '$year-12-31'],
      orderBy: 'hdate');

  /// Returns an error message, or null when saved.
  static Future<String?> add(DateTime date, String name, String type) async {
    final k = _k(date);
    final ex = await AppDb.db.query('holidays', where: 'hdate = ?', whereArgs: [k]);
    if (ex.isNotEmpty) return 'There is already a holiday on that date (${ex.first['name']}).';
    await AppDb.db.insert('holidays', {'hdate': k, 'name': name, 'type': type});
    await Audit.log('HOLIDAY_ADDED', entity: 'holiday', entityId: k, newValue: '$name ($type)');
    return null;
  }

  static Future<void> delete(int id) async {
    final r = await AppDb.db.query('holidays', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return;
    await AppDb.db.delete('holidays', where: 'id = ?', whereArgs: [id]);
    await Audit.log('HOLIDAY_DELETED',
        entity: 'holiday', entityId: r.first['hdate'] as String, oldValue: '${r.first['name']}');
  }
}

/// Leave days per employee. Paid leave pays Daily staff and is not an absence
/// for fixed-salary staff. Unpaid leave counts as an absence.
/// NOTE: leave rules (credits, who qualifies) must be updated to the company's rules.
class LeaveRepo {
  static const types = ['Vacation', 'Sick', 'Other'];

  static int creditsPerYear() => Settings.getInt('leave_credits', 5);

  static Future<List<DbRow>> forEmployee(int empId, int year) => AppDb.db.query(
      'leave_records',
      where: 'employee_id = ? AND leave_date >= ? AND leave_date <= ?',
      whereArgs: [empId, '$year-01-01', '$year-12-31'],
      orderBy: 'leave_date DESC');

  static Future<int> paidUsed(int empId, int year) async {
    final r = await forEmployee(empId, year);
    return r.where((e) => e['paid'] == 1).length;
  }

  /// Returns an error message, or null when saved.
  static Future<String?> add(int empId, DateTime date, String type, bool paid, String note) async {
    final emp = await EmployeesRepo.byId(empId);
    if (emp == null) return 'Employee not found.';
    final k = _k(date);
    if (k.compareTo(emp['date_hired'] as String) < 0) {
      return 'The leave date is before the date hired.';
    }
    final ex = await AppDb.db.query('leave_records',
        where: 'employee_id = ? AND leave_date = ?', whereArgs: [empId, k]);
    if (ex.isNotEmpty) return 'This employee already has leave on that date.';
    await AppDb.db.insert('leave_records', {
      'employee_id': empId,
      'leave_date': k,
      'type': type,
      'paid': paid ? 1 : 0,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
    await Audit.log('LEAVE_ADDED',
        entity: 'leave', entityId: '${emp['emp_code']} $k', newValue: '$type, ${paid ? 'paid' : 'unpaid'}');
    return null;
  }

  static Future<void> delete(int id) async {
    final r = await AppDb.db.query('leave_records', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return;
    final emp = await EmployeesRepo.byId(r.first['employee_id'] as int);
    await AppDb.db.delete('leave_records', where: 'id = ?', whereArgs: [id]);
    await Audit.log('LEAVE_DELETED',
        entity: 'leave',
        entityId: '${emp?['emp_code']} ${r.first['leave_date']}',
        oldValue: '${r.first['type']}, ${r.first['paid'] == 1 ? 'paid' : 'unpaid'}');
  }
}
