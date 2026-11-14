import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/employees_repo.dart';
import '../core/time_off_repo.dart';
import '../theme/app_theme.dart';

/// Two tabs: the company holiday calendar and employee leave.
class HolidaysLeaveScreen extends StatelessWidget {
  const HolidaysLeaveScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Holidays'), Tab(text: 'Leave')]),
        Expanded(child: TabBarView(children: [_HolidaysTab(), _LeaveTab()])),
      ]),
    );
  }
}

final _df = DateFormat('EEE, MMM d, y');

// ------------------------------------------------------------------ holidays

class _HolidaysTab extends StatefulWidget {
  const _HolidaysTab();
  @override
  State<_HolidaysTab> createState() => _HolidaysTabState();
}

class _HolidaysTabState extends State<_HolidaysTab> {
  int _year = DateTime.now().year;

  Future<void> _add() async {
    DateTime date = DateTime(_year, DateTime.now().month, DateTime.now().day);
    final name = TextEditingController();
    String type = 'Regular';
    String? err;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Add holiday'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                trailing: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: c, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setD(() => date = d);
                  },
                  child: Text(_df.format(date)),
                ),
              ),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'Regular', child: Text('Regular holiday')),
                  DropdownMenuItem(value: 'Special', child: Text('Special non-working day')),
                ],
                onChanged: (v) => setD(() => type = v ?? type),
              ),
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
                if (name.text.trim().isEmpty) {
                  setD(() => err = 'Enter the holiday name.');
                  return;
                }
                final e = await HolidaysRepo.add(date, name.text.trim(), type);
                if (e != null) {
                  setD(() => err = e);
                } else if (c.mounted) {
                  Navigator.pop(c);
                }
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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
          Text('$_year', style: Theme.of(context).textTheme.titleLarge),
          IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right)),
          FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add holiday')),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Add each year\'s holidays yourself, because some dates change every year. '
              'Holiday pay percentages are under Payroll rules.'),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<DbRow>>(
          future: HolidaysRepo.forYear(_year),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return Center(child: Text('No holidays added for $_year.'));
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final r in rows)
                Card(
                  child: ListTile(
                    title: Text(r['name'] as String),
                    subtitle: Text(_df.format(DateTime.parse(r['hdate'] as String))),
                    trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      StatusChip(r['type'] == 'Regular' ? Status.info : Status.warn,
                          r['type'] == 'Regular' ? 'Regular' : 'Special'),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await HolidaysRepo.delete(r['id'] as int);
                          if (mounted) setState(() {});
                        },
                      ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}

// --------------------------------------------------------------------- leave

class _LeaveTab extends StatefulWidget {
  const _LeaveTab();
  @override
  State<_LeaveTab> createState() => _LeaveTabState();
}

class _LeaveTabState extends State<_LeaveTab> {
  int? _empId;
  int _year = DateTime.now().year;
  late final Future<List<DbRow>> _emps = EmployeesRepo.list(status: 'Active');

  Future<void> _add() async {
    DateTime date = DateTime.now();
    String type = 'Vacation';
    bool paid = true;
    final note = TextEditingController();
    String? err;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Add leave'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                trailing: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: c, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setD(() => date = d);
                  },
                  child: Text(_df.format(date)),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: LeaveRepo.types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setD(() => type = v ?? type),
              ),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Paid leave'),
                  value: paid,
                  onChanged: (v) => setD(() => paid = v)),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
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
                final e = await LeaveRepo.add(_empId!, date, type, paid, note.text.trim());
                if (e != null) {
                  setD(() => err = e);
                } else if (c.mounted) {
                  Navigator.pop(c);
                }
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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const StatusChip(Status.warn, 'Leave rules are subject to update per the company\'s business rules'),
          const SizedBox(height: 12),
          FutureBuilder<List<DbRow>>(
            future: _emps,
            builder: (context, snap) {
              final emps = snap.data ?? [];
              return DropdownButtonFormField<int>(
                initialValue: _empId,
                decoration: const InputDecoration(labelText: 'Employee', border: OutlineInputBorder()),
                items: [
                  for (final e in emps)
                    DropdownMenuItem(
                        value: e['id'] as int,
                        child: Text('${EmployeesRepo.fullName(e)}  (${e['emp_code']})')),
                ],
                onChanged: (v) => setState(() => _empId = v),
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
            Text('$_year', style: Theme.of(context).textTheme.titleLarge),
            IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right)),
            FilledButton.icon(
                onPressed: _empId == null ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('Add leave')),
          ]),
        ]),
      ),
      Expanded(
        child: _empId == null
            ? const Center(child: Text('Choose an employee to see and add leave.'))
            : FutureBuilder<List<Object>>(
                future: Future.wait<Object>([
                  LeaveRepo.forEmployee(_empId!, _year),
                  LeaveRepo.paidUsed(_empId!, _year),
                ]),
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final rows = snap.data![0] as List<DbRow>;
                  final used = snap.data![1] as int;
                  final credits = LeaveRepo.creditsPerYear();
                  return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                    StatusChip(used > credits ? Status.bad : Status.info,
                        'Paid leave used: $used of $credits days (set under Payroll rules)'),
                    const SizedBox(height: 8),
                    if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No leave recorded.')),
                    for (final r in rows)
                      Card(
                        child: ListTile(
                          title: Text(_df.format(DateTime.parse(r['leave_date'] as String))),
                          subtitle: Text('${r['type']}${(r['note'] as String).isEmpty ? '' : '  |  ${r['note']}'}'),
                          trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            StatusChip(r['paid'] == 1 ? Status.good : Status.warn,
                                r['paid'] == 1 ? 'Paid' : 'Unpaid'),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await LeaveRepo.delete(r['id'] as int);
                                if (mounted) setState(() {});
                              },
                            ),
                          ]),
                        ),
                      ),
                  ]);
                },
              ),
      ),
    ]);
  }
}
