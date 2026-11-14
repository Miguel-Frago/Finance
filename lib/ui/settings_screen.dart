import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../core/backup.dart';
import '../core/db.dart';
import '../core/settings.dart';
import '../theme/app_theme.dart';
import 'lock_gate.dart';
import 'payroll_rules_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _name = TextEditingController(text: Settings.get('company_name'));
  late final _addr = TextEditingController(text: Settings.get('company_address'));
  late final _break = TextEditingController(text: Settings.get('break_minutes', '60'));
  late final _grace = TextEditingController(text: Settings.get('grace_minutes', '0'));

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickTime(String key, String def) async {
    final cur = Settings.get(key, def).split(':');
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: int.parse(cur[0]), minute: int.parse(cur[1])));
    if (t == null) return;
    await Settings.set(key,
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    setState(() {});
  }

  Future<void> _pickImage(String key) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final src = r?.files.single.path;
    if (src == null) return;
    final dest = p.join(AppDb.supportDir, '$key${p.extension(src)}');
    await File(src).copy(dest);
    await Settings.set('${key}_path', dest);
    setState(() {});
  }

  Widget _imageBox(String key, String label) {
    final path = Settings.get('${key}_path');
    final has = path.isNotEmpty && File(path).existsSync();
    return Column(children: [
      Container(
        width: 150,
        height: 90,
        decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline)),
        alignment: Alignment.center,
        child: has
            ? Image.file(File(path), fit: BoxFit.contain)
            : Text('$label\n(temporary placeholder)',
                textAlign: TextAlign.center),
      ),
      TextButton(
          onPressed: () => _pickImage(key),
          child: Text(has ? 'Replace $label' : 'Upload $label')),
    ]);
  }

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                ...children,
              ]),
        ),
      );

  Future<_PwChoice?> _askBackupPassword() {
    final a = TextEditingController();
    final b = TextEditingController();
    String? err;
    return showDialog<_PwChoice>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Protect this backup?'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('A backup contains all salaries and personal data. '
                  'Protect it with a password. If you forget the password, the backup cannot be opened.'),
              TextField(
                  controller: a,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (6+ characters)')),
              TextField(
                  controller: b,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Repeat password')),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(c, const _PwChoice(null)),
                child: const Text('Save without password')),
            FilledButton(
              onPressed: () {
                if (a.text.length < 6) {
                  setD(() => err = 'Use at least 6 characters.');
                } else if (a.text != b.text) {
                  setD(() => err = 'The two passwords do not match.');
                } else {
                  Navigator.pop(c, _PwChoice(a.text));
                }
              },
              child: const Text('Save encrypted'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askRestorePassword() {
    final a = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Backup password'),
        content: TextField(
            controller: a,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, a.text), child: const Text('Open backup')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = Settings.get('last_backup_at');
    return ListView(padding: const EdgeInsets.all(20), children: [
      _section('Company (used on printed reports and payslips)', [
        TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Company name')),
        TextField(
            controller: _addr,
            decoration: const InputDecoration(labelText: 'Address')),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () async {
              await Settings.set('company_name', _name.text.trim());
              await Settings.set('company_address', _addr.text.trim());
              if (mounted) _snack('Company details saved.');
            },
            child: const Text('Save'),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 24, children: [
          _imageBox('logo', 'logo'),
          _imageBox('signature', 'signature'),
        ]),
      ]),
      _section('Work schedule (default, editable)', [
        Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton(
              onPressed: () => _pickTime('work_start', '08:00'),
              child: Text('Start: ${Settings.get('work_start', '08:00')}')),
          OutlinedButton(
              onPressed: () => _pickTime('work_end', '17:00'),
              child: Text('End: ${Settings.get('work_end', '17:00')}')),
          SizedBox(
              width: 140,
              child: TextField(
                  controller: _break,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Break (minutes)'),
                  onSubmitted: (v) => Settings.set('break_minutes', v.trim()))),
          SizedBox(
              width: 140,
              child: TextField(
                  controller: _grace,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Grace (minutes)'),
                  onSubmitted: (v) => Settings.set('grace_minutes', v.trim()))),
        ]),
        const SizedBox(height: 4),
        const Text('Press Enter after typing a number to save it. '
            'The schedule is not final yet, so change it any time.'),
      ]),
      _section('Payroll', [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.rule),
          title: const Text('Payroll rules'),
          subtitle: const Text('Overtime, working days, SSS / PhilHealth / Pag-IBIG / tax deductions'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PayrollRulesScreen())),
        ),
      ]),
      _section('Theme', [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in themeChoices.entries)
            ChoiceChip(
              avatar: CircleAvatar(backgroundColor: themeSwatches[e.key]),
              label: Text(e.value),
              selected: themeId.value == e.key,
              onSelected: (_) async {
                themeId.value = e.key;
                await Settings.set('theme', e.key);
                setState(() {});
              },
            ),
        ]),
      ]),
      _section('Security', [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.stars_rounded),
          title: const Text('Change puzzle lock'),
          subtitle: const Text('A new recovery code will be issued.'),
          onTap: () => changePuzzleRequest.value = true,
        ),
        Row(children: [
          const Text('Auto-lock after inactivity: '),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: Settings.getInt('lock_timeout_min', 5),
            items: const [0, 1, 5, 10, 30]
                .map((m) => DropdownMenuItem(
                    value: m, child: Text(m == 0 ? 'Never' : '$m min')))
                .toList(),
            onChanged: (v) async {
              await Settings.set('lock_timeout_min', '${v ?? 5}');
              setState(() {});
            },
          ),
        ]),
      ]),
      _section('Backup and restore', [
        Text(last.isEmpty
            ? 'No backup yet.'
            : 'Last backup: ${DateFormat('MMM d, y h:mm a').format(DateTime.parse(last))}'),
        const SizedBox(height: 8),
        Wrap(spacing: 12, children: [
          FilledButton.icon(
            icon: const Icon(Icons.save_alt),
            label: const Text('Back up now'),
            onPressed: () async {
              final choice = await _askBackupPassword();
              if (choice == null) return;
              final r = await Backup.create(password: choice.pw);
              if (mounted) {
                _snack(r.message);
                setState(() {});
              }
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.restore),
            label: const Text('Restore from file'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Restore data?'),
                  content: const Text(
                      'This replaces ALL current data with the backup file. '
                      'Back up first if you are unsure.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Restore')),
                  ],
                ),
              );
              if (ok != true) return;
              final r = await Backup.restore(askPassword: _askRestorePassword);
              if (mounted) {
                themeId.value = Settings.get('theme', 'light');
                _snack(r.message);
                setState(() {});
              }
            },
          ),
        ]),
        const SizedBox(height: 8),
        const Text('Tip: protect backups with a password, keep them on a USB drive or another device, '
            'and back up after every approved payroll. A forgotten backup password cannot be reset.'),
      ]),
    ]);
  }
}

class _PwChoice {
  final String? pw; // null = save without a password
  const _PwChoice(this.pw);
}
