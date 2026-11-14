import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/employees_repo.dart';
import '../core/loans_repo.dart';
import '../theme/app_theme.dart';

/// Loans and cash advances, deducted automatically in payroll.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});
  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  String _status = 'Active';
  static final _df = DateFormat('MMM d, y');

  Future<void> _add() async {
    final emps = await EmployeesRepo.list(status: 'Active');
    if (!mounted) return;
    int? empId;
    final label = TextEditingController(text: 'Cash advance');
    final amount = TextEditingController();
    final per = TextEditingController();
    final note = TextEditingController();
    DateTime start = DateTime.now();
    String? err;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('New loan / cash advance'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                  initialValue: empId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Employee'),
                  items: [
                    for (final e in emps)
                      DropdownMenuItem(
                          value: e['id'] as int,
                          child: Text('${EmployeesRepo.fullName(e)}  (${e['emp_code']})',
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setD(() => empId = v),
                ),
                TextField(controller: label, decoration: const InputDecoration(labelText: 'Description')),
                TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Total amount', prefixText: '\u20b1 ')),
                TextField(
                    controller: per,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Deduction per payroll', prefixText: '\u20b1 ')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start deducting from'),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: c, initialDate: start, firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (d != null) setD(() => start = d);
                    },
                    child: Text(_df.format(start)),
                  ),
                ),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(err!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final a = double.tryParse(amount.text.replaceAll(',', '').trim());
                final p = double.tryParse(per.text.replaceAll(',', '').trim());
                if (empId == null || label.text.trim().isEmpty || a == null || a <= 0 || p == null || p <= 0) {
                  setD(() => err = 'Choose an employee and enter a description and amounts above 0.');
                  return;
                }
                await LoansRepo.add(
                  empId: empId!,
                  label: label.text.trim(),
                  principal: (a * 100).round(),
                  perPayroll: (p * 100).round(),
                  startDate: DateFormat('yyyy-MM-dd').format(start),
                  note: note.text.trim(),
                );
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _open(DbRow l) async {
    final pays = await LoansRepo.payments(l['id'] as int);
    if (!mounted) return;
    final per = TextEditingController(text: ((l['per_payroll_centavos'] as int) / 100).toStringAsFixed(2));
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${l['label']} - ${l['last_name']}, ${l['first_name']}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Total ${EmployeesRepo.pesos(l['principal_centavos'] as int)}  |  '
                  'Paid ${EmployeesRepo.pesos(l['paid'] as int)}  |  '
                  'Balance ${EmployeesRepo.pesos(l['balance_centavos'] as int)}'),
              const SizedBox(height: 8),
              if (l['status'] == 'Active')
                TextField(
                    controller: per,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Deduction per payroll', prefixText: '\u20b1 ')),
              const SizedBox(height: 12),
              Text('Payments', style: Theme.of(c).textTheme.titleSmall),
              if (pays.isEmpty) const Text('None yet. Balances reduce when a payroll is approved.'),
              for (final p in pays)
                Text('${_df.format(DateTime.parse(p['paid_on'] as String))}   ${EmployeesRepo.pesos(p['amount_centavos'] as int)}'),
            ]),
          ),
        ),
        actions: [
          if (l['status'] == 'Active')
            TextButton(
              onPressed: () async {
                await LoansRepo.cancel(l['id'] as int);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Stop deductions'),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
          if (l['status'] == 'Active')
            FilledButton(
              onPressed: () async {
                final n = double.tryParse(per.text.replaceAll(',', '').trim());
                if (n != null && n > 0) {
                  await LoansRepo.setPerPayroll(l['id'] as int, (n * 100).round());
                  if (c.mounted) Navigator.pop(c);
                }
              },
              child: const Text('Save'),
            ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const StatusChip(Status.warn, 'Loan rules are subject to update per the company\'s business rules'),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Active', label: Text('Active')),
                ButtonSegment(value: 'All', label: Text('All')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('New loan / advance')),
          ]),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<DbRow>>(
          future: LoansRepo.list(status: _status),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return const Center(child: Text('No loans.'));
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              for (final l in rows)
                Card(
                  child: ListTile(
                    title: Text('${l['last_name']}, ${l['first_name']}  -  ${l['label']}'),
                    subtitle: Text('${EmployeesRepo.pesos(l['per_payroll_centavos'] as int)} per payroll  |  '
                        'Balance ${EmployeesRepo.pesos(l['balance_centavos'] as int)} of ${EmployeesRepo.pesos(l['principal_centavos'] as int)}'),
                    trailing: StatusChip(
                        l['status'] == 'Active'
                            ? Status.info
                            : (l['status'] == 'Paid off' ? Status.good : Status.inactive),
                        l['status'] as String),
                    onTap: () => _open(l),
                  ),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}
