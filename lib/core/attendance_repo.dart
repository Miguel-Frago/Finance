import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'attendance_calc.dart';
import 'audit.dart';
import 'db.dart';
import 'employees_repo.dart';
import 'settings.dart';

class AttendanceRepo {
  static String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static WorkSchedule schedule() => WorkSchedule(
        startMin: parseHm(Settings.get('work_start', '08:00')),
        endMin: parseHm(Settings.get('work_end', '17:00')),
        breakMin: Settings.getInt('break_minutes', 60),
        graceMin: Settings.getInt('grace_minutes', 0),
      );

  /// Every active employee (hired on or before [date]) with their record for
  /// that date, if any (att_id is null when there is none).
  static Future<List<DbRow>> forDate(String date) => AppDb.db.rawQuery('''
    SELECT e.id, e.emp_code, e.first_name, e.last_name, e.position, e.department,
           a.id AS att_id, a.time_in, a.time_out, a.method, a.minutes_worked,
           a.late_minutes, a.undertime_minutes, a.overtime_minutes, a.note
    FROM employees e
    LEFT JOIN attendance_records a ON a.employee_id = e.id AND a.work_date = ?
    WHERE e.status = 'Active' AND e.date_hired <= ?
    ORDER BY e.last_name COLLATE NOCASE, e.first_name COLLATE NOCASE
  ''', [date, date]);

  static String _desc(String? tin, String? tout) =>
      'in ${tin ?? '-'} out ${tout ?? '-'}';

  /// Insert or update the record for one employee and day. Times are minutes
  /// since midnight. Late/undertime/overtime are computed and stored.
  static Future<void> save({
    required int employeeId,
    required String empCode,
    required String date,
    required int timeIn,
    int? timeOut,
    required String method,
    String note = '',
  }) async {
    final r = AttendanceCalc.compute(schedule(), timeIn, timeOut);
    final values = {
      'employee_id': employeeId,
      'work_date': date,
      'time_in': fmtHm(timeIn),
      'time_out': timeOut == null ? null : fmtHm(timeOut),
      'method': method,
      'minutes_worked': r.worked,
      'late_minutes': r.lateMin,
      'undertime_minutes': r.undertime,
      'overtime_minutes': r.overtime,
      'note': note,
    };
    final existing = await AppDb.db.query('attendance_records',
        where: 'employee_id = ? AND work_date = ?',
        whereArgs: [employeeId, date],
        limit: 1);
    String? oldDesc;
    if (existing.isEmpty) {
      await AppDb.db.insert('attendance_records', values);
    } else {
      final o = existing.first;
      oldDesc = _desc(o['time_in'] as String?, o['time_out'] as String?);
      await AppDb.db.update('attendance_records', values,
          where: 'id = ?', whereArgs: [o['id']]);
    }
    await Audit.log('ATTENDANCE_SAVED',
        entity: 'attendance',
        entityId: '$empCode $date ($method)',
        oldValue: oldDesc,
        newValue: _desc(fmtHm(timeIn), timeOut == null ? null : fmtHm(timeOut)));
  }

  static Future<void> delete(int attId, String empCode, String date,
      String? timeIn, String? timeOut) async {
    await AppDb.db
        .delete('attendance_records', where: 'id = ?', whereArgs: [attId]);
    await Audit.log('ATTENDANCE_DELETED',
        entity: 'attendance',
        entityId: '$empCode $date',
        oldValue: _desc(timeIn, timeOut));
  }

  /// Numbers for the dashboard.
  static Future<Map<String, int>> stats() async {
    final today = dateKey(DateTime.now());
    final active = Sqflite.firstIntValue(await AppDb.db
            .rawQuery("SELECT COUNT(*) FROM employees WHERE status = 'Active'")) ??
        0;
    final terminated = Sqflite.firstIntValue(await AppDb.db.rawQuery(
            "SELECT COUNT(*) FROM employees WHERE status = 'Terminated'")) ??
        0;
    final expected = Sqflite.firstIntValue(await AppDb.db.rawQuery(
            "SELECT COUNT(*) FROM employees WHERE status = 'Active' AND date_hired <= ?",
            [today])) ??
        0;
    final att = await AppDb.db.rawQuery('''
      SELECT COUNT(*) AS total,
             SUM(CASE WHEN a.late_minutes > 0 THEN 1 ELSE 0 END) AS late
      FROM attendance_records a JOIN employees e ON e.id = a.employee_id
      WHERE a.work_date = ? AND e.status = 'Active' ''', [today]);
    final present = (att.first['total'] as int?) ?? 0;
    final lateCount = (att.first['late'] as int?) ?? 0;
    return {
      'active': active,
      'terminated': terminated,
      'present': present,
      'late': lateCount,
      'notYet': (expected - present).clamp(0, 1 << 30),
    };
  }
}
