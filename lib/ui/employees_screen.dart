import 'package:flutter/material.dart';
import '../core/employees_repo.dart';
import '../theme/app_theme.dart';
import 'employee_form.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  String _q = '';
  String _status = 'Active';

  Future<void> _open([int? id]) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => EmployeeForm(id: id)));
    if (changed == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, ID, position or department',
                border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Active', label: Text('Active')),
                ButtonSegment(value: 'Terminated', label: Text('Terminated')),
                ButtonSegment(value: 'All', label: Text('All')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            FilledButton.icon(
              onPressed: () => _open(),
              icon: const Icon(Icons.person_add),
              label: const Text('Add employee'),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<DbRow>>(
          future: EmployeesRepo.list(q: _q, status: _status),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data!;
            if (rows.isEmpty) {
              return const Center(child: Text('No employees found.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                final active = r['status'] == 'Active';
                final detail = [
                  r['emp_code'],
                  if ((r['position'] as String).isNotEmpty) r['position'],
                  if ((r['department'] as String).isNotEmpty) r['department'],
                ].join('  |  ');
                final pay =
                    '${EmployeesRepo.pesos(r['rate_centavos'] as int)} / ${EmployeesRepo.payUnit[r['pay_type']]}';
                return ListTile(
                  leading: CircleAvatar(
                      child: Text((r['first_name'] as String)[0].toUpperCase())),
                  title: Text(EmployeesRepo.fullName(r)),
                  subtitle: Text('$detail\n$pay'),
                  isThreeLine: true,
                  trailing: StatusChip(active ? Status.good : Status.inactive,
                      active ? 'Active' : 'Terminated'),
                  onTap: () => _open(r['id'] as int),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
