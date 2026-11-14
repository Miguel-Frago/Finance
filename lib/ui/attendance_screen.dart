import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/attendance_calc.dart';
import '../core/attendance_repo.dart';
import '../core/employees_repo.dart';
import '../theme/app_theme.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _date = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);
  String _q = '';

  String get _key => AttendanceRepo.dateKey(_date);
  bool get _isToday => _key == AttendanceRepo.dateKey(DateTime.now());
  bool get _isFuture => _date.isAfter(DateTime.now());

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _shift(int days) => setState(() => _date = _date.add(Duration(days: days)));

  int _nowMin() {
    final n = TimeOfDay.now();
    return n.hour * 60 + n.minute;
  }

  Future<void> _punch(DbRow r, {required bool out}) async {
    final now = _nowMin();
    try {
      if (!out) {
        await AttendanceRepo.save(
          employeeId: r['id'] as int,
          empCode: r['emp_code'] as String,
          date: _key,
          timeIn: now,
          method: 'button',
        );
      } else {
        final tin = parseHm(r['time_in'] as String);
        if (now <= tin) {
          _snack('Time out must be later than time in.');
          return;
        }
        await AttendanceRepo.save(
          employeeId: r['id'] as int,
          empCode: r['emp_code'] as String,
          date: _key,
          timeIn: tin,
          timeOut: now,
          method: (r['method'] as String?) ?? 'button',
          note: (r['note'] as String?) ?? '',
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  Future<void> _edit(DbRow r) async {
    int? tin = r['time_in'] == null ? null : parseHm(r['time_in'] as String);
    int? tout = r['time_out'] == null ? null : parseHm(r['time_out'] as String);
    final note = TextEditingController(text: (r['note'] as String?) ?? '');
    String? err;

    Future<int?> pick(BuildContext c, int? cur, int fallback) async {
      final m = cur ?? fallback;
      final t = await showTimePicker(
          context: c, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
      return t == null ? null : t.hour * 60 + t.minute;
    }

    final sch = AttendanceRepo.schedule();
    final action = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(
              '${EmployeesRepo.fullName(r)}\n${DateFormat('EEE, MMM d').format(_date)}',
              style: Theme.of(c).textTheme.titleMedium),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Time in'),
                trailing: OutlinedButton(
                  onPressed: () async {
                    final v = await pick(c, tin, sch.startMin);
                    if (v != null) setD(() => tin = v);
                  },
                  child: Text(tin == null ? 'Set' : fmt12(tin!)),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Time out'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  OutlinedButton(
                    onPressed: () async {
                      final v = await pick(c, tout, sch.endMin);
                      if (v != null) setD(() => tout = v);
                    },
                    child: Text(tout == null ? 'Set' : fmt12(tout!)),
                  ),
                  if (tout != null)
                    IconButton(
                        tooltip: 'Clear time out',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setD(() => tout = null)),
                ]),
              ),
              TextField(
                  controller: note,
                  decoration:
                      const InputDecoration(labelText: 'Note (optional)')),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ),
            ]),
          ),
          actions: [
            if (r['att_id'] != null)
              TextButton(
                  onPressed: () => Navigator.pop(c, 'delete'),
                  child: const Text('Delete record')),
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (tin == null) {
                  setD(() => err = 'Set the time in.');
                } else if (tout != null && tout! <= tin!) {
                  setD(() => err = 'Time out must be later than time in.');
                } else {
                  Navigator.pop(c, 'save');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'save') {
        await AttendanceRepo.save(
          employeeId: r['id'] as int,
          empCode: r['emp_code'] as String,
          date: _key,
          timeIn: tin!,
          timeOut: tout,
          method: 'manual',
          note: note.text.trim(),
        );
      } else if (action == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Delete this attendance record?'),
            content: const Text('The deletion is recorded in the audit trail.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (ok != true) return;
        await AttendanceRepo.delete(r['att_id'] as int, r['emp_code'] as String,
            _key, r['time_in'] as String?, r['time_out'] as String?);
      }
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  List<Widget> _chips(DbRow r) {
    if (r['att_id'] == null) {
      if (_isFuture) return [const StatusChip(Status.inactive, 'Upcoming')];
      return _isToday
          ? [const StatusChip(Status.info, 'Not in yet')]
          : [const StatusChip(Status.bad, 'Absent')];
    }
    final lateMin = r['late_minutes'] as int;
    final under = r['undertime_minutes'] as int;
    final over = r['overtime_minutes'] as int;
    return [
      lateMin > 0
          ? StatusChip(Status.warn, 'Late ${lateMin}m')
          : const StatusChip(Status.good, 'Present'),
      if (under > 0) StatusChip(Status.warn, 'Undertime ${under}m'),
      if (over > 0) StatusChip(Status.info, 'Overtime ${over}m'),
      if (r['time_out'] == null && !_isToday)
        const StatusChip(Status.warn, 'No time out'),
    ];
  }

  Widget _summary(List<DbRow> rows) {
    final present = rows.where((r) => r['att_id'] != null).length;
    final lateCount = rows.where((r) => (r['late_minutes'] as int?) != null && (r['late_minutes'] as int) > 0).length;
    final missing = rows.length - present;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      StatusChip(Status.good, 'Present: $present'),
      StatusChip(Status.warn, 'Late: $lateCount'),
      if (!_isFuture)
        StatusChip(_isToday ? Status.info : Status.bad,
            _isToday ? 'Not in yet: $missing' : 'Absent: $missing'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(
                tooltip: 'Previous day',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1)),
            TextButton(
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => _date = d);
              },
              child: Text(DateFormat('EEEE, MMM d, y').format(_date),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
                tooltip: 'Next day',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1)),
            if (!_isToday)
              TextButton(
                  onPressed: () => setState(() => _date = DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                      DateTime.now().day)),
                  child: const Text('Today')),
          ]),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search employee',
                border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<DbRow>>(
          future: AttendanceRepo.forDate(_key),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data!;
            final rows = all.where((r) {
              final s = '${EmployeesRepo.fullName(r)} ${r['emp_code']}'.toLowerCase();
              return s.contains(_q);
            }).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _summary(all),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No employees to show for this day.')),
                  ),
                for (final r in rows) _card(context, r),
              ],
            );
          },
        ),
      ),
    ]);
  }

  Widget _card(BuildContext context, DbRow r) {
    final has = r['att_id'] != null;
    final tin = r['time_in'] as String?;
    final tout = r['time_out'] as String?;
    final times = has
        ? 'In ${fmt12(parseHm(tin!))}   Out ${tout == null ? '-' : fmt12(parseHm(tout))}'
            '${tout == null ? '' : '   Worked ${fmtDuration(r['minutes_worked'] as int)}'}'
        : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(EmployeesRepo.fullName(r),
              style: Theme.of(context).textTheme.titleMedium),
          Text([
            r['emp_code'],
            if ((r['position'] as String).isNotEmpty) r['position'],
          ].join('  |  ')),
          if (times.isNotEmpty) ...[const SizedBox(height: 4), Text(times)],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: _chips(r)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, children: [
            if (_isToday && !has)
              TextButton.icon(
                  onPressed: () => _punch(r, out: false),
                  icon: const Icon(Icons.login),
                  label: const Text('Time in now')),
            if (_isToday && has && tout == null)
              TextButton.icon(
                  onPressed: () => _punch(r, out: true),
                  icon: const Icon(Icons.logout),
                  label: const Text('Time out now')),
            if (!_isFuture)
              TextButton.icon(
                  onPressed: () => _edit(r),
                  icon: const Icon(Icons.edit),
                  label: Text(has ? 'Edit' : 'Enter manually')),
            const Tooltip(
              message: 'Fingerprint attendance needs a scanner (Phase 5)',
              child: IconButton(
                  onPressed: null, icon: Icon(Icons.fingerprint)),
            ),
          ]),
        ]),
      ),
    );
  }
}
