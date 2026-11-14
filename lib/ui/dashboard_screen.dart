import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/dashboard_repo.dart';
import '../core/db.dart';
import '../core/employees_repo.dart';
import '../core/reports.dart';
import '../core/settings.dart';
import '../theme/app_theme.dart';
import 'charts.dart';
import 'payroll_screen.dart' show payrollStatus;
import 'report_preview_screen.dart';

/// Color-coded dashboard. Widgets can be shown or hidden, and the printed
/// dashboard report follows what is visible.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<DashData> _future = DashboardRepo.load();
  Set<String> _hidden = DashboardRepo.hidden();

  (Status, String) _backupStatus() {
    final raw = Settings.get('last_backup_at');
    if (raw.isEmpty) return (Status.bad, 'No backup yet');
    final days = DateTime.now().difference(DateTime.parse(raw)).inDays;
    final when = DateFormat('MMM d, y h:mm a').format(DateTime.parse(raw));
    if (days < 7) return (Status.good, 'Backed up $when');
    if (days < 30) return (Status.warn, 'Last backup $when ($days days ago)');
    return (Status.bad, 'Last backup $when ($days days ago)');
  }

  Future<void> _customize() async {
    final hidden = {..._hidden};
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Choose what to show'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final e in dashWidgets.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: !hidden.contains(e.key),
                  onChanged: (v) => setD(() => v == true ? hidden.remove(e.key) : hidden.add(e.key)),
                ),
              const SizedBox(height: 4),
              const Text('The printed dashboard report shows the same widgets.'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await DashboardRepo.setHidden(hidden);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => _hidden = DashboardRepo.hidden());
  }

  Widget _kpi(String title, String value, Status s) {
    final c = statusColor(context, s);
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: c, width: 5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: c, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _panel(double w, String title, Widget child) => SizedBox(
        width: w,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              child,
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashData>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        return LayoutBuilder(builder: (context, box) {
          final avail = box.maxWidth - 40;
          final w = box.maxWidth >= 1000 ? (avail - 16) / 2 : avail;
          final good = statusColor(context, Status.good);
          final warn = statusColor(context, Status.warn);
          final info = statusColor(context, Status.info);
          final (bStatus, bText) = _backupStatus();
          final size = File(AppDb.path).existsSync()
              ? '${(File(AppDb.path).lengthSync() / 1024).toStringAsFixed(0)} KB'
              : '-';

          final panels = <Widget>[];
          if (d != null) {
            final s = d.stats;
            if (!_hidden.contains('kpi')) {
              panels.add(SizedBox(
                width: avail,
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  _kpi('Active employees', '${s['active']}', Status.info),
                  _kpi('Present today', '${s['present']} of ${(s['present'] ?? 0) + (s['notYet'] ?? 0)}', Status.good),
                  _kpi('Late today', '${s['late']}', (s['late'] ?? 0) > 0 ? Status.warn : Status.good),
                  _kpi('Latest payroll (net)',
                      d.latest == null ? '-' : EmployeesRepo.pesos(d.latest!['net'] as int),
                      d.latest == null ? Status.inactive : payrollStatus(d.latest!['status'] as String)),
                  _kpi('Loans outstanding', EmployeesRepo.pesos(d.loansOutstanding),
                      d.loansOutstanding > 0 ? Status.warn : Status.good),
                ]),
              ));
            }
            if (!_hidden.contains('attendance_week')) {
              panels.add(_panel(
                w,
                'Attendance, last 7 days',
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  VBars(items: [
                    for (final a in d.week)
                      BarItem(DateFormat('E d').format(a.date), '${a.present}', [
                        BarSegment((a.present - a.lateCount).toDouble(), good),
                        BarSegment(a.lateCount.toDouble(), warn),
                      ]),
                  ]),
                  const SizedBox(height: 8),
                  const Wrap(spacing: 8, children: [
                    StatusChip(Status.good, 'On time'),
                    StatusChip(Status.warn, 'Late'),
                  ]),
                ]),
              ));
            }
            if (!_hidden.contains('payroll_trend')) {
              panels.add(_panel(
                w,
                'Payroll by period (net pay)',
                d.trend.isEmpty
                    ? const Text('No payroll yet.')
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        VBars(items: [
                          for (final p in d.trend)
                            BarItem(
                              DashboardRepo.shortDate(p['date_from'] as String),
                              pesoShort(p['net'] as int),
                              [
                                BarSegment(
                                    ((p['net'] as int) < 0 ? 0 : p['net'] as int).toDouble(),
                                    statusColor(context, payrollStatus(p['status'] as String)))
                              ],
                            ),
                        ]),
                        const SizedBox(height: 8),
                        const Wrap(spacing: 8, runSpacing: 6, children: [
                          StatusChip(Status.warn, 'Draft'),
                          StatusChip(Status.info, 'Computed'),
                          StatusChip(Status.good, 'Approved / Paid'),
                        ]),
                      ]),
              ));
            }
            if (!_hidden.contains('dept_cost')) {
              panels.add(_panel(
                w,
                'Pay by department${d.latest == null ? '' : ' - ${d.latest!['label']}'}',
                d.dept.isEmpty
                    ? const Text('Compute a payroll to see this.')
                    : HBars(items: [
                        for (final r in d.dept)
                          HBarItem('${r['dept']} (${r['n']})', pesoShort(r['net'] as int),
                              ((r['net'] as int) < 0 ? 0 : r['net'] as int).toDouble(), info),
                      ]),
              ));
            }
          } else {
            panels.add(const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())));
          }
          if (!_hidden.contains('data_safety')) {
            panels.add(_panel(w, 'Data safety', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatusChip(bStatus, bText),
              const SizedBox(height: 8),
              Text('Database size: $size'),
            ])));
          }
          if (!_hidden.contains('color_guide')) {
            panels.add(_panel(w, 'Color guide', const Wrap(spacing: 8, runSpacing: 8, children: [
              StatusChip(Status.good, 'Good / present / paid'),
              StatusChip(Status.warn, 'Attention / late / pending'),
              StatusChip(Status.bad, 'Problem / absent / overdue'),
              StatusChip(Status.info, 'Information / in progress'),
              StatusChip(Status.inactive, 'Inactive / not applicable'),
            ])));
          }

          return ListView(padding: const EdgeInsets.all(20), children: [
            Text(Settings.get('company_name', 'Your Company'),
                style: Theme.of(context).textTheme.headlineMedium),
            Text(DateFormat('EEEE, MMMM d, y').format(DateTime.now())),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: () => setState(() => _future = DashboardRepo.load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh')),
              OutlinedButton.icon(
                  onPressed: _customize,
                  icon: const Icon(Icons.tune),
                  label: const Text('Customize')),
              FilledButton.icon(
                onPressed: () => openReport(context,
                    title: 'Dashboard summary',
                    fileName: 'dashboard.pdf',
                    build: (f) => Reports.dashboard(f, DashboardRepo.hidden())),
                icon: const Icon(Icons.print),
                label: const Text('Print dashboard'),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 16, children: panels),
          ]);
        });
      },
    );
  }
}
