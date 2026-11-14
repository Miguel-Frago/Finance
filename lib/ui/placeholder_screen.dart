import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;
  final Status status;
  final String tag;
  const PlaceholderScreen(this.title, this.icon, this.description,
      {super.key, required this.status, required this.tag});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 72, color: statusColor(context, status)),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            StatusChip(status, tag),
            const SizedBox(height: 16),
            Text(description, textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}
