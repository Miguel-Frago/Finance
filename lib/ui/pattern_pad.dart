import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 3x3 "connect the stars" puzzle pad. Returns the dot order (0..8).
class PatternPad extends StatefulWidget {
  final ValueChanged<List<int>> onComplete;
  final bool enabled;
  const PatternPad({super.key, required this.onComplete, this.enabled = true});

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  static const double _size = 300;
  final List<int> _sel = [];
  Offset? _cur;

  Offset _center(int i) {
    const cell = _size / 3;
    return Offset((i % 3) * cell + cell / 2, (i ~/ 3) * cell + cell / 2);
  }

  void _hit(Offset pos) {
    for (var i = 0; i < 9; i++) {
      if (!_sel.contains(i) && (pos - _center(i)).distance < 34) {
        setState(() => _sel.add(i));
        HapticFeedback.selectionClick();
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Center(
      child: SizedBox(
        width: _size,
        height: _size,
        child: GestureDetector(
          onPanStart: widget.enabled
              ? (d) {
                  setState(() {
                    _sel.clear();
                    _cur = d.localPosition;
                  });
                  _hit(d.localPosition);
                }
              : null,
          onPanUpdate: widget.enabled
              ? (d) {
                  setState(() => _cur = d.localPosition);
                  _hit(d.localPosition);
                }
              : null,
          onPanEnd: widget.enabled
              ? (_) {
                  final result = List<int>.from(_sel);
                  setState(() {
                    _sel.clear();
                    _cur = null;
                  });
                  widget.onComplete(result);
                }
              : null,
          child: CustomPaint(
            painter: _PadPainter(_sel, _cur, color, _center,
                Theme.of(context).colorScheme.outline),
          ),
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  final List<int> sel;
  final Offset? cur;
  final Color color, idle;
  final Offset Function(int) center;
  _PadPainter(this.sel, this.cur, this.color, this.center, this.idle);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < sel.length - 1; i++) {
      canvas.drawLine(center(sel[i]), center(sel[i + 1]), line);
    }
    if (sel.isNotEmpty && cur != null) {
      canvas.drawLine(center(sel.last), cur!, line);
    }
    for (var i = 0; i < 9; i++) {
      final on = sel.contains(i);
      canvas.drawCircle(center(i), on ? 22 : 14,
          Paint()..color = on ? color : idle.withValues(alpha: 0.5));
      if (on) {
        canvas.drawCircle(center(i), 8, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) => true;
}
