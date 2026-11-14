import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/employees_repo.dart';
import '../core/payroll_repo.dart';
import '../core/reports.dart';
import 'report_preview_screen.dart';
import '../theme/app_theme.dart';
import 'payroll_item_screen.dart';
import 'payroll_screen.dart' show payrollStatus;

class PayrollDetailScreen extends StatefulWidget {
  final int periodId;
  const PayrollDetailScreen({super.key, required this.periodId});
  @override
  State<PayrollDetailScreen> createState() => _PayrollDetailScreenState();
}

class _Data {
  final DbRow? period;
  final List<DbRow> items;
  _Data(this.period, this.items);
}

class _PayrollDetailScreenState extends State<PayrollDetailScreen> {
  static final _d = DateFormat('MMM d, y');
  late Future<_Data> _future = _load();

  Future<_Data> _load() async =>
      _Data(await PayrollRepo.period(widget.periodId), await PayrollRepo.items(widget.periodId));

  void _refresh() => setState(() => _future = _load());

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _confirm(String title, String body, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) _snack(done);
    } catch (e) {
      if (mounted) _snack('$e');
    }
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Data>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        final p = d?.period;
        return Scaffold(
          appBar: AppBar(title: Text(p == null ? 'Payroll' : p['label'] as String)),
          body: d == null || p == null
              ? const Center(child: CircularProgressIndicator())
              : _body(p, d.items),
        );
      },
    );
  }

  Widget _body(DbRow p, List<DbRow> items) {
    final status = p['status'] as String;
    final editable = status == 'Draft' || status == 'Computed';
    int gross = 0, net = 0, issues = 0;
    for (final i in items) {
      gross += i['gross_centavos'] as int;
      net += i['net_centavos'] as int;
      if ((i['warnings'] as String).isNotEmpty || (i['net_centavos'] as int) < 0) issues++;
    }
    final id = widget.periodId;

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusChip(payrollStatus(status), status),
              Text('${_d.format(DateTime.parse(p['date_from'] as String))} to ${_d.format(DateTime.parse(p['date_to'] as String))}'),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StatusChip(Status.info, 'Employees: ${items.length}'),
              StatusChip(Status.info, 'Gross: ${EmployeesRepo.pesos(gross)}'),
              StatusChip(Status.good, 'Net: ${EmployeesRepo.pesos(net)}'),
              if (issues > 0) StatusChip(Status.warn, 'Need review: $issues'),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (editable)
                FilledButton.icon(
                  onPressed: () => _run(() async {
                    await PayrollRepo.compute(id);
                  }, status == 'Draft' ? 'Payroll computed.' : 'Payroll recomputed.'),
                  icon: const Icon(Icons.calculate),
                  label: Text(status == 'Draft' ? 'Compute payroll' : 'Recompute'),
                ),
              if (status == 'Computed' && items.isNotEmpty)
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await _confirm(
                        'Approve payroll?',
                        issues > 0
                            ? '$issues employee(s) still need review (warnings or negative pay). Approving locks all amounts.'
                            : 'Approving locks all amounts. You can reopen it later if needed.',
                        'Approve');
                    if (ok) _run(() => PayrollRepo.approve(id), 'Payroll approved.');
                  },
                  icon: const Icon(Icons.verified),
                  label: const Text('Approve'),
                ),
              if (status == 'Approved') ...[
                FilledButton.icon(
                  onPressed: () async {
                    if (await _confirm('Mark as paid?', 'Use this once the employees have been paid.', 'Mark paid')) {
                      _run(() => PayrollRepo.markPaid(id), 'Marked as paid.');
                    }
                  },
                  icon: const Icon(Icons.payments),
                  label: const Text('Mark as paid'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (await _confirm('Reopen payroll?', 'This unlocks the amounts for editing. The change is recorded in the audit trail.', 'Reopen')) {
                      _run(() => PayrollRepo.reopen(id), 'Payroll reopened.');
                    }
                  },
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Reopen'),
                ),
              ],
              if (items.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () => openReport(context,
                      title: 'Payroll register',
                      fileName: 'payroll_register.pdf',
                      build: (f) => Reports.payrollRegister(f, id)),
                  icon: const Icon(Icons.print),
                  label: const Text('Payroll register'),
                ),
                OutlinedButton.icon(
                  onPressed: () => openReport(context,
                      title: 'Payslips',
                      fileName: 'payslips.pdf',
                      build: (f) => Reports.payslips(f, id)),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Print payslips'),
                ),
              ],
              if (editable)
                OutlinedButton.icon(
                  onPressed: () async {
                    if (await _confirm('Delete this payroll?', 'All computed amounts and adjustments for this period are removed.', 'Delete')) {
                      try {
                        await PayrollRepo.deletePeriod(id);
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        if (mounted) _snack('$e');
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      if (items.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Nothing computed yet. Press "Compute payroll".')),
        ),
      for (final i in items)
        Card(
          child: ListTile(
            title: Text(i['emp_name'] as String),
            subtitle: Text(
                '${i['emp_code']}  |  ${i['pay_type']} ${EmployeesRepo.pesos(i['rate_centavos'] as int)}\n'
                'Worked ${i['days_worked']} d  |  Absent ${i['absent_days']} d  |  OT ${i['overtime_min']} min'),
            isThreeLine: true,
            leading: ((i['warnings'] as String).isNotEmpty || (i['net_centavos'] as int) < 0)
                ? Icon(Icons.warning_amber_rounded, color: statusColor(context, Status.warn))
                : null,
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(EmployeesRepo.pesos(i['net_centavos'] as int),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Text('net pay', style: TextStyle(fontSize: 11)),
            ]),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PayrollItemScreen(itemId: i['id'] as int, editable: editable)));
              if (mounted) _refresh();
            },
          ),
        ),
    ]);
  }
}
