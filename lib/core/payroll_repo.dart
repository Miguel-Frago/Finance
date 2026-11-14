import 'dart:math';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;
import 'attendance_calc.dart' show parseHm;
import 'attendance_repo.dart';
import 'audit.dart';
import 'db.dart';
import 'employees_repo.dart';
import 'payroll_calc.dart';
import 'settings.dart';

class PayrollRepo {
  static String _k(DateTime d) => PayrollCalc.key(d);

  // ------------------------------------------------------------ settings

  /// Overtime % (default 125), days-per-year factor (default 261) and working
  /// weekdays (default Mon-Fri) are company rules kept in Settings.
  static PayrollSettings settings() {
    final sch = AttendanceRepo.schedule();
    var std = sch.endMin - sch.startMin - sch.breakMin;
    if (std <= 0) std = 480;
    final days = Settings.get('work_days', '1,2,3,4,5')
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toSet();
    return PayrollSettings(
      stdMinutes: std,
      daysFactor: Settings.getInt('days_factor', 261),
      workWeekdays: days.isEmpty ? {1, 2, 3, 4, 5} : days,
      otMultiplier: Settings.getInt('ot_pct', 125) / 100,
      holRegularPct: Settings.getInt('hol_reg_pct', 200).toDouble(),
      holSpecialPct: Settings.getInt('hol_spc_pct', 130).toDouble(),
      holRegularUnworkedPaid: Settings.get('hol_reg_unworked', '1') == '1',
      restDayPct: Settings.getInt('restday_pct', 130).toDouble(),
      ndPct: Settings.getInt('nd_pct', 10).toDouble(),
    );
  }

  // ------------------------------------------------ statutory deduction rules

  static Future<List<DbRow>> rules({bool enabledOnly = false, DatabaseExecutor? ex}) =>
      (ex ?? AppDb.db).query('statutory_rules',
          where: enabledOnly ? 'enabled = 1' : null, orderBy: 'id');

  static Future<void> saveRule(DbRow v, {int? id}) async {
    if (id == null) {
      await AppDb.db.insert('statutory_rules', v);
    } else {
      await AppDb.db.update('statutory_rules', v, where: 'id = ?', whereArgs: [id]);
    }
    await Audit.log('DEDUCTION_RULE_SAVED',
        entity: 'rule',
        entityId: '${v['name']}',
        newValue:
            '${((v['percent_bp'] as int) / 100).toStringAsFixed(2)}% of ${v['base']}'
            '${v['cap_centavos'] == null ? '' : ', cap ${EmployeesRepo.pesos(v['cap_centavos'] as int)}'}'
            '${v['enabled'] == 1 ? '' : ' (off)'}');
  }

  static Future<void> deleteRule(int id, String name) async {
    await AppDb.db.delete('statutory_rules', where: 'id = ?', whereArgs: [id]);
    await Audit.log('DEDUCTION_RULE_DELETED', entity: 'rule', entityId: name);
  }

  // -------------------------------------------------------------- periods

  static Future<List<DbRow>> periods() => AppDb.db.rawQuery('''
    SELECT p.*,
      (SELECT COUNT(*) FROM payroll_items i WHERE i.period_id = p.id) AS n,
      (SELECT COALESCE(SUM(net_centavos), 0) FROM payroll_items i WHERE i.period_id = p.id) AS net
    FROM payroll_periods p ORDER BY date_from DESC, id DESC''');

  static Future<DbRow?> period(int id) async {
    final r = await AppDb.db.query('payroll_periods', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  static Future<List<DbRow>> overlapping(String from, String to) =>
      AppDb.db.query('payroll_periods',
          where: 'date_from <= ? AND date_to >= ?', whereArgs: [to, from]);

  static Future<int> createPeriod(String label, DateTime from, DateTime to) async {
    final id = await AppDb.db.insert('payroll_periods', {
      'label': label,
      'date_from': _k(from),
      'date_to': _k(to),
      'status': 'Draft',
      'created_at': DateTime.now().toIso8601String(),
    });
    await Audit.log('PAYROLL_PERIOD_CREATED',
        entity: 'payroll', entityId: label, newValue: '${_k(from)} to ${_k(to)}');
    return id;
  }

  static Future<List<DbRow>> items(int periodId) => AppDb.db.query('payroll_items',
      where: 'period_id = ?',
      whereArgs: [periodId],
      orderBy: 'emp_name COLLATE NOCASE');

  static Future<DbRow?> item(int id) async {
    final r = await AppDb.db.query('payroll_items', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  static Future<List<DbRow>> lines(int itemId) => AppDb.db.query('payroll_lines',
      where: 'item_id = ?', whereArgs: [itemId], orderBy: 'kind, id');

  // ------------------------------------------------------------- compute

  /// (Re)computes every employee for a Draft or Computed period.
  /// Manual additions/deductions entered earlier are kept.
  static Future<int> compute(int periodId) async {
    final p = await period(periodId);
    if (p == null) return 0;
    if (p['status'] != 'Draft' && p['status'] != 'Computed') {
      throw StateError('This payroll is locked.');
    }
    final fromK = p['date_from'] as String;
    final toK = p['date_to'] as String;
    final st = settings();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final holRows = await AppDb.db.query('holidays',
        where: 'hdate >= ? AND hdate <= ?', whereArgs: [fromK, toK]);
    final holidays = {for (final h in holRows) h['hdate'] as String: h['type'] as String};

    final emps = await AppDb.db.query('employees',
        where: 'date_hired <= ? AND (date_terminated IS NULL OR date_terminated >= ?)',
        whereArgs: [toK, fromK],
        orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE');

    await AppDb.db.transaction((txn) async {
      final keep = <int>[];
      for (final e in emps) {
        final empId = e['id'] as int;
        final rateRows = await txn.query('employee_rates',
            where: 'employee_id = ?', whereArgs: [empId], orderBy: 'effective_date ASC, id ASC');
        final entries = rateRows
            .map((r) => RateEntry(r['effective_date'] as String, r['pay_type'] as String,
                r['rate_centavos'] as int))
            .toList();
        if (entries.isEmpty) continue;
        final attRows = await txn.query('attendance_records',
            where: 'employee_id = ? AND work_date >= ? AND work_date <= ?',
            whereArgs: [empId, fromK, toK]);
        final att = {
          for (final a in attRows)
            a['work_date'] as String: AttDay(
              workedMin: a['minutes_worked'] as int,
              overtimeMin: a['overtime_minutes'] as int,
              lateMin: a['late_minutes'] as int,
              complete: a['time_out'] != null,
              timeInMin: parseHm(a['time_in'] as String),
              timeOutMin: a['time_out'] == null ? null : parseHm(a['time_out'] as String),
            )
        };
        final leaveRows = await txn.query('leave_records',
            columns: ['leave_date'],
            where: 'employee_id = ? AND paid = 1 AND leave_date >= ? AND leave_date <= ?',
            whereArgs: [empId, fromK, toK]);
        final leaveSet = {for (final l in leaveRows) l['leave_date'] as String};
        final term = e['date_terminated'] == null
            ? null
            : DateTime.parse(e['date_terminated'] as String);
        final res = PayrollCalc.compute(
          PayrollCalcInput(
            from: DateTime.parse(fromK),
            to: DateTime.parse(toK),
            hired: DateTime.parse(e['date_hired'] as String),
            terminated: term,
            today: today,
            entries: entries,
            attendance: att,
            holidays: holidays,
            paidLeave: leaveSet,
          ),
          st,
        );
        // snapshot: the entry in effect on the last paid day
        final lastDay = (term != null && term.isBefore(DateTime.parse(toK))) ? _k(term) : toK;
        final snap = PayrollCalc.entryOn(entries, lastDay) ?? entries.first;
        final snapRow = rateRows.lastWhere(
            (r) => r['effective_date'] == snap.effectiveDate,
            orElse: () => rateRows.first);

        final values = {
          'period_id': periodId,
          'employee_id': empId,
          'emp_code': e['emp_code'],
          'emp_name': EmployeesRepo.fullName(e),
          'position': snapRow['position'],
          'department': snapRow['department'],
          'pay_type': snap.payType,
          'rate_centavos': snap.rateCentavos,
          'days_worked': res.daysWorked,
          'absent_days': res.absentDays,
          'shortfall_min': res.shortfallMin,
          'overtime_min': res.overtimeMin,
          'basic_centavos': res.basic,
          'overtime_centavos': res.overtime,
          'absence_ded_centavos': res.absenceDed,
          'late_ded_centavos': res.lateDed,
          'warnings': res.warnings.join('\n'),
        };
        final existing = await txn.query('payroll_items',
            where: 'period_id = ? AND employee_id = ?', whereArgs: [periodId, empId]);
        int itemId;
        if (existing.isEmpty) {
          itemId = await txn.insert('payroll_items', values);
        } else {
          itemId = existing.first['id'] as int;
          await txn.update('payroll_items', values, where: 'id = ?', whereArgs: [itemId]);
        }
        keep.add(itemId);

        // computed earnings and loan deductions are regenerated every time
        await txn.delete('payroll_lines',
            where: "item_id = ? AND kind IN ('earning', 'loan')", whereArgs: [itemId]);
        Future<void> earning(String label, int amt) async {
          if (amt <= 0) return;
          await txn.insert('payroll_lines', {
            'item_id': itemId,
            'kind': 'earning',
            'label': label,
            'amount_centavos': amt,
            'manual': 0,
          });
        }

        await earning('Holiday pay (unworked regular holiday)', res.holidayPay);
        await earning('Holiday premium', res.holidayPremium);
        await earning('Rest day premium', res.restDayPremium);
        await earning('Night differential', res.nightDiff);
        await earning('Paid leave (${res.paidLeaveDays} day/s)', res.paidLeavePay);
        final loans = await txn.query('loans',
            where: "employee_id = ? AND status = 'Active' AND balance_centavos > 0 AND start_date <= ?",
            whereArgs: [empId, toK]);
        for (final ln in loans) {
          final amt = min(ln['per_payroll_centavos'] as int, ln['balance_centavos'] as int);
          if (amt <= 0) continue;
          await txn.insert('payroll_lines', {
            'item_id': itemId,
            'kind': 'loan',
            'label': ln['label'],
            'amount_centavos': amt,
            'manual': 0,
            'loan_id': ln['id'],
          });
        }
        await _finalize(txn, itemId);
      }
      // employees no longer eligible are removed from this (unlocked) period
      final all = await txn.query('payroll_items',
          columns: ['id'], where: 'period_id = ?', whereArgs: [periodId]);
      for (final r in all) {
        final id = r['id'] as int;
        if (!keep.contains(id)) {
          await txn.delete('payroll_lines', where: 'item_id = ?', whereArgs: [id]);
          await txn.delete('payroll_items', where: 'id = ?', whereArgs: [id]);
        }
      }
      await txn.update(
          'payroll_periods',
          {'status': 'Computed', 'computed_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [periodId]);
    });
    await Audit.log('PAYROLL_COMPUTED',
        entity: 'payroll', entityId: p['label'] as String, newValue: '${emps.length} employees');
    return emps.length;
  }

  /// Recomputes gross, deduction rules and net from the stored components,
  /// the computed earning/loan lines and the manual lines. Called after compute
  /// and after any manual change.
  static Future<void> _finalize(DatabaseExecutor ex, int itemId) async {
    final it = (await ex.query('payroll_items', where: 'id = ?', whereArgs: [itemId])).first;
    final lines = await ex.query('payroll_lines', where: 'item_id = ?', whereArgs: [itemId]);
    int manualAdd = 0, manualDed = 0, earnings = 0, loans = 0;
    for (final l in lines) {
      final amt = l['amount_centavos'] as int;
      switch (l['kind']) {
        case 'addition':
          manualAdd += amt;
        case 'deduction':
          manualDed += amt;
        case 'earning':
          earnings += amt;
        case 'loan':
          loans += amt;
      }
    }
    final basicNet = (it['basic_centavos'] as int) -
        (it['absence_ded_centavos'] as int) -
        (it['late_ded_centavos'] as int);
    final gross = basicNet + (it['overtime_centavos'] as int) + manualAdd + earnings;

    await ex.delete('payroll_lines',
        where: "item_id = ? AND kind = 'statutory'", whereArgs: [itemId]);
    int statutory = 0;
    for (final r in await rules(enabledOnly: true, ex: ex)) {
      final base = r['base'] == 'basic' ? basicNet : gross;
      final bp = r['percent_bp'] as int;
      if (base <= 0 || bp <= 0) continue;
      var amt = (base * bp + 5000) ~/ 10000;
      final cap = r['cap_centavos'] as int?;
      if (cap != null && amt > cap) amt = cap;
      if (amt <= 0) continue;
      await ex.insert('payroll_lines', {
        'item_id': itemId,
        'kind': 'statutory',
        'label': r['name'],
        'amount_centavos': amt,
        'manual': 0,
      });
      statutory += amt;
    }
    final otherDed = manualDed + loans;
    await ex.update(
        'payroll_items',
        {
          'additions_centavos': manualAdd + earnings,
          'other_ded_centavos': otherDed,
          'statutory_centavos': statutory,
          'gross_centavos': gross,
          'net_centavos': gross - statutory - otherDed,
        },
        where: 'id = ?',
        whereArgs: [itemId]);
  }

  // -------------------------------------------------- manual adjustments

  static Future<bool> _editable(int itemId) async {
    final r = await AppDb.db.rawQuery(
        'SELECT p.status FROM payroll_items i JOIN payroll_periods p ON p.id = i.period_id WHERE i.id = ?',
        [itemId]);
    return r.isNotEmpty && (r.first['status'] == 'Draft' || r.first['status'] == 'Computed');
  }

  static Future<void> addAdjustment(int itemId,
      {required bool addition, required String label, required int centavos}) async {
    if (!await _editable(itemId)) throw StateError('This payroll is locked.');
    final it = await item(itemId);
    await AppDb.db.transaction((txn) async {
      await txn.insert('payroll_lines', {
        'item_id': itemId,
        'kind': addition ? 'addition' : 'deduction',
        'label': label,
        'amount_centavos': centavos,
        'manual': 1,
      });
      await _finalize(txn, itemId);
    });
    await Audit.log(addition ? 'PAYROLL_ADDITION_ADDED' : 'PAYROLL_DEDUCTION_ADDED',
        entity: 'payroll',
        entityId: '${it?['emp_code']}',
        newValue: '$label ${EmployeesRepo.pesos(centavos)}');
  }

  static Future<void> deleteAdjustment(int lineId) async {
    final l = await AppDb.db.query('payroll_lines', where: 'id = ?', whereArgs: [lineId]);
    if (l.isEmpty || l.first['manual'] != 1) return;
    final itemId = l.first['item_id'] as int;
    if (!await _editable(itemId)) throw StateError('This payroll is locked.');
    final it = await item(itemId);
    await AppDb.db.transaction((txn) async {
      await txn.delete('payroll_lines', where: 'id = ?', whereArgs: [lineId]);
      await _finalize(txn, itemId);
    });
    await Audit.log('PAYROLL_ADJUSTMENT_DELETED',
        entity: 'payroll',
        entityId: '${it?['emp_code']}',
        oldValue:
            '${l.first['label']} ${EmployeesRepo.pesos(l.first['amount_centavos'] as int)}');
  }

  // ------------------------------------------------------------- status

  static Future<void> _move(int id, String from, String to, String action,
      {String? stamp}) async {
    final p = await period(id);
    if (p == null || p['status'] != from) {
      throw StateError('Payroll must be $from to do this.');
    }
    await AppDb.db.update(
        'payroll_periods',
        {'status': to, if (stamp != null) stamp: DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id]);
    await Audit.log(action,
        entity: 'payroll', entityId: p['label'] as String, oldValue: from, newValue: to);
  }

  /// Approving locks the payroll and applies loan deductions to the balances.
  static Future<void> approve(int id) async {
    final p = await period(id);
    if (p == null || p['status'] != 'Computed') {
      throw StateError('Payroll must be Computed to do this.');
    }
    await AppDb.db.transaction((txn) async {
      final lines = await txn.rawQuery('''
        SELECT l.loan_id, l.amount_centavos, l.item_id FROM payroll_lines l
        JOIN payroll_items i ON i.id = l.item_id
        WHERE i.period_id = ? AND l.kind = 'loan' AND l.loan_id IS NOT NULL''', [id]);
      for (final l in lines) {
        final loan = await txn.query('loans', where: 'id = ?', whereArgs: [l['loan_id']]);
        if (loan.isEmpty) continue;
        final bal = loan.first['balance_centavos'] as int;
        final amt = min(l['amount_centavos'] as int, bal);
        if (amt <= 0) continue;
        await txn.insert('loan_payments', {
          'loan_id': l['loan_id'],
          'period_id': id,
          'item_id': l['item_id'],
          'amount_centavos': amt,
          'paid_on': DateTime.now().toIso8601String(),
        });
        await txn.update(
            'loans',
            {'balance_centavos': bal - amt, 'status': bal - amt == 0 ? 'Paid off' : 'Active'},
            where: 'id = ?',
            whereArgs: [l['loan_id']]);
      }
      await txn.update(
          'payroll_periods',
          {'status': 'Approved', 'approved_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [id]);
    });
    await Audit.log('PAYROLL_APPROVED',
        entity: 'payroll', entityId: p['label'] as String, oldValue: 'Computed', newValue: 'Approved');
  }

  /// Reopening puts loan balances back to what they were before approval.
  static Future<void> reopen(int id) async {
    final p = await period(id);
    if (p == null || p['status'] != 'Approved') {
      throw StateError('Payroll must be Approved to do this.');
    }
    await AppDb.db.transaction((txn) async {
      final pays = await txn.query('loan_payments', where: 'period_id = ?', whereArgs: [id]);
      for (final pay in pays) {
        final loan = await txn.query('loans', where: 'id = ?', whereArgs: [pay['loan_id']]);
        if (loan.isEmpty) continue;
        final status = loan.first['status'] == 'Cancelled' ? 'Cancelled' : 'Active';
        await txn.update(
            'loans',
            {
              'balance_centavos':
                  (loan.first['balance_centavos'] as int) + (pay['amount_centavos'] as int),
              'status': status,
            },
            where: 'id = ?',
            whereArgs: [pay['loan_id']]);
      }
      await txn.delete('loan_payments', where: 'period_id = ?', whereArgs: [id]);
      await txn.update('payroll_periods', {'status': 'Computed'},
          where: 'id = ?', whereArgs: [id]);
    });
    await Audit.log('PAYROLL_REOPENED',
        entity: 'payroll', entityId: p['label'] as String, oldValue: 'Approved', newValue: 'Computed');
  }

  static Future<void> markPaid(int id) =>
      _move(id, 'Approved', 'Paid', 'PAYROLL_PAID', stamp: 'paid_at');

  static Future<void> deletePeriod(int id) async {
    final p = await period(id);
    if (p == null) return;
    if (p['status'] != 'Draft' && p['status'] != 'Computed') {
      throw StateError('Only Draft or Computed payrolls can be deleted.');
    }
    await AppDb.db.transaction((txn) async {
      final its = await txn.query('payroll_items',
          columns: ['id'], where: 'period_id = ?', whereArgs: [id]);
      for (final r in its) {
        await txn.delete('payroll_lines', where: 'item_id = ?', whereArgs: [r['id']]);
      }
      await txn.delete('payroll_items', where: 'period_id = ?', whereArgs: [id]);
      await txn.delete('payroll_periods', where: 'id = ?', whereArgs: [id]);
    });
    await Audit.log('PAYROLL_PERIOD_DELETED',
        entity: 'payroll', entityId: p['label'] as String);
  }
}
