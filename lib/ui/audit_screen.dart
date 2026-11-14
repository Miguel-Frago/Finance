import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/audit.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search the audit trail',
              border: OutlineInputBorder()),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: Audit.recent(q: _q),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data!;
            if (rows.isEmpty) return const Center(child: Text('No entries.'));
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                final at = DateFormat('MMM d, y h:mm:ss a')
                    .format(DateTime.parse(r['at'] as String));
                final detail = [
                  if ((r['entity_id'] as String).isNotEmpty)
                    '${r['entity']}: ${r['entity_id']}',
                  if (r['old_value'] != null) 'from "${r['old_value']}"',
                  if (r['new_value'] != null) 'to "${r['new_value']}"',
                ].join('  ');
                return ListTile(
                  dense: true,
                  title: Text(r['action'] as String),
                  subtitle: Text('$at  |  ${r['device']}\n$detail'),
                  isThreeLine: detail.isNotEmpty,
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
