import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/employees_repo.dart';
import '../core/payroll_repo.dart';
import '../theme/app_theme.dart';
import 'payroll_detail_screen.dart';
import 'payroll_rules_screen.dart';

Status payrollStatus(String s) => switch (s) {
      'Draft' => Status.warn,
      'Computed' => Status.info,
      'Approved' => Status.good,
      'Paid' => Status.good,
      _ => Status.inactive,
    };

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  static final _d = DateFormat('MMM d, y');
  static final _short = DateFormat('MMM d');

  Future<void> _newPeriod() async {
    final now = DateTime.now();
    DateTime from = DateTime(now.year, now.month, 1);
    DateTime to = DateTime(now.year, now.month + 1, 0);
    final label = TextEditingController();
    String? err;
    String autoLabel() => '${_short.format(from)} - ${_d.format(to)}';

    final created = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('New payroll period'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('From'),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final x = await showDatePicker(
                          context: c, initialDate: from, firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (x != null) setD(() => from = x);
                    },
                    child: Text(_d.format(from)),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('To'),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final x = await showDatePicker(
                          context: c, initialDate: to, firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (x != null) setD(() => to = x);
                    },
                    child: Text(_d.format(to)),
                  ),
                ),
                TextField(
                    controller: label,
                    decoration: InputDecoration(
                        labelText: 'Label (optional)', hintText: autoLabel())),
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
                if (to.isBefore(from)) {
                  setD(() => err = 'The end date must not be before the start date.');
                  return;
                }
                final f = PayrollRepoDates.key(from), t = PayrollRepoDates.key(to);
                final over = await PayrollRepo.overlapping(f, t);
                if (over.isNotEmpty && c.mounted) {
                  final go = await showDialog<bool>(
                    context: c,
                    builder: (c2) => AlertDialog(
                      title: const Text('Overlapping payroll'),
                      content: Text(
                          'This overlaps with "${over.first['label']}". Employees could be paid twice for the same days. Create it anyway?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(c2, true), child: const Text('Create anyway')),
                      ],
                    ),
                  );
                  if (go != true) return;
                }
                await PayrollRepo.createPeriod(
                    label.text.trim().isEmpty ? autoLabel() : label.text.trim(), from, to);
                if (c.mounted) Navigator.pop(c, true);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (created == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 12, runSpacing: 8, children: [
          FilledButton.icon(
              onPressed: _newPeriod,
              icon: const Icon(Icons.add),
              label: const Text('New payroll period')),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const PayrollRulesScreen())),
            icon: const Icon(Icons.rule),
            label: const Text('Payroll rules'),
          ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<DbRow>>(
          future: PayrollRepo.periods(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No payroll yet. Set your rules, then create a payroll period.',
                    textAlign: TextAlign.center),
              ));
            }
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              for (final r in rows)
                Card(
                  child: ListTile(
                    title: Text(r['label'] as String),
                    subtitle: Text(
                        '${_d.format(DateTime.parse(r['date_from'] as String))} to ${_d.format(DateTime.parse(r['date_to'] as String))}\n'
                        '${r['n']} employees  |  Net ${EmployeesRepo.pesos(r['net'] as int)}'),
                    isThreeLine: true,
                    trailing: StatusChip(payrollStatus(r['status'] as String), r['status'] as String),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PayrollDetailScreen(periodId: r['id'] as int)));
                      if (mounted) setState(() {});
                    },
                  ),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}

/// Small helper so this file does not need the whole calc import.
class PayrollRepoDates {
  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
