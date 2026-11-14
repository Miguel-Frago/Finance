import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Single local SQLite database (fully offline).
/// Schema version 1 = Phase 1 tables only. Later phases add tables via onUpgrade.
class AppDb {
  static Database? _db;
  static late String path;
  static late String supportDir;

  static Database get db => _db!;

  static Future<void> init() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    supportDir = dir.path;
    path = p.join(dir.path, 'bfm.db');
    _db = await _open();
  }

  static Future<Database> _open() => openDatabase(
        path,
        version: 5,
        onCreate: (d, v) async {
          await _v1(d);
          await _v2(d);
          await _v3(d, seed: false);
          await _v4(d);
          await _v5(d);
        },
        onUpgrade: (d, oldV, newV) async {
          if (oldV < 2) await _v2(d);
          if (oldV < 3) await _v3(d, seed: true);
          if (oldV < 4) await _v4(d);
          if (oldV < 5) await _v5(d);
        },
      );

  /// Holidays, leave, and loans / cash advances.
  static Future<void> _v5(Database d) async {
    await d.execute('''
      CREATE TABLE holidays(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hdate TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        type TEXT NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE leave_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees(id),
        leave_date TEXT NOT NULL,
        type TEXT NOT NULL,
        paid INTEGER NOT NULL DEFAULT 1,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        UNIQUE(employee_id, leave_date)
      )''');
    await d.execute('''
      CREATE TABLE loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees(id),
        label TEXT NOT NULL,
        principal_centavos INTEGER NOT NULL,
        per_payroll_centavos INTEGER NOT NULL,
        balance_centavos INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'Active',
        start_date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE loan_payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER NOT NULL REFERENCES loans(id),
        period_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        amount_centavos INTEGER NOT NULL,
        paid_on TEXT NOT NULL
      )''');
    await d.execute('ALTER TABLE payroll_lines ADD COLUMN loan_id INTEGER');
    await d.execute('CREATE INDEX idx_leave_emp ON leave_records(employee_id, leave_date)');
    await d.execute('CREATE INDEX idx_loans_emp ON loans(employee_id)');
  }

  /// Payroll: periods, one item per employee per period, and detail lines.
  /// Items keep a snapshot of name/position/rate so approved payrolls never change.
  static Future<void> _v4(Database d) async {
    await d.execute('''
      CREATE TABLE payroll_periods(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        date_from TEXT NOT NULL,
        date_to TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Draft',
        created_at TEXT NOT NULL,
        computed_at TEXT,
        approved_at TEXT,
        paid_at TEXT
      )''');
    await d.execute('''
      CREATE TABLE payroll_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        period_id INTEGER NOT NULL REFERENCES payroll_periods(id),
        employee_id INTEGER NOT NULL REFERENCES employees(id),
        emp_code TEXT NOT NULL,
        emp_name TEXT NOT NULL,
        position TEXT NOT NULL DEFAULT '',
        department TEXT NOT NULL DEFAULT '',
        pay_type TEXT NOT NULL,
        rate_centavos INTEGER NOT NULL,
        days_worked INTEGER NOT NULL DEFAULT 0,
        absent_days INTEGER NOT NULL DEFAULT 0,
        shortfall_min INTEGER NOT NULL DEFAULT 0,
        overtime_min INTEGER NOT NULL DEFAULT 0,
        basic_centavos INTEGER NOT NULL DEFAULT 0,
        overtime_centavos INTEGER NOT NULL DEFAULT 0,
        absence_ded_centavos INTEGER NOT NULL DEFAULT 0,
        late_ded_centavos INTEGER NOT NULL DEFAULT 0,
        additions_centavos INTEGER NOT NULL DEFAULT 0,
        statutory_centavos INTEGER NOT NULL DEFAULT 0,
        other_ded_centavos INTEGER NOT NULL DEFAULT 0,
        gross_centavos INTEGER NOT NULL DEFAULT 0,
        net_centavos INTEGER NOT NULL DEFAULT 0,
        warnings TEXT NOT NULL DEFAULT '',
        UNIQUE(period_id, employee_id)
      )''');
    await d.execute('''
      CREATE TABLE payroll_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL REFERENCES payroll_items(id),
        kind TEXT NOT NULL,
        label TEXT NOT NULL,
        amount_centavos INTEGER NOT NULL,
        manual INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('CREATE INDEX idx_pitems_period ON payroll_items(period_id)');
    await d.execute('CREATE INDEX idx_plines_item ON payroll_lines(item_id)');
    // Company-defined deductions (SSS, PhilHealth, Pag-IBIG, tax ...).
    // percent_bp = percent x 100 (4.5% -> 450). Nothing is deducted until set.
    await d.execute('''
      CREATE TABLE statutory_rules(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        base TEXT NOT NULL DEFAULT 'gross',
        percent_bp INTEGER NOT NULL DEFAULT 0,
        cap_centavos INTEGER,
        enabled INTEGER NOT NULL DEFAULT 1
      )''');
    for (final n in ['SSS', 'PhilHealth', 'Pag-IBIG', 'Withholding tax']) {
      await d.insert('statutory_rules', {'name': n});
    }
  }

  /// Rate/position history (effective-dated) and performance reviews.
  /// Existing employees get one starting entry dated on their hire date.
  static Future<void> _v3(Database d, {required bool seed}) async {
    await d.execute('''
      CREATE TABLE employee_rates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees(id),
        effective_date TEXT NOT NULL,
        position TEXT NOT NULL DEFAULT '',
        department TEXT NOT NULL DEFAULT '',
        pay_type TEXT NOT NULL,
        rate_centavos INTEGER NOT NULL,
        reason TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )''');
    await d.execute(
        'CREATE INDEX idx_rates_emp ON employee_rates(employee_id, effective_date)');
    await d.execute('''
      CREATE TABLE performance_reviews(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees(id),
        review_date TEXT NOT NULL,
        rating INTEGER NOT NULL,
        reviewer TEXT NOT NULL DEFAULT '',
        comments TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )''');
    await d.execute(
        'CREATE INDEX idx_reviews_emp ON performance_reviews(employee_id, review_date)');
    if (seed) {
      await d.execute('''
        INSERT INTO employee_rates(employee_id, effective_date, position,
          department, pay_type, rate_centavos, reason, note, created_at)
        SELECT id, date_hired, position, department, pay_type, rate_centavos,
          'Hired', '', created_at FROM employees''');
    }
  }

  /// Phase 2: employees and attendance. Money is stored in centavos (integers)
  /// so peso amounts never suffer rounding errors.
  static Future<void> _v2(Database d) async {
    await d.execute('''
      CREATE TABLE employees(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        emp_code TEXT NOT NULL UNIQUE,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        position TEXT NOT NULL DEFAULT '',
        department TEXT NOT NULL DEFAULT '',
        contact TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'Active',
        pay_type TEXT NOT NULL DEFAULT 'Monthly',
        rate_centavos INTEGER NOT NULL DEFAULT 0,
        date_hired TEXT NOT NULL,
        date_terminated TEXT,
        sss_no TEXT NOT NULL DEFAULT '',
        philhealth_no TEXT NOT NULL DEFAULT '',
        pagibig_no TEXT NOT NULL DEFAULT '',
        tin_no TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE attendance_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees(id),
        work_date TEXT NOT NULL,
        time_in TEXT NOT NULL,
        time_out TEXT,
        method TEXT NOT NULL DEFAULT 'manual',
        minutes_worked INTEGER NOT NULL DEFAULT 0,
        late_minutes INTEGER NOT NULL DEFAULT 0,
        undertime_minutes INTEGER NOT NULL DEFAULT 0,
        overtime_minutes INTEGER NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        UNIQUE(employee_id, work_date)
      )''');
    await d.execute(
        'CREATE INDEX idx_att_date ON attendance_records(work_date)');
    await d.execute('CREATE INDEX idx_emp_status ON employees(status)');
  }

  static Future<void> _v1(Database d) async {
    await d.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE audit_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at TEXT NOT NULL,
        device TEXT NOT NULL,
        action TEXT NOT NULL,
        entity TEXT NOT NULL DEFAULT '',
        entity_id TEXT NOT NULL DEFAULT '',
        old_value TEXT,
        new_value TEXT
      )''');
    // The audit trail cannot be edited or deleted from inside the app.
    await d.execute('''
      CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_log
      BEGIN SELECT RAISE(ABORT, 'audit_log is read-only'); END''');
    await d.execute('''
      CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log
      BEGIN SELECT RAISE(ABORT, 'audit_log is read-only'); END''');
    await d.execute('CREATE INDEX idx_audit_at ON audit_log(at)');
  }

  static Future<void> checkpoint() async {
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> reopen() async {
    _db = await _open();
  }
}
