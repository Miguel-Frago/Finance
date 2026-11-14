import 'package:flutter/material.dart';
import '../core/security.dart';
import 'pattern_pad.dart';

enum _Step { unlock, forgot, setup1, setup2, showCode }

/// Puzzle lock: unlock, first-time setup, change puzzle, recovery.
/// All steps are drawn inline (no dialogs) so this screen can sit above the app.
class LockScreen extends StatefulWidget {
  final bool setup;
  final VoidCallback onDone;
  final VoidCallback? onCancel;
  const LockScreen(
      {super.key, required this.setup, required this.onDone, this.onCancel});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late _Step _step = widget.setup ? _Step.setup1 : _Step.unlock;
  List<int> _first = [];
  String _msg = '';
  String _code = '';
  bool _written = false;
  int _fails = 0;
  DateTime? _blockedUntil;
  final _recovery = TextEditingController();

  static const _minDots = 4;

  bool get _blocked =>
      _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  void _onPattern(List<int> p) async {
    if (p.length < _minDots) {
      setState(() => _msg = 'Connect at least $_minDots stars.');
      return;
    }
    switch (_step) {
      case _Step.unlock:
        if (Security.verifyPattern(p)) {
          widget.onDone();
        } else {
          _fails++;
          if (_fails >= 5) {
            _fails = 0;
            _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
            setState(() => _msg = 'Too many tries. Wait 30 seconds.');
            Future.delayed(const Duration(seconds: 30), () {
              if (mounted) setState(() => _msg = '');
            });
          } else {
            setState(() => _msg = 'Not quite. Try again. ($_fails/5)');
          }
        }
      case _Step.setup1:
        _first = p;
        setState(() {
          _step = _Step.setup2;
          _msg = '';
        });
      case _Step.setup2:
        if (p.join() == _first.join()) {
          final code = await Security.savePattern(p);
          setState(() {
            _code = code;
            _step = _Step.showCode;
            _msg = '';
          });
        } else {
          setState(() {
            _step = _Step.setup1;
            _msg = 'The two puzzles did not match. Start again.';
          });
        }
      default:
        break;
    }
  }

  String get _title => switch (_step) {
        _Step.unlock => 'Solve the puzzle to unlock',
        _Step.setup1 => 'Create your secret puzzle',
        _Step.setup2 => 'Draw it once more to confirm',
        _Step.forgot => 'Enter your recovery code',
        _Step.showCode => 'Save your recovery code',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = cs.onSurface.withValues(alpha: 0.66);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.scaffoldBackgroundColor,
              Color.lerp(theme.scaffoldBackgroundColor, cs.primary, isDark ? 0.13 : 0.055)!,
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [cs.primary, Color.lerp(cs.primary, cs.surface, 0.38)!],
                      ),
                      boxShadow: [
                        BoxShadow(color: cs.primary.withValues(alpha: 0.28), blurRadius: 28, spreadRadius: 1),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text('Z', style: TextStyle(
                      fontSize: 48, height: 1, fontWeight: FontWeight.w900,
                      color: cs.onPrimary, fontStyle: FontStyle.italic,
                    )),
                  ),
                  const SizedBox(height: 14),
                  Text('ZENTRIX', style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900, letterSpacing: 4,
                  )),
                  const SizedBox(height: 4),
                  Text('BUSINESS MANAGEMENT SYSTEM', style: theme.textTheme.labelSmall?.copyWith(
                    color: muted, letterSpacing: 2.1, fontWeight: FontWeight.w600,
                  ), textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: cs.primary.withValues(alpha: 0.24)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(_step == _Step.unlock ? Icons.lock_rounded : Icons.shield_outlined,
                              size: 15, color: cs.primary),
                            const SizedBox(width: 7),
                            Text(_step == _Step.unlock ? 'SECURE ACCESS' : 'SECURITY SETUP',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.primary, fontWeight: FontWeight.w800, letterSpacing: 1.2,
                              )),
                          ]),
                        ),
                        const SizedBox(height: 18),
                        Text(_title, textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 18),
                        if (_step == _Step.forgot) ..._forgotBody(),
                        if (_step == _Step.showCode) ..._codeBody(),
                        if (_step != _Step.forgot && _step != _Step.showCode) ...[
                          PatternPad(onComplete: _onPattern, enabled: !_blocked),
                          const SizedBox(height: 12),
                          Text(
                            _step == _Step.setup1
                                ? 'Connect at least $_minDots dots. Remember your pattern.'
                                : _step == _Step.unlock
                                    ? 'Draw your saved pattern to continue.'
                                    : 'Repeat the same pattern to confirm.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(color: muted),
                          ),
                        ],
                        if (_msg.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_msg, textAlign: TextAlign.center,
                              style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
                          ),
                        if (_step == _Step.unlock)
                          TextButton(
                            onPressed: () => setState(() {
                              _step = _Step.forgot;
                              _msg = '';
                            }),
                            child: const Text('Forgot your pattern?'),
                          ),
                        if (widget.onCancel != null && _step != _Step.showCode)
                          TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('MONITOR  •  MANAGE  •  GROW',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted, letterSpacing: 1.7, fontWeight: FontWeight.w600,
                    )),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _forgotBody() => [
        TextField(
          controller: _recovery,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'Recovery code', hintText: 'XXXX-XXXX-XXXX'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            if (Security.verifyRecovery(_recovery.text)) {
              setState(() {
                _step = _Step.setup1;
                _msg = '';
              });
            } else {
              setState(() => _msg = 'That code is not correct.');
            }
          },
          child: const Text('Reset my puzzle'),
        ),
        TextButton(
            onPressed: () => setState(() => _step = _Step.unlock),
            child: const Text('Back')),
      ];

  List<Widget> _codeBody() => [
        const Text(
            'If you forget the puzzle, this code is the only way back in. '
            'Write it down and keep it somewhere safe. It is shown only once.',
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        SelectableText(_code,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(letterSpacing: 2, fontWeight: FontWeight.bold)),
        CheckboxListTile(
          value: _written,
          onChanged: (v) => setState(() => _written = v ?? false),
          title: const Text('I have written it down'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        FilledButton(
            onPressed: _written ? widget.onDone : null,
            child: const Text('Continue')),
      ];
}
