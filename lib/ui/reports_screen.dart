import 'package:flutter/material.dart';
import '../core/payroll_repo.dart';
import '../core/reports.dart';
import 'report_preview_screen.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  Future<String?> _choose(BuildContext c, String title, List<String> options) =>
      showDialog<String>(
        context: c,
        builder: (d) => SimpleDialog(title: Text(title), children: [
          for (final o in options)
            SimpleDialogOption(onPressed: () => Navigator.pop(d, o), child: Text(o)),
        ]),
      );

  Future<int?> _period(BuildContext c) async {
    final ps = await PayrollRepo.periods();
    if (!c.mounted) return null;
    if (ps.isEmpty) {
      ScaffoldMessenger.of(c).showSnackBar(
          const SnackBar(content: Text('There is no payroll yet. Create one under Payroll.')));
      return null;
    }
    return showDialog<int>(
      context: c,
      builder: (d) => SimpleDialog(title: const Text('Choose a payroll period'), children: [
        for (final p in ps)
          SimpleDialogOption(
              onPressed: () => Navigator.pop(d, p['id'] as int),
              child: Text('${p['label']}  (${p['status']})')),
      ]),
    );
  }

  Future<DateTimeRange?> _range(BuildContext c) {
    final now = DateTime.now();
    return showDateRangePicker(
      context: c,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
          start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 0)),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle,
      Future<void> Function() onTap) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Reports and printing', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Every report opens as a preview where you can print, save as PDF, '
              'share, and choose A4, Letter or Legal paper.'),
          const SizedBox(height: 12),
          _tile(context, Icons.receipt_long, 'Payslips',
              'One payslip per page, for everyone or one employee', () async {
            final id = await _period(context);
            if (id == null || !context.mounted) return;
            final items = await PayrollRepo.items(id);
            if (!context.mounted) return;
            final names = {for (final i in items) '${i['emp_name']} (${i['emp_code']})': i['id'] as int};
            final pick = await _choose(context, 'Which employees?', ['All employees', ...names.keys]);
            if (pick == null || !context.mounted) return;
            openReport(context,
                title: 'Payslips',
                fileName: 'payslips.pdf',
                build: (f) => Reports.payslips(f, id, itemId: names[pick]));
          }),
          _tile(context, Icons.table_chart, 'Payroll register',
              'All employees for one payroll period, with totals', () async {
            final id = await _period(context);
            if (id == null || !context.mounted) return;
            openReport(context,
                title: 'Payroll register',
                fileName: 'payroll_register.pdf',
                build: (f) => Reports.payrollRegister(f, id));
          }),
          _tile(context, Icons.account_balance, 'Government & company deductions',
              'SSS, PhilHealth, Pag-IBIG, tax and others per employee', () async {
            final id = await _period(context);
            if (id == null || !context.mounted) return;
            openReport(context,
                title: 'Deductions report',
                fileName: 'deductions.pdf',
                build: (f) => Reports.deductions(f, id));
          }),
          _tile(context, Icons.access_time, 'Attendance report',
              'Days present, absences, late, undertime, overtime', () async {
            final r = await _range(context);
            if (r == null || !context.mounted) return;
            openReport(context,
                title: 'Attendance report',
                fileName: 'attendance.pdf',
                build: (f) => Reports.attendance(f, r.start, r.end));
          }),
          _tile(context, Icons.people_alt, 'Employee masterlist',
              'Active, terminated or all employees', () async {
            final s = await _choose(context, 'Which employees?', ['Active', 'Terminated', 'All']);
            if (s == null || !context.mounted) return;
            openReport(context,
                title: 'Employee masterlist',
                fileName: 'masterlist.pdf',
                build: (f) => Reports.masterlist(f, s));
          }),
          _tile(context, Icons.card_giftcard, '13th month pay',
              'Total basic pay earned in a year divided by 12', () async {
            final y = DateTime.now().year;
            final pick = await _choose(context, 'Which year?', ['$y', '${y - 1}', '${y - 2}']);
            if (pick == null || !context.mounted) return;
            openReport(context,
                title: '13th month pay $pick',
                fileName: '13th_month_$pick.pdf',
                build: (f) => Reports.thirteenthMonth(f, int.parse(pick)));
          }),
          _tile(context, Icons.request_quote, 'Loans and cash advances',
              'Balances and deductions per employee', () async {
            openReport(context,
                title: 'Loans and cash advances',
                fileName: 'loans.pdf',
                build: (f) => Reports.loans(f));
          }),
          _tile(context, Icons.fact_check, 'Audit trail',
              'Who changed what and when', () async {
            final r = await _range(context);
            if (r == null || !context.mounted) return;
            openReport(context,
                title: 'Audit trail',
                fileName: 'audit_trail.pdf',
                build: (f) => Reports.audit(f, r.start, r.end));
          }),
          const SizedBox(height: 8),
          const Text('Coming later: dashboard summary report and rental reports.'),
        ]),
      ),
    );
  }
}
