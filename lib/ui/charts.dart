import 'dart:math';
import 'package:flutter/material.dart';

/// Short peso text for chart labels: 12,300 -> "\u20b112.3k".
String pesoShort(int centavos) {
  final v = centavos / 100;
  if (v.abs() >= 1000000) return '\u20b1${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 1000) return '\u20b1${(v / 1000).toStringAsFixed(1)}k';
  return '\u20b1${v.toStringAsFixed(0)}';
}

class BarSegment {
  final double value;
  final Color color;
  const BarSegment(this.value, this.color);
}

class BarItem {
  final String label, top;
  final List<BarSegment> segments;
  const BarItem(this.label, this.top, this.segments);
}

/// Simple vertical (optionally stacked) bar chart. No packages needed.
class VBars extends StatelessWidget {
  final List<BarItem> items;
  final double height;
  const VBars({super.key, required this.items, this.height = 170});

  @override
  Widget build(BuildContext context) {
    double total(BarItem i) => i.segments.fold<double>(0, (a, s) => a + s.value);
    final maxV = items.fold<double>(0, (m, i) => max(m, total(i)));
    final barArea = height - 44;
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final it in items)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                FittedBox(child: Text(it.top, style: const TextStyle(fontSize: 10))),
                const SizedBox(height: 2),
                Builder(builder: (_) {
                  final t = total(it);
                  final h = (maxV <= 0 || t <= 0) ? 2.0 : max(2.0, barArea * t / maxV);
                  return ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    child: t <= 0
                        ? Container(height: h, color: Theme.of(context).colorScheme.outlineVariant)
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            for (final s in it.segments.reversed)
                              if (s.value > 0) Container(height: h * s.value / t, color: s.color),
                          ]),
                  );
                }),
                const SizedBox(height: 4),
                Text(it.label,
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center),
              ]),
            ),
          ),
      ]),
    );
  }
}

class HBarItem {
  final String label, valueText;
  final double value;
  final Color color;
  const HBarItem(this.label, this.valueText, this.value, this.color);
}

/// Simple horizontal bar list, for example pay by department.
class HBars extends StatelessWidget {
  final List<HBarItem> items;
  const HBars({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final maxV = items.fold<double>(0, (m, i) => max(m, i.value));
    return Column(children: [
      for (final it in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
                width: 110,
                child: Text(it.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: maxV <= 0 ? 0.02 : max(0.02, it.value / maxV),
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                      color: it.color, borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(it.valueText, style: const TextStyle(fontSize: 12)),
          ]),
        ),
    ]);
  }
}
