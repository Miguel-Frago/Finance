import 'package:flutter/material.dart';
import '../core/employees_repo.dart';
import '../core/payroll_repo.dart';
import '../core/reports.dart';
import 'report_preview_screen.dart';
import '../theme/app_theme.dart';

/// One employee's pay breakdown. Manual additions/deductions can be added or
/// removed while the payroll is not approved.
class PayrollItemScreen extends StatefulWidget {
  final int itemId;
  final bool editable;
  const PayrollItemScreen({super.key, required this.itemId, required this.editable});
  @override
  State<PayrollItemScreen> createState() => _PayrollItemScreenState();
}

class _ItemData {
  final DbRow? item;
  final List<DbRow> lines;
  _ItemData(this.item, this.lines);
}

class _PayrollItemScreenState extends State<PayrollItemScreen> {
  late Future<_ItemData> _future = _load();

  Future<_ItemData> _load() async =>
      _ItemData(await PayrollRepo.item(widget.itemId), await PayrollRepo.lines(widget.itemId));

  void _refresh() => setState(() => _future = _load());

  Widget _row(String label, int centavos,
      {bool bold = false, bool negative = false, Widget? trailing}) {
    final shown = negative ? -centavos : centavos;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
        Text(EmployeesRepo.pesos(shown),
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        if (trailing != null) trailing,
      ]),
    );
  }

  Future<void> _add(bool addition) async {
    final label = TextEditingController();
    final amount = TextEditingController();
    String? err;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(addition ? 'Add to pay' : 'Add deduction'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: label,
                  decoration: InputDecoration(
                      labelText: 'Description',
                      hintText: addition ? 'e.g. Allowance, bonus' : 'e.g. Cash advance, loan')),
              TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '\u20b1 ')),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final n = double.tryParse(amount.text.replaceAll(',', '').trim());
                if (label.text.trim().isEmpty || n == null || n <= 0) {
                  setD(() => err = 'Enter a description and an amount above 0.');
                  return;
                }
                try {
                  await PayrollRepo.addAdjustment(widget.itemId,
                      addition: addition, label: label.text.trim(), centavos: (n * 100).round());
                  if (c.mounted) Navigator.pop(c);
                } catch (e) {
                  setD(() => err = '$e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ItemData>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        final it = d?.item;
        return Scaffold(
          appBar: AppBar(
            title: Text(it == null ? 'Pay breakdown' : it['emp_name'] as String),
            actions: [
              if (it != null)
                IconButton(
                  tooltip: 'Print payslip',
                  icon: const Icon(Icons.print),
                  onPressed: () => openReport(context,
                      title: 'Payslip',
                      fileName: 'payslip_${it['emp_code']}.pdf',
                      build: (f) => Reports.payslips(f, it['period_id'] as int,
                          itemId: widget.itemId)),
                ),
            ],
          ),
          body: it == null
              ? const Center(child: CircularProgressIndicator())
              : _body(it, d!.lines),
        );
      },
    );
  }

  Widget _body(DbRow it, List<DbRow> lines) {
    final adds = lines.where((l) => l['kind'] == 'addition' || l['kind'] == 'earning').toList();
    final stat = lines.where((l) => l['kind'] == 'statutory' || l['kind'] == 'loan').toList();
    final deds = lines.where((l) => l['kind'] == 'deduction').toList();
    final warnings = (it['warnings'] as String).split('\n').where((w) => w.isNotEmpty).toList();

    Widget lineRow(DbRow l, {bool negative = false}) => _row(
          l['label'] as String,
          l['amount_centavos'] as int,
          negative: negative,
          trailing: (l['manual'] == 1 && widget.editable)
              ? IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    try {
                      await PayrollRepo.deleteAdjustment(l['id'] as int);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                    if (mounted) _refresh();
                  })
              : null,
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('${it['emp_code']}  |  ${it['position']}  |  ${it['department']}'),
          Text('${it['pay_type']} rate ${EmployeesRepo.pesos(it['rate_centavos'] as int)}'),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final w in warnings) StatusChip(Status.warn, w),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Earnings', style: Theme.of(context).textTheme.titleMedium),
                _row('Basic pay', it['basic_centavos'] as int),
                _row('Absences (${it['absent_days']} day/s)', it['absence_ded_centavos'] as int,
                    negative: true),
                _row('Late / undertime (${it['shortfall_min']} min)',
                    it['late_ded_centavos'] as int,
                    negative: true),
                _row('Overtime (${it['overtime_min']} min)', it['overtime_centavos'] as int),
                for (final l in adds) lineRow(l),
                if (widget.editable)
                  TextButton.icon(
                      onPressed: () => _add(true),
                      icon: const Icon(Icons.add),
                      label: const Text('Add to pay')),
                const Divider(),
                _row('Gross pay', it['gross_centavos'] as int, bold: true),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Deductions', style: Theme.of(context).textTheme.titleMedium),
                if (stat.isEmpty && deds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('None. Set deduction rules under Payroll rules.'),
                  ),
                for (final l in stat) lineRow(l, negative: true),
                for (final l in deds) lineRow(l, negative: true),
                if (widget.editable)
                  TextButton.icon(
                      onPressed: () => _add(false),
                      icon: const Icon(Icons.add),
                      label: const Text('Add deduction')),
              ]),
            ),
          ),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _row('NET PAY', it['net_centavos'] as int, bold: true),
            ),
          ),
        ]),
      ),
    );
  }
}
