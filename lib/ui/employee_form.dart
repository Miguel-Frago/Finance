import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/employees_repo.dart';
import 'employee_history_screen.dart';

/// Add or edit an employee. Pass [id] to edit.
class EmployeeForm extends StatefulWidget {
  final int? id;
  const EmployeeForm({super.key, this.id});
  @override
  State<EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<EmployeeForm> {
  final _key = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _contact = TextEditingController();
  final _rate = TextEditingController();
  final _sss = TextEditingController();
  final _phil = TextEditingController();
  final _pagibig = TextEditingController();
  final _tin = TextEditingController();
  String _position = '', _dept = '', _status = 'Active', _pay = 'Monthly';
  DateTime _hired = DateTime.now();
  DateTime? _term;
  List<String> _positions = [], _depts = [];
  String _code = '';
  bool _loading = true;

  static final _df = DateFormat('MMM d, y');
  static final _iso = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _positions = await EmployeesRepo.distinct('position');
    _depts = await EmployeesRepo.distinct('department');
    if (widget.id != null) {
      final r = await EmployeesRepo.byId(widget.id!);
      if (r != null) {
        _code = r['emp_code'] as String;
        _first.text = r['first_name'] as String;
        _last.text = r['last_name'] as String;
        _contact.text = r['contact'] as String;
        _position = r['position'] as String;
        _dept = r['department'] as String;
        _status = r['status'] as String;
        _pay = r['pay_type'] as String;
        _rate.text = ((r['rate_centavos'] as int) / 100).toStringAsFixed(2);
        _hired = DateTime.parse(r['date_hired'] as String);
        _term = r['date_terminated'] == null
            ? null
            : DateTime.parse(r['date_terminated'] as String);
        _sss.text = r['sss_no'] as String;
        _phil.text = r['philhealth_no'] as String;
        _pagibig.text = r['pagibig_no'] as String;
        _tin.text = r['tin_no'] as String;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1990),
        lastDate: DateTime(2100),
      );

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_status == 'Terminated') {
      if (_term == null) {
        _snack('Choose the date terminated.');
        return;
      }
      if (_term!.isBefore(_hired)) {
        _snack('Date terminated cannot be before date hired.');
        return;
      }
    }
    final dup = await EmployeesRepo.duplicateName(_first.text, _last.text,
        exceptId: widget.id);
    if (dup != null && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Same name already exists'),
          content: Text('$dup has the same first and last name. '
              'Save this as a separate employee anyway?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
    final centavos =
        (double.parse(_rate.text.replaceAll(',', '').trim()) * 100).round();
    final v = <String, Object?>{
      'first_name': _first.text.trim(),
      'last_name': _last.text.trim(),
      'contact': _contact.text.trim(),
      'status': _status,
      'date_hired': _iso.format(_hired),
      'date_terminated':
          _status == 'Terminated' ? _iso.format(_term!) : null,
      'sss_no': _sss.text.trim(),
      'philhealth_no': _phil.text.trim(),
      'pagibig_no': _pagibig.text.trim(),
      'tin_no': _tin.text.trim(),
    };
    try {
      if (widget.id == null) {
        v.addAll({
          'position': _position.trim(),
          'department': _dept.trim(),
          'pay_type': _pay,
          'rate_centavos': centavos,
        });
        await EmployeesRepo.create(v);
      } else {
        await EmployeesRepo.update(widget.id!, v);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  Widget _suggest(String label, String initial, List<String> options,
      ValueChanged<String> onChanged) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initial),
      optionsBuilder: (v) => options
          .where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
      onSelected: onChanged,
      fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
        controller: ctrl,
        focusNode: focus,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _reloadJob() async {
    final r = await EmployeesRepo.byId(widget.id!);
    if (r == null || !mounted) return;
    setState(() {
      _position = r['position'] as String;
      _dept = r['department'] as String;
      _pay = r['pay_type'] as String;
      _rate.text = ((r['rate_centavos'] as int) / 100).toStringAsFixed(2);
    });
  }

  Widget _jobCard() {
    final centavos = (double.tryParse(_rate.text) ?? 0) * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Current position and pay',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text('${_position.isEmpty ? '-' : _position}  |  ${_dept.isEmpty ? '-' : _dept}'),
          Text('${EmployeesRepo.pesos(centavos.round())} per ${EmployeesRepo.payUnit[_pay]} ($_pay)'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EmployeeHistoryScreen(employeeId: widget.id!)));
              await _reloadJob();
            },
            icon: const Icon(Icons.trending_up),
            label: const Text('Rate, promotion & reviews'),
          ),
        ]),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final editing = widget.id != null;
    return Scaffold(
      appBar: AppBar(
          title: Text(editing ? 'Edit employee $_code' : 'New employee')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _key,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    if (!editing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                            'The employee ID (EMP-0001, EMP-0002, ...) is created automatically.'),
                      ),
                    TextFormField(
                        controller: _first,
                        decoration:
                            const InputDecoration(labelText: 'First name'),
                        validator: _required),
                    TextFormField(
                        controller: _last,
                        decoration:
                            const InputDecoration(labelText: 'Last name'),
                        validator: _required),
                    if (!editing) ...[
                      _suggest('Position', _position, _positions,
                          (v) => _position = v),
                      _suggest('Department', _dept, _depts, (v) => _dept = v),
                    ],
                    TextFormField(
                        controller: _contact,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(labelText: 'Contact number')),
                    const SizedBox(height: 16),
                    if (!editing) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _pay,
                      decoration: const InputDecoration(labelText: 'Pay type'),
                      items: EmployeesRepo.payTypes
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) => setState(() => _pay = v ?? _pay),
                    ),
                    TextFormField(
                      controller: _rate,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText:
                            'Rate (\u20b1 per ${EmployeesRepo.payUnit[_pay]})',
                        prefixText: '\u20b1 ',
                      ),
                      validator: (v) {
                        final n =
                            double.tryParse((v ?? '').replaceAll(',', '').trim());
                        return (n == null || n <= 0) ? 'Enter an amount above 0' : null;
                      },
                    ),
                    ] else
                      _jobCard(),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date hired'),
                      trailing: OutlinedButton(
                        onPressed: () async {
                          final d = await _pickDate(_hired);
                          if (d != null) setState(() => _hired = d);
                        },
                        child: Text(_df.format(_hired)),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const ['Active', 'Terminated']
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) => setState(() => _status = v ?? _status),
                    ),
                    if (_status == 'Terminated')
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Date terminated'),
                        trailing: OutlinedButton(
                          onPressed: () async {
                            final d = await _pickDate(_term ?? DateTime.now());
                            if (d != null) setState(() => _term = d);
                          },
                          child: Text(_term == null ? 'Choose' : _df.format(_term!)),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('Government numbers (optional)',
                        style: Theme.of(context).textTheme.titleSmall),
                    TextFormField(
                        controller: _sss,
                        decoration: const InputDecoration(labelText: 'SSS no.')),
                    TextFormField(
                        controller: _phil,
                        decoration:
                            const InputDecoration(labelText: 'PhilHealth no.')),
                    TextFormField(
                        controller: _pagibig,
                        decoration:
                            const InputDecoration(labelText: 'Pag-IBIG no.')),
                    TextFormField(
                        controller: _tin,
                        decoration: const InputDecoration(labelText: 'TIN')),
                    const SizedBox(height: 24),
                    FilledButton(onPressed: _save, child: const Text('Save employee')),
                  ]),
                ),
              ),
            ),
    );
  }
}
