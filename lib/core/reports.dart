import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'attendance_calc.dart';
import 'dashboard_repo.dart';
import 'db.dart';
import 'employees_repo.dart';
import 'loans_repo.dart';
import 'payroll_calc.dart';
import 'payroll_repo.dart';
import 'report_kit.dart';
import 'settings.dart';

/// Builds every printable report as a PDF. [f] is the paper size chosen in the
/// preview screen (A4, Letter or Legal).
class Reports {
  static final _d = DateFormat('MMM d, y');
  static String _p(int c) => EmployeesRepo.pesos(c);
  static String _neg(int c) => EmployeesRepo.pesos(-c);
  static String _printed() => 'Printed ${DateFormat('MMM d, y h:mm a').format(DateTime.now())}';

  static pw.MultiPage _page(ReportKit kit, PdfPageFormat f, String title, String sub,
      List<pw.Widget> body, {bool landscape = false}) {
    return pw.MultiPage(
      pageFormat: landscape ? f.landscape : f,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
      header: (c) => kit.header(title, sub),
      footer: kit.footer,
      build: (c) => body,
    );
  }

  // ------------------------------------------------------ employee masterlist

  static Future<Uint8List> masterlist(PdfPageFormat f, String status) async {
    final kit = await ReportKit.load();
    final rows = await EmployeesRepo.list(status: status);
    final doc = kit.newDoc();
    doc.addPage(_page(kit, f, 'Employee masterlist', '$status employees  |  ${_printed()}', [
      kit.table(
        ['ID', 'Name', 'Position', 'Department', 'Pay type', 'Rate', 'Hired', 'Status'],
        [
          for (final r in rows)
            [
              r['emp_code'] as String,
              EmployeesRepo.fullName(r),
              r['position'] as String,
              r['department'] as String,
              r['pay_type'] as String,
              '${_p(r['rate_centavos'] as int)} / ${EmployeesRepo.payUnit[r['pay_type']]}',
              _d.format(DateTime.parse(r['date_hired'] as String)),
              r['status'] as String,
            ]
        ],
        right: {5},
      ),
      pw.SizedBox(height: 6),
      pw.Text('Total: ${rows.length} employees', style: const pw.TextStyle(fontSize: 9)),
    ], landscape: true));
    return doc.save();
  }

  // ------------------------------------------------------- attendance summary

  static Future<Uint8List> attendance(PdfPageFormat f, DateTime from, DateTime to) async {
    final kit = await ReportKit.load();
    final fromK = PayrollCalc.key(from), toK = PayrollCalc.key(to);
    final emps = await AppDb.db.query('employees',
        where: 'date_hired <= ? AND (date_terminated IS NULL OR date_terminated >= ?)',
        whereArgs: [toK, fromK],
        orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE');
    final recs = await AppDb.db.query('attendance_records',
        where: 'work_date >= ? AND work_date <= ?', whereArgs: [fromK, toK]);
    final byEmp = <int, List<DbRow>>{};
    for (final r in recs) {
      byEmp.putIfAbsent(r['employee_id'] as int, () => []).add(r);
    }
    final workdays = PayrollRepo.settings().workWeekdays;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final data = <List<String>>[];
    for (final e in emps) {
      final list = byEmp[e['id'] as int] ?? [];
      final dates = {for (final r in list) r['work_date'] as String};
      int worked = 0, late = 0, under = 0, over = 0, absent = 0;
      for (final r in list) {
        worked += r['minutes_worked'] as int;
        late += r['late_minutes'] as int;
        under += r['undertime_minutes'] as int;
        over += r['overtime_minutes'] as int;
      }
      final hired = DateTime.parse(e['date_hired'] as String);
      final term = e['date_terminated'] == null ? null : DateTime.parse(e['date_terminated'] as String);
      var d = hired.isAfter(from) ? hired : from;
      final end = (term != null && term.isBefore(to)) ? term : to;
      for (; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
        if (workdays.contains(d.weekday) && d.isBefore(today) && !dates.contains(PayrollCalc.key(d))) {
          absent++;
        }
      }
      data.add([
        e['emp_code'] as String,
        EmployeesRepo.fullName(e),
        e['department'] as String,
        '${list.length}',
        '$absent',
        fmtDuration(worked),
        '$late',
        '$under',
        '$over',
      ]);
    }
    final doc = kit.newDoc();
    doc.addPage(_page(kit, f, 'Attendance report',
        '${_d.format(from)} to ${_d.format(to)}  |  ${_printed()}', [
      kit.table(
        ['ID', 'Name', 'Department', 'Days present', 'Days absent*', 'Hours worked', 'Late (min)', 'Undertime (min)', 'Overtime (min)'],
        data,
        right: {3, 4, 5, 6, 7, 8},
      ),
      pw.SizedBox(height: 6),
      pw.Text(
          '*Absent = working day before today with no attendance record. Holidays and leave are not excluded yet.',
          style: const pw.TextStyle(fontSize: 7.5)),
    ], landscape: true));
    return doc.save();
  }

  // --------------------------------------------------------- payroll register

  static String _sub(DbRow p) {
    final status = p['status'] as String;
    final draft = (status == 'Draft' || status == 'Computed') ? '  |  NOT FINAL ($status)' : '  |  $status';
    return '${p['label']}  |  ${_d.format(DateTime.parse(p['date_from'] as String))} to ${_d.format(DateTime.parse(p['date_to'] as String))}$draft';
  }

  static Future<Uint8List> payrollRegister(PdfPageFormat f, int periodId) async {
    final kit = await ReportKit.load();
    final p = (await PayrollRepo.period(periodId))!;
    final items = await PayrollRepo.items(periodId);
    int tBasic = 0, tOt = 0, tAbs = 0, tAdd = 0, tGross = 0, tStat = 0, tOther = 0, tNet = 0;
    final data = <List<String>>[];
    for (final i in items) {
      final abs = (i['absence_ded_centavos'] as int) + (i['late_ded_centavos'] as int);
      tBasic += i['basic_centavos'] as int;
      tOt += i['overtime_centavos'] as int;
      tAbs += abs;
      tAdd += i['additions_centavos'] as int;
      tGross += i['gross_centavos'] as int;
      tStat += i['statutory_centavos'] as int;
      tOther += i['other_ded_centavos'] as int;
      tNet += i['net_centavos'] as int;
      data.add([
        '${i['emp_name']}\n${i['emp_code']}',
        '${i['pay_type']}\n${_p(i['rate_centavos'] as int)}',
        _p(i['basic_centavos'] as int),
        _p(i['overtime_centavos'] as int),
        _neg(abs),
        _p(i['additions_centavos'] as int),
        _p(i['gross_centavos'] as int),
        _neg(i['statutory_centavos'] as int),
        _neg(i['other_ded_centavos'] as int),
        _p(i['net_centavos'] as int),
      ]);
    }
    data.add(['TOTAL (${items.length})', '', _p(tBasic), _p(tOt), _neg(tAbs), _p(tAdd), _p(tGross),
      _neg(tStat), _neg(tOther), _p(tNet)]);
    final doc = kit.newDoc();
    doc.addPage(_page(kit, f, 'Payroll register', _sub(p), [
      kit.table(
        ['Employee', 'Pay', 'Basic', 'Overtime', 'Absent / late', 'Additions & premiums', 'Gross', 'Gov. & company ded.', 'Loans & other ded.', 'Net pay'],
        data,
        right: {2, 3, 4, 5, 6, 7, 8, 9},
      ),
    ], landscape: true));
    return doc.save();
  }

  // ----------------------------------------------------------------- payslips

  static pw.Widget _col(String title, List<List<String>> rows, String totalLabel, int total) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(title, style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
      pw.Divider(thickness: 0.4, height: 6),
      for (final r in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Expanded(child: pw.Text(r[0], style: const pw.TextStyle(fontSize: 9))),
            pw.Text(r[1], style: const pw.TextStyle(fontSize: 9)),
          ]),
        ),
      pw.Divider(thickness: 0.4, height: 8),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(totalLabel, style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        pw.Text(_p(total), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
      ]),
    ]);
  }

  static pw.Widget _slip(ReportKit kit, DbRow p, DbRow it, List<DbRow> lines) {
    final adds = lines.where((l) => l['kind'] == 'addition' || l['kind'] == 'earning');
    final stat = lines.where((l) => l['kind'] == 'statutory' || l['kind'] == 'loan');
    final deds = lines.where((l) => l['kind'] == 'deduction');
    final earn = <List<String>>[
      ['Basic pay', _p(it['basic_centavos'] as int)],
      if ((it['absence_ded_centavos'] as int) > 0)
        ['Absences (${it['absent_days']} day/s)', _neg(it['absence_ded_centavos'] as int)],
      if ((it['late_ded_centavos'] as int) > 0)
        ['Late / undertime (${it['shortfall_min']} min)', _neg(it['late_ded_centavos'] as int)],
      if ((it['overtime_centavos'] as int) > 0)
        ['Overtime (${it['overtime_min']} min)', _p(it['overtime_centavos'] as int)],
      for (final l in adds) [l['label'] as String, _p(l['amount_centavos'] as int)],
    ];
    final dedRows = <List<String>>[
      for (final l in stat) [l['label'] as String, _p(l['amount_centavos'] as int)],
      for (final l in deds) [l['label'] as String, _p(l['amount_centavos'] as int)],
    ];
    if (dedRows.isEmpty) dedRows.add(['None', _p(0)]);
    final totalDed = (it['statutory_centavos'] as int) + (it['other_ded_centavos'] as int);

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        kit.header('PAYSLIP', _sub(p)),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(it['emp_name'] as String,
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.Text('ID: ${it['emp_code']}', style: const pw.TextStyle(fontSize: 9)),
        ]),
        pw.Text('${it['position']}  |  ${it['department']}', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('${it['pay_type']} rate: ${_p(it['rate_centavos'] as int)}',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 10),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: _col('EARNINGS', earn, 'Gross pay', it['gross_centavos'] as int)),
          pw.SizedBox(width: 16),
          pw.Expanded(child: _col('DEDUCTIONS', dedRows, 'Total deductions', totalDed)),
        ]),
        pw.SizedBox(height: 10),
        pw.Container(
          color: PdfColors.grey200,
          padding: const pw.EdgeInsets.all(8),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('NET PAY', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
            pw.Text(_p(it['net_centavos'] as int),
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          ]),
        ),
        pw.SizedBox(height: 18),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          kit.sigLine('Employee signature'),
          kit.sigLine('Approved by', withImage: true),
        ]),
      ]),
    );
  }

  /// One payslip per page. Pass [itemId] for a single employee.
  static Future<Uint8List> payslips(PdfPageFormat f, int periodId, {int? itemId}) async {
    final kit = await ReportKit.load();
    final p = (await PayrollRepo.period(periodId))!;
    var items = await PayrollRepo.items(periodId);
    if (itemId != null) items = items.where((i) => i['id'] == itemId).toList();
    final doc = kit.newDoc();
    for (final it in items) {
      final lines = await PayrollRepo.lines(it['id'] as int);
      doc.addPage(pw.MultiPage(
        pageFormat: f,
        margin: const pw.EdgeInsets.all(28),
        build: (c) => [_slip(kit, p, it, lines)],
      ));
    }
    if (items.isEmpty) {
      doc.addPage(pw.Page(pageFormat: f, build: (c) => pw.Center(child: pw.Text('No payslips. Compute the payroll first.'))));
    }
    return doc.save();
  }

  // ------------------------------------------------------ deductions summary

  static Future<Uint8List> deductions(PdfPageFormat f, int periodId) async {
    final kit = await ReportKit.load();
    final p = (await PayrollRepo.period(periodId))!;
    final items = await PayrollRepo.items(periodId);
    final lines = await AppDb.db.rawQuery('''
      SELECT l.item_id, l.label, l.amount_centavos FROM payroll_lines l
      JOIN payroll_items i ON i.id = l.item_id
      WHERE i.period_id = ? AND l.kind = 'statutory' ''', [periodId]);
    final labels = <String>[];
    final by = <int, Map<String, int>>{};
    for (final l in lines) {
      final lab = l['label'] as String;
      if (!labels.contains(lab)) labels.add(lab);
      by.putIfAbsent(l['item_id'] as int, () => {})[lab] = l['amount_centavos'] as int;
    }
    final totals = {for (final l in labels) l: 0};
    int grand = 0;
    final data = <List<String>>[];
    for (final i in items) {
      final m = by[i['id'] as int] ?? {};
      int sum = 0;
      final row = <String>['${i['emp_name']}  (${i['emp_code']})', _p(i['gross_centavos'] as int)];
      for (final l in labels) {
        final a = m[l] ?? 0;
        totals[l] = totals[l]! + a;
        sum += a;
        row.add(_p(a));
      }
      grand += sum;
      row.add(_p(sum));
      data.add(row);
    }
    data.add(['TOTAL', '', for (final l in labels) _p(totals[l]!), _p(grand)]);
    final doc = kit.newDoc();
    doc.addPage(_page(kit, f, 'Government & company deductions', _sub(p), [
      if (labels.isEmpty)
        pw.Text('No deductions were applied. Set the percentages under Payroll rules, then recompute.')
      else
        kit.table(['Employee', 'Gross pay', ...labels, 'Total'], data,
            right: {for (var i = 1; i < labels.length + 3; i++) i}),
    ], landscape: true));
    return doc.save();
  }

  // --------------------------------------------------------------- dashboard

  static pw.Widget _barRow(String label, double ratio, PdfColor color, String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(children: [
        pw.SizedBox(width: 130, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9))),
        pw.Container(width: 220 * ratio.clamp(0.01, 1.0), height: 8, color: color),
        pw.SizedBox(width: 6),
        pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
      ]),
    );
  }

  static pw.Widget _h(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(t, style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
      );

  /// Prints the same widgets that are visible on the dashboard.
  static Future<Uint8List> dashboard(PdfPageFormat f, Set<String> hidden) async {
    final kit = await ReportKit.load();
    final d = await DashboardRepo.load();
    final s = d.stats;
    final body = <pw.Widget>[];

    if (!hidden.contains('kpi')) {
      body.add(_h('Key numbers'));
      body.add(kit.table(['Measure', 'Value'], [
        ['Active employees', '${s['active']}'],
        ['Terminated employees', '${s['terminated']}'],
        ['Present today', '${s['present']} of ${(s['present'] ?? 0) + (s['notYet'] ?? 0)}'],
        ['Late today', '${s['late']}'],
        [
          d.latest == null ? 'Latest payroll (net)' : 'Latest payroll (net): ${d.latest!['label']} (${d.latest!['status']})',
          d.latest == null ? '-' : _p(d.latest!['net'] as int)
        ],
        ['Loans outstanding', _p(d.loansOutstanding)],
      ], right: {1}));
    }
    if (!hidden.contains('attendance_week')) {
      body.add(_h('Attendance, last 7 days'));
      final maxV = d.week.fold<int>(0, (m, a) => a.present > m ? a.present : m);
      for (final a in d.week) {
        body.add(_barRow(DateFormat('EEE, MMM d').format(a.date),
            maxV == 0 ? 0 : a.present / maxV, PdfColors.green700,
            '${a.present} present, ${a.lateCount} late'));
      }
    }
    if (!hidden.contains('payroll_trend')) {
      body.add(_h('Payroll by period (net pay)'));
      if (d.trend.isEmpty) {
        body.add(pw.Text('No payroll yet.', style: const pw.TextStyle(fontSize: 9)));
      } else {
        final maxV = d.trend.fold<int>(0, (m, p) => (p['net'] as int) > m ? p['net'] as int : m);
        for (final p in d.trend) {
          final st = p['status'] as String;
          final color = st == 'Draft'
              ? PdfColors.amber700
              : (st == 'Computed' ? PdfColors.blue700 : PdfColors.green700);
          body.add(_barRow('${p['label']}', maxV <= 0 ? 0 : (p['net'] as int) / maxV, color,
              '${_p(p['net'] as int)}  ($st, ${p['n']} employees)'));
        }
      }
    }
    if (!hidden.contains('dept_cost')) {
      body.add(_h('Pay by department${d.latest == null ? '' : ' - ${d.latest!['label']}'}'));
      if (d.dept.isEmpty) {
        body.add(pw.Text('Compute a payroll to see this.', style: const pw.TextStyle(fontSize: 9)));
      } else {
        final maxV = d.dept.fold<int>(0, (m, r) => (r['net'] as int) > m ? r['net'] as int : m);
        for (final r in d.dept) {
          body.add(_barRow('${r['dept']} (${r['n']})', maxV <= 0 ? 0 : (r['net'] as int) / maxV,
              PdfColors.blue700, _p(r['net'] as int)));
        }
      }
    }
    if (!hidden.contains('data_safety')) {
      final raw = Settings.get('last_backup_at');
      body.add(_h('Data safety'));
      body.add(pw.Text(
          raw.isEmpty ? 'No backup yet.' : 'Last backup: ${DateFormat('MMM d, y h:mm a').format(DateTime.parse(raw))}',
          style: const pw.TextStyle(fontSize: 9)));
    }
    if (body.isEmpty) body.add(pw.Text('All dashboard widgets are hidden.'));

    final doc = kit.newDoc();
    doc.addPage(_page(kit, f, 'Dashboard summary', _printed(), body));
    return doc.save();
  }

  // ------------------------------------------------------------- 13th month

  /// Total basic pay earned in the year (Approved/Paid payrolls ending in that
  /// year) divided by 12. Confirm this matches the company's policy.
  static Future<Uint8List> thirteenthMonth(PdfPageFormat f, int year) async {
    final kit = await ReportKit.load();
    final rows = await AppDb.db.rawQuery('''
      SELECT i.emp_code, i.emp_name, COUNT(*) AS n,
             SUM(i.basic_centavos - i.absence_ded_centavos - i.late_ded_centavos) AS basic_total
      FROM payroll_items i JOIN payroll_periods p ON p.id = i.period_id
      WHERE p.status IN ('Approved', 'Paid') AND p.date_to >= ? AND p.date_to <= ?
      GROUP BY i.employee_id ORDER BY i.emp_name COLLATE NOCASE''',
        ['$year-01-01', '$year-12-31']);
    int tBasic = 0, tPay = 0;
    final data = <List<String>>[];
    for (final r in rows) {
      final b = (r['basic_total'] as int?) ?? 0;
      final pay = (b / 12).round();
      tBasic += b;
      tPay += pay;
      data.add([r['emp_code'] as String, r['emp_name'] as String, '${r['n']}', _p(b), _p(pay)]);
    }
    data.add(['', 'TOTAL', '', _p(tBasic), _p(tPay)]);
    final doc = kit.newDoc();
    doc.addPage(_page(kit, f, '13th month pay', 'Year $year  |  ${_printed()}', [
      kit.table(['ID', 'Employee', 'Payrolls', 'Basic pay earned', '13th month pay'], data, right: {2, 3, 4}),
      pw.SizedBox(height: 6),
      pw.Text(
          'Computed as total basic pay earned in $year (after absences and late, from approved or paid payrolls) divided by 12. '
          'Confirm this matches company policy.',
          style: const pw.TextStyle(fontSize: 7.5)),
    ]));
    return doc.save();
  }

  // ------------------------------------------------------------------- loans

  static Future<Uint8List> loans(PdfPageFormat f) async {
    final kit = await ReportKit.load();
    final rows = await LoansRepo.list(status: 'All');
    int tBal = 0;
    final data = <List<String>>[];
    for (final l in rows) {
      if (l['status'] == 'Active') tBal += l['balance_centavos'] as int;
      data.add([
        '${l['last_name']}, ${l['first_name']}\n${l['emp_code']}',
        l['label'] as String,
        _d.format(DateTime.parse(l['start_date'] as String)),
        _p(l['principal_centavos'] as int),
        _p(l['per_payroll_centavos'] as int),
        _p(l['paid'] as int),
        _p(l['balance_centavos'] as int),
        l['status'] as String,
      ]);
    }
    final doc = kit.newDoc();
    doc.addPage(_page(kit, f, 'Loans and cash advances', _printed(), [
      kit.table(['Employee', 'Description', 'Start', 'Total', 'Per payroll', 'Paid', 'Balance', 'Status'], data,
          right: {3, 4, 5, 6}),
      pw.SizedBox(height: 6),
      pw.Text('Outstanding balance of active loans: ${_p(tBal)}', style: const pw.TextStyle(fontSize: 9)),
    ], landscape: true));
    return doc.save();
  }

  // -------------------------------------------------------------- audit trail

  static Future<Uint8List> audit(PdfPageFormat f, DateTime from, DateTime to) async {
    final kit = await ReportKit.load();
    final rows = await AppDb.db.query('audit_log',
        where: 'at >= ? AND at <= ?',
        whereArgs: ['${PayrollCalc.key(from)}T00:00:00', '${PayrollCalc.key(to)}T23:59:59.999'],
        orderBy: 'id DESC',
        limit: 3000);
    final fmt = DateFormat('MMM d, y h:mm a');
    final doc = kit.newDoc();
    doc.addPage(_page(kit, f, 'Audit trail',
        '${_d.format(from)} to ${_d.format(to)}  |  ${_printed()}', [
      kit.table(
        ['Date / time', 'Device', 'Action', 'Record', 'Details'],
        [
          for (final r in rows)
            [
              fmt.format(DateTime.parse(r['at'] as String)),
              r['device'] as String,
              r['action'] as String,
              '${r['entity']} ${r['entity_id']}'.trim(),
              [
                if (r['old_value'] != null) 'from: ${r['old_value']}',
                if (r['new_value'] != null) 'to: ${r['new_value']}',
              ].join('  '),
            ]
        ],
        widths: const {
          0: pw.FixedColumnWidth(95),
          1: pw.FixedColumnWidth(70),
          2: pw.FixedColumnWidth(110),
          3: pw.FlexColumnWidth(1),
          4: pw.FlexColumnWidth(2),
        },
      ),
      if (rows.length >= 3000)
        pw.Text('Only the latest 3,000 entries are shown. Narrow the date range.',
            style: const pw.TextStyle(fontSize: 8)),
    ], landscape: true));
    return doc.save();
  }
}
