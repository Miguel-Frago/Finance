import 'package:flutter/material.dart';
import '../core/employees_repo.dart';
import '../core/payroll_repo.dart';
import '../core/settings.dart';

/// Company payroll rules. Everything here is editable because the rules differ
/// per company. Nothing is deducted until a percentage above 0 is entered.
class PayrollRulesScreen extends StatefulWidget {
  const PayrollRulesScreen({super.key});
  @override
  State<PayrollRulesScreen> createState() => _PayrollRulesScreenState();
}

class _PayrollRulesScreenState extends State<PayrollRulesScreen> {
  late final _ot = TextEditingController(text: Settings.get('ot_pct', '125'));
  late final _factor = TextEditingController(text: Settings.get('days_factor', '261'));
  late final _holReg = TextEditingController(text: Settings.get('hol_reg_pct', '200'));
  late final _holSpc = TextEditingController(text: Settings.get('hol_spc_pct', '130'));
  late final _rest = TextEditingController(text: Settings.get('restday_pct', '130'));
  late final _nd = TextEditingController(text: Settings.get('nd_pct', '10'));
  late final _leave = TextEditingController(text: Settings.get('leave_credits', '5'));
  late bool _holUnworked = Settings.get('hol_reg_unworked', '1') == '1';
  late final Set<int> _days = Settings.get('work_days', '1,2,3,4,5')
      .split(',')
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .toSet();
  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveGeneral() async {
    final ot = int.tryParse(_ot.text.trim());
    final f = int.tryParse(_factor.text.trim());
    if (ot == null || ot < 100 || ot > 500 || f == null || f < 200 || f > 366 || _days.isEmpty) {
      _snack('Check the values: overtime 100-500%, days per year 200-366, at least one working day.');
      return;
    }
    final hr = int.tryParse(_holReg.text.trim());
    final hs = int.tryParse(_holSpc.text.trim());
    final rd = int.tryParse(_rest.text.trim());
    final nd = int.tryParse(_nd.text.trim());
    final lv = int.tryParse(_leave.text.trim());
    if (hr == null || hr < 100 || hr > 400 || hs == null || hs < 100 || hs > 400 ||
        rd == null || rd < 100 || rd > 400 || nd == null || nd < 0 || nd > 100 ||
        lv == null || lv < 0 || lv > 60) {
      _snack('Check the holiday, rest day, night differential and leave values.');
      return;
    }
    await Settings.set('hol_reg_pct', '$hr');
    await Settings.set('hol_spc_pct', '$hs');
    await Settings.set('restday_pct', '$rd');
    await Settings.set('nd_pct', '$nd');
    await Settings.set('leave_credits', '$lv');
    await Settings.set('hol_reg_unworked', _holUnworked ? '1' : '0');
    await Settings.set('ot_pct', '$ot');
    await Settings.set('days_factor', '$f');
    await Settings.set('work_days', (_days.toList()..sort()).join(','));
    if (mounted) _snack('Payroll rules saved. Recompute open payrolls to apply them.');
  }

  Future<void> _editRule([DbRow? r]) async {
    final name = TextEditingController(text: (r?['name'] as String?) ?? '');
    final pct = TextEditingController(
        text: r == null ? '' : ((r['percent_bp'] as int) / 100).toString());
    final cap = TextEditingController(
        text: r?['cap_centavos'] == null
            ? ''
            : ((r!['cap_centavos'] as int) / 100).toStringAsFixed(2));
    String base = (r?['base'] as String?) ?? 'gross';
    bool enabled = r == null || r['enabled'] == 1;
    String? err;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(r == null ? 'Add deduction' : 'Edit ${r['name']}'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                TextField(
                    controller: pct,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Employee share (%)', suffixText: '%')),
                DropdownButtonFormField<String>(
                  initialValue: base,
                  decoration: const InputDecoration(labelText: 'Percent of'),
                  items: const [
                    DropdownMenuItem(value: 'gross', child: Text('Gross pay')),
                    DropdownMenuItem(
                        value: 'basic', child: Text('Basic pay (after absences and late)')),
                  ],
                  onChanged: (v) => setD(() => base = v ?? base),
                ),
                TextField(
                    controller: cap,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Maximum per payroll (optional)', prefixText: '\u20b1 ')),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Apply to payroll'),
                    value: enabled,
                    onChanged: (v) => setD(() => enabled = v)),
                if (err != null)
                  Text(err!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
              ]),
            ),
          ),
          actions: [
            if (r != null)
              TextButton(
                onPressed: () async {
                  await PayrollRepo.deleteRule(r['id'] as int, r['name'] as String);
                  if (c.mounted) Navigator.pop(c);
                },
                child: const Text('Delete'),
              ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final p = double.tryParse(pct.text.trim());
                final capN = cap.text.trim().isEmpty ? null : double.tryParse(cap.text.replaceAll(',', '').trim());
                if (name.text.trim().isEmpty || p == null || p < 0 || p > 100) {
                  setD(() => err = 'Enter a name and a percent from 0 to 100.');
                  return;
                }
                if (cap.text.trim().isNotEmpty && (capN == null || capN <= 0)) {
                  setD(() => err = 'The maximum must be an amount above 0, or empty.');
                  return;
                }
                await PayrollRepo.saveRule({
                  'name': name.text.trim(),
                  'base': base,
                  'percent_bp': (p * 100).round(),
                  'cap_centavos': capN == null ? null : (capN * 100).round(),
                  'enabled': enabled ? 1 : 0,
                }, id: r?['id'] as int?);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll rules')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Overtime and working days',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _ot,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Overtime pay (% of hourly rate)',
                          helperText: '125 means 125% of the normal hourly rate.')),
                  TextField(
                      controller: _factor,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Working days per year (for the daily rate)',
                          helperText:
                              'Used for monthly/annual rates and deductions. 261 for Mon-Fri, 313 for Mon-Sat.')),
                  const SizedBox(height: 12),
                  const Text('Working days of the week'),
                  Wrap(spacing: 8, children: [
                    for (var i = 0; i < 7; i++)
                      FilterChip(
                        label: Text(_names[i]),
                        selected: _days.contains(i + 1),
                        onSelected: (v) => setState(() {
                          v ? _days.add(i + 1) : _days.remove(i + 1);
                        }),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _saveGeneral, child: const Text('Save')),
                  const SizedBox(height: 8),
                  const Text('Press Save once to apply the values on this page. Recompute open payrolls to use them.'),
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Holidays, rest day, night work and leave',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _holReg,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Regular holiday, worked (% of daily rate)',
                          helperText: '200 means double pay.')),
                  TextField(
                      controller: _holSpc,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Special non-working day, worked (%)',
                          helperText: '130 means 30% extra.')),
                  TextField(
                      controller: _rest,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Rest day, worked (%)', helperText: '130 means 30% extra.')),
                  TextField(
                      controller: _nd,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Night differential, 10pm to 6am (% extra)',
                          helperText: '10 means 10% of the hourly rate for night minutes.')),
                  TextField(
                      controller: _leave,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Paid leave days per year',
                          helperText: 'Used only to show leave balances.')),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pay Daily-rate staff for an unworked regular holiday'),
                    value: _holUnworked,
                    onChanged: (v) => setState(() => _holUnworked = v),
                  ),
                  const SizedBox(height: 4),
                  FilledButton(onPressed: _saveGeneral, child: const Text('Save')),
                  const SizedBox(height: 8),
                  const Text('These are starting values. Update them to your company\'s business rules.'),
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Government and company deductions',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(
                      'Enter the employee share used by your company (the rates change over time). '
                      'Nothing is deducted until the percent is above 0. A deduction applies to every payroll.'),
                  const SizedBox(height: 8),
                  FutureBuilder<List<DbRow>>(
                    future: PayrollRepo.rules(),
                    builder: (context, snap) {
                      final rows = snap.data ?? [];
                      return Column(children: [
                        for (final r in rows)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(r['name'] as String),
                            subtitle: Text(
                                '${((r['percent_bp'] as int) / 100).toStringAsFixed(2)}% of ${r['base']} pay'
                                '${r['cap_centavos'] == null ? '' : ', max ${EmployeesRepo.pesos(r['cap_centavos'] as int)}'}'
                                '${r['enabled'] == 1 ? '' : '  (off)'}'),
                            trailing: const Icon(Icons.edit),
                            onTap: () => _editRule(r),
                          ),
                      ]);
                    },
                  ),
                  OutlinedButton.icon(
                      onPressed: () => _editRule(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add deduction')),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
