import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'attendance_repo.dart';
import 'db.dart';
import 'employees_repo.dart';
import 'payroll_repo.dart';
import 'settings.dart';

class DayAtt {
  final DateTime date;
  final int present, lateCount;
  const DayAtt(this.date, this.present, this.lateCount);
}

class DashData {
  final Map<String, int> stats;
  final List<DayAtt> week;
  final List<DbRow> trend; // oldest first
  final DbRow? latest; // latest period that has employees
  final List<DbRow> dept; // pay by department for [latest]
  final int loansOutstanding;
  const DashData(this.stats, this.week, this.trend, this.latest, this.dept, this.loansOutstanding);
}

/// Dashboard widgets the manager can show or hide. The printed dashboard
/// report follows exactly what is visible.
const dashWidgets = <String, String>{
  'kpi': 'Key numbers',
  'attendance_week': 'Attendance, last 7 days',
  'payroll_trend': 'Payroll by period',
  'dept_cost': 'Pay by department (latest payroll)',
  'data_safety': 'Data safety',
  'color_guide': 'Color guide',
};

class DashboardRepo {
  static Set<String> hidden() =>
      Settings.get('dash_hidden').split(',').where((e) => e.isNotEmpty).toSet();

  static Future<void> setHidden(Set<String> keys) =>
      Settings.set('dash_hidden', (keys.toList()..sort()).join(','));

  static Future<DashData> load() async {
    final stats = await AttendanceRepo.stats();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(today.year, today.month, today.day - 6);
    final rows = await AppDb.db.rawQuery('''
      SELECT a.work_date, COUNT(*) AS total,
             SUM(CASE WHEN a.late_minutes > 0 THEN 1 ELSE 0 END) AS late
      FROM attendance_records a JOIN employees e ON e.id = a.employee_id
      WHERE a.work_date >= ? AND a.work_date <= ?
      GROUP BY a.work_date''',
        [AttendanceRepo.dateKey(first), AttendanceRepo.dateKey(today)]);
    final byDate = {for (final r in rows) r['work_date'] as String: r};
    final week = <DayAtt>[];
    for (var i = 0; i < 7; i++) {
      final d = DateTime(first.year, first.month, first.day + i);
      final r = byDate[AttendanceRepo.dateKey(d)];
      week.add(DayAtt(d, (r?['total'] as int?) ?? 0, (r?['late'] as int?) ?? 0));
    }

    final periods = await PayrollRepo.periods(); // newest first
    final trend = periods.take(6).toList().reversed.toList();
    DbRow? latest;
    for (final p in periods) {
      if ((p['n'] as int) > 0) {
        latest = p;
        break;
      }
    }
    final dept = latest == null
        ? <DbRow>[]
        : await AppDb.db.rawQuery('''
            SELECT CASE WHEN department = '' THEN '(none)' ELSE department END AS dept,
                   COUNT(*) AS n, SUM(net_centavos) AS net
            FROM payroll_items WHERE period_id = ?
            GROUP BY dept ORDER BY net DESC''', [latest['id']]);
    final loans = Sqflite.firstIntValue(await AppDb.db.rawQuery(
            "SELECT COALESCE(SUM(balance_centavos), 0) FROM loans WHERE status = 'Active'")) ??
        0;
    return DashData(stats, week, trend, latest, dept, loans);
  }

  static String shortDate(String iso) => DateFormat('MMM d').format(DateTime.parse(iso));
}
