import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/employees_repo.dart';
import '../core/rates_repo.dart';
import '../core/reviews_repo.dart';
import '../theme/app_theme.dart';

/// Rate and position history plus performance reviews for one employee.
class EmployeeHistoryScreen extends StatefulWidget {
  final int employeeId;
  const EmployeeHistoryScreen({super.key, required this.employeeId});
  @override
  State<EmployeeHistoryScreen> createState() => _EmployeeHistoryScreenState();
}

class _EmployeeHistoryScreenState extends State<EmployeeHistoryScreen> {
  DbRow? _emp;
  static final _df = DateFormat('MMM d, y');
  static final _iso = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    EmployeesRepo.byId(widget.employeeId).then((e) {
      if (mounted) setState(() => _emp = e);
    });
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
          ],
        ),
      ) ??
      false;

  // ---------------------------------------------------------------- rates

  Future<void> _changeRate() async {
    final today = _iso.format(DateTime.now());
    final cur = await RatesRepo.effectiveOn(widget.employeeId, today) ?? _emp;
    if (cur == null || !mounted) return;
    DateTime date = DateTime.now();
    final pos = TextEditingController(text: cur['position'] as String);
    final dept = TextEditingController(text: cur['department'] as String);
    final rate = TextEditingController(
        text: ((cur['rate_centavos'] as int) / 100).toStringAsFixed(2));
    final note = TextEditingController();
    String pay = cur['pay_type'] as String;
    String reason = 'Promotion';
    String? err;

    await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Change rate / promote'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Effective date'),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: c,
                          initialDate: date,
                          firstDate: DateTime(1990),
                          lastDate: DateTime(2100));
                      if (d != null) setD(() => date = d);
                    },
                    child: Text(_df.format(date)),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: RatesRepo.reasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setD(() => reason = v ?? reason),
                ),
                TextField(
                    controller: pos,
                    decoration: const InputDecoration(labelText: 'Position')),
                TextField(
                    controller: dept,
                    decoration: const InputDecoration(labelText: 'Department')),
                DropdownButtonFormField<String>(
                  initialValue: pay,
                  decoration: const InputDecoration(
                      labelText: 'Pay type',
                      helperText: 'Change only if the company allows it.'),
                  items: EmployeesRepo.payTypes
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setD(() => pay = v ?? pay),
                ),
                TextField(
                  controller: rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'New rate (\u20b1 per ${EmployeesRepo.payUnit[pay]})',
                      prefixText: '\u20b1 '),
                ),
                TextField(
                    controller: note,
                    decoration: const InputDecoration(labelText: 'Note (optional)')),
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
                final n = double.tryParse(rate.text.replaceAll(',', '').trim());
                if (n == null || n <= 0) {
                  setD(() => err = 'Enter a rate above 0.');
                  return;
                }
                final e = await RatesRepo.add(
                  empId: widget.employeeId,
                  date: _iso.format(date),
                  position: pos.text.trim(),
                  department: dept.text.trim(),
                  payType: pay,
                  rateCentavos: (n * 100).round(),
                  reason: reason,
                  note: note.text.trim(),
                );
                if (e != null) {
                  setD(() => err = e);
                } else if (c.mounted) {
                  Navigator.pop(c, true);
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

  Widget _ratesTab() {
    final today = _iso.format(DateTime.now());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
              onPressed: _changeRate,
              icon: const Icon(Icons.trending_up),
              label: const Text('Change rate / promote')),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<DbRow>>(
          future: RatesRepo.list(widget.employeeId),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            final currentId = rows
                .firstWhere((r) => (r['effective_date'] as String).compareTo(today) <= 0,
                    orElse: () => rows.first)['id'];
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              for (final r in rows)
                Card(
                  child: ListTile(
                    title: Text(
                        '${_df.format(DateTime.parse(r['effective_date'] as String))}  -  ${r['reason']}'),
                    subtitle: Text(
                        '${r['position']}  |  ${r['department']}\n'
                        '${EmployeesRepo.pesos(r['rate_centavos'] as int)} / ${EmployeesRepo.payUnit[r['pay_type']]} (${r['pay_type']})'
                        '${(r['note'] as String).isEmpty ? '' : '\n${r['note']}'}'),
                    isThreeLine: true,
                    trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (r['id'] == currentId)
                        const StatusChip(Status.good, 'Current')
                      else if ((r['effective_date'] as String).compareTo(today) > 0)
                        const StatusChip(Status.info, 'Scheduled'),
                      if (r['reason'] != 'Hired')
                        IconButton(
                          tooltip: 'Delete entry',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await _confirm('Delete this entry?',
                                'Use this only to remove a mistake. It is recorded in the audit trail.')) {
                              await RatesRepo.delete(r['id'] as int);
                              if (mounted) setState(() {});
                            }
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

  // -------------------------------------------------------------- reviews

  Future<void> _addReview() async {
    DateTime date = DateTime.now();
    int rating = 3;
    final reviewer = TextEditingController();
    final comments = TextEditingController();
    await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Add performance review'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Review date'),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: c,
                          initialDate: date,
                          firstDate: DateTime(1990),
                          lastDate: DateTime(2100));
                      if (d != null) setD(() => date = d);
                    },
                    child: Text(_df.format(date)),
                  ),
                ),
                DropdownButtonFormField<int>(
                  initialValue: rating,
                  decoration: const InputDecoration(labelText: 'Rating'),
                  items: ReviewsRepo.ratingLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text('${e.key} - ${e.value}')))
                      .toList(),
                  onChanged: (v) => setD(() => rating = v ?? rating),
                ),
                TextField(
                    controller: reviewer,
                    decoration: const InputDecoration(labelText: 'Reviewed by (optional)')),
                TextField(
                    controller: comments,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Comments (optional)')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await ReviewsRepo.add(
                  empId: widget.employeeId,
                  date: _iso.format(date),
                  rating: rating,
                  reviewer: reviewer.text.trim(),
                  comments: comments.text.trim(),
                );
                if (c.mounted) Navigator.pop(c, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Status _ratingStatus(int r) =>
      r >= 4 ? Status.good : (r == 3 ? Status.info : (r == 2 ? Status.warn : Status.bad));

  Widget _reviewsTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
              onPressed: _addReview,
              icon: const Icon(Icons.rate_review),
              label: const Text('Add review')),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<DbRow>>(
          future: ReviewsRepo.list(widget.employeeId),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return const Center(child: Text('No reviews yet.'));
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              for (final r in rows)
                Card(
                  child: ListTile(
                    title: Text(_df.format(DateTime.parse(r['review_date'] as String))),
                    subtitle: Text([
                      if ((r['reviewer'] as String).isNotEmpty) 'By ${r['reviewer']}',
                      if ((r['comments'] as String).isNotEmpty) r['comments'] as String,
                    ].join('\n')),
                    trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      StatusChip(_ratingStatus(r['rating'] as int),
                          '${r['rating']} - ${ReviewsRepo.ratingLabels[r['rating']]}'),
                      IconButton(
                        tooltip: 'Delete review',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await _confirm('Delete this review?',
                              'It is recorded in the audit trail.')) {
                            await ReviewsRepo.delete(r['id'] as int);
                            if (mounted) setState(() {});
                          }
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_emp == null
              ? 'History'
              : '${EmployeesRepo.fullName(_emp!)}  (${_emp!['emp_code']})'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Rate & position'),
            Tab(text: 'Performance reviews'),
          ]),
        ),
        body: TabBarView(children: [_ratesTab(), _reviewsTab()]),
      ),
    );
  }
}
