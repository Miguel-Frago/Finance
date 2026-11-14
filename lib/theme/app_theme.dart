import 'package:flutter/material.dart';

/// Currently selected theme id: light, dark, blue, green, purple.
final ValueNotifier<String> themeId = ValueNotifier<String>('light');

const themeChoices = <String, String>{
  'light': 'Light',
  'dark': 'Dark',
  'blue': 'Ocean Blue',
  'green': 'Teal Green',
  'purple': 'Royal Purple',
};

const themeSwatches = <String, Color>{
  'light': Colors.indigo,
  'dark': Color(0xFF263238),
  'blue': Colors.blue,
  'green': Colors.teal,
  'purple': Colors.deepPurple,
};

enum Status { good, warn, bad, info, inactive }

/// Meaning colors used everywhere (monitoring, dashboard, charts).
/// They stay the same in every theme so the color code never changes.
class StatusColors extends ThemeExtension<StatusColors> {
  final Color good, warn, bad, info, inactive;
  const StatusColors({
    required this.good,
    required this.warn,
    required this.bad,
    required this.info,
    required this.inactive,
  });

  static const light = StatusColors(
    good: Color(0xFF2E7D32),
    warn: Color(0xFFF9A825),
    bad: Color(0xFFC62828),
    info: Color(0xFF1565C0),
    inactive: Color(0xFF757575),
  );
  static const dark = StatusColors(
    good: Color(0xFF66BB6A),
    warn: Color(0xFFFFCA28),
    bad: Color(0xFFEF5350),
    info: Color(0xFF64B5F6),
    inactive: Color(0xFF9E9E9E),
  );

  @override
  StatusColors copyWith({Color? good, Color? warn, Color? bad, Color? info, Color? inactive}) =>
      StatusColors(
        good: good ?? this.good,
        warn: warn ?? this.warn,
        bad: bad ?? this.bad,
        info: info ?? this.info,
        inactive: inactive ?? this.inactive,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      good: Color.lerp(good, other.good, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      info: Color.lerp(info, other.info, t)!,
      inactive: Color.lerp(inactive, other.inactive, t)!,
    );
  }
}

ThemeData buildTheme(String id) {
  final isDark = id == 'dark';
  final seed = switch (id) {
    'blue' => Colors.blue,
    'green' => Colors.teal,
    'purple' => Colors.deepPurple,
    'dark' => Colors.indigo,
    _ => Colors.indigo,
  };
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ),
    extensions: [isDark ? StatusColors.dark : StatusColors.light],
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

Color statusColor(BuildContext context, Status s) {
  final c = Theme.of(context).extension<StatusColors>()!;
  return switch (s) {
    Status.good => c.good,
    Status.warn => c.warn,
    Status.bad => c.bad,
    Status.info => c.info,
    Status.inactive => c.inactive,
  };
}

IconData statusIcon(Status s) => switch (s) {
      Status.good => Icons.check_circle,
      Status.warn => Icons.warning_amber_rounded,
      Status.bad => Icons.error,
      Status.info => Icons.info,
      Status.inactive => Icons.remove_circle_outline,
    };

/// Color + icon + label, so meaning never depends on color alone.
class StatusChip extends StatelessWidget {
  final Status status;
  final String label;
  const StatusChip(this.status, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(statusIcon(status), size: 16, color: c),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              style: TextStyle(color: c, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
