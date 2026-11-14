import 'package:flutter/material.dart';

/// ZentriX palettes. Each preset controls both the full theme and its accent.
final ValueNotifier<String> themeId = ValueNotifier<String>('violet');

const themeChoices = <String, String>{
  'gold': 'Midnight Gold',
  'crimson': 'Crimson Noir',
  'ocean': 'Deep Ocean',
  'forest': 'Forest',
  'violet': 'Neon Violet',
  'paper': 'Paper Light',
};

const themeSwatches = <String, Color>{
  'gold': Color(0xFFE8B04A),
  'crimson': Color(0xFFFF4D5E),
  'ocean': Color(0xFF3CC8E6),
  'forest': Color(0xFF6FD68B),
  'violet': Color(0xFFB388FF),
  'paper': Color(0xFFB9770E),
};

enum Status { good, warn, bad, info, inactive }

/// Semantic status colors remain consistent across every ZentriX palette.
class StatusColors extends ThemeExtension<StatusColors> {
  final Color good, warn, bad, info, inactive;
  const StatusColors({required this.good, required this.warn, required this.bad, required this.info, required this.inactive});

  static const light = StatusColors(
    good: Color(0xFF2E7D32), warn: Color(0xFFF9A825), bad: Color(0xFFC62828),
    info: Color(0xFF1565C0), inactive: Color(0xFF757575),
  );
  static const dark = StatusColors(
    good: Color(0xFF66BB6A), warn: Color(0xFFFFCA28), bad: Color(0xFFEF5350),
    info: Color(0xFF64B5F6), inactive: Color(0xFF9E9E9E),
  );

  @override
  StatusColors copyWith({Color? good, Color? warn, Color? bad, Color? info, Color? inactive}) =>
      StatusColors(good: good ?? this.good, warn: warn ?? this.warn, bad: bad ?? this.bad,
        info: info ?? this.info, inactive: inactive ?? this.inactive);

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(good: Color.lerp(good, other.good, t)!, warn: Color.lerp(warn, other.warn, t)!,
      bad: Color.lerp(bad, other.bad, t)!, info: Color.lerp(info, other.info, t)!,
      inactive: Color.lerp(inactive, other.inactive, t)!);
  }
}

String normalizeThemeId(String id) => switch (id) {
  'light' => 'paper',
  'dark' => 'gold',
  'blue' => 'ocean',
  'green' => 'forest',
  'purple' => 'violet',
  'gold' || 'crimson' || 'ocean' || 'forest' || 'violet' || 'paper' => id,
  _ => 'violet',
};

ThemeData buildTheme(String rawId) {
  final id = normalizeThemeId(rawId);
  final brightness = id == 'paper' ? Brightness.light : Brightness.dark;
  final colors = switch (id) {
    'gold' => (bg: const Color(0xFF0F0E13), surface: const Color(0xFF1A1920), text: const Color(0xFFF2EFE8), muted: const Color(0xFF9C97A6), accent: const Color(0xFFE8B04A), border: const Color(0xFF2C2A35), onAccent: const Color(0xFF1A1206)),
    'crimson' => (bg: const Color(0xFF120A0C), surface: const Color(0xFF1F1215), text: const Color(0xFFF5EAEA), muted: const Color(0xFFA58F93), accent: const Color(0xFFFF4D5E), border: const Color(0xFF35202A), onAccent: Colors.white),
    'ocean' => (bg: const Color(0xFF08121A), surface: const Color(0xFF0F202C), text: const Color(0xFFE6F3F8), muted: const Color(0xFF7FA0B0), accent: const Color(0xFF3CC8E6), border: const Color(0xFF1B3445), onAccent: const Color(0xFF04202A)),
    'forest' => (bg: const Color(0xFF0B130E), surface: const Color(0xFF13211A), text: const Color(0xFFE9F3EA), muted: const Color(0xFF85A08C), accent: const Color(0xFF6FD68B), border: const Color(0xFF22382A), onAccent: const Color(0xFF062010)),
    'paper' => (bg: const Color(0xFFF5F1EA), surface: Colors.white, text: const Color(0xFF201D26), muted: const Color(0xFF6F6A78), accent: const Color(0xFFB9770E), border: const Color(0xFFE4DDD0), onAccent: Colors.white),
    _ => (bg: const Color(0xFF0E0A18), surface: const Color(0xFF191229), text: const Color(0xFFEFE9FB), muted: const Color(0xFF9A8FB5), accent: const Color(0xFFB388FF), border: const Color(0xFF2C2144), onAccent: const Color(0xFF14082A)),
  };
  final scheme = ColorScheme.fromSeed(seedColor: colors.accent, brightness: brightness).copyWith(
    primary: colors.accent, onPrimary: colors.onAccent, secondary: colors.accent,
    onSecondary: colors.onAccent, surface: colors.surface, onSurface: colors.text,
    outline: colors.border, surfaceContainerHighest: Color.lerp(colors.surface, colors.border, .45)!,
  );
  return ThemeData(
    useMaterial3: true, brightness: brightness, colorScheme: scheme,
    scaffoldBackgroundColor: colors.bg, canvasColor: colors.bg,
    cardTheme: CardThemeData(color: colors.surface, surfaceTintColor: Colors.transparent),
    appBarTheme: AppBarTheme(backgroundColor: colors.bg, foregroundColor: colors.text, surfaceTintColor: Colors.transparent),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: colors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.border))),
    extensions: [brightness == Brightness.dark ? StatusColors.dark : StatusColors.light],
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

Color statusColor(BuildContext context, Status s) {
  final c = Theme.of(context).extension<StatusColors>()!;
  return switch (s) { Status.good => c.good, Status.warn => c.warn, Status.bad => c.bad, Status.info => c.info, Status.inactive => c.inactive };
}

IconData statusIcon(Status s) => switch (s) {
  Status.good => Icons.check_circle, Status.warn => Icons.warning_amber_rounded,
  Status.bad => Icons.error, Status.info => Icons.info, Status.inactive => Icons.remove_circle_outline,
};

class StatusChip extends StatelessWidget {
  final Status status;
  final String label;
  const StatusChip(this.status, this.label, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: c)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(statusIcon(status), size: 16, color: c), const SizedBox(width: 6),
        Flexible(child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
