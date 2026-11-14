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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.stars_rounded, size: 56, color: cs.primary),
              const SizedBox(height: 8),
              Text('ZentriX',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Text(_title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              if (_step == _Step.forgot) ..._forgotBody(),
              if (_step == _Step.showCode) ..._codeBody(),
              if (_step != _Step.forgot && _step != _Step.showCode) ...[
                PatternPad(onComplete: _onPattern, enabled: !_blocked),
                const SizedBox(height: 12),
                Text(
                  _step == _Step.setup1
                      ? 'Drag across at least $_minDots stars. Remember the order!'
                      : _step == _Step.unlock
                          ? 'Drag across the stars in your secret order.'
                          : '',
                  textAlign: TextAlign.center,
                ),
              ],
              if (_msg.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_msg, style: TextStyle(color: cs.error)),
                ),
              const SizedBox(height: 8),
              if (_step == _Step.unlock)
                TextButton(
                    onPressed: () => setState(() {
                          _step = _Step.forgot;
                          _msg = '';
                        }),
                    child: const Text('Forgot the puzzle?')),
              if (widget.onCancel != null && _step != _Step.showCode)
                TextButton(
                    onPressed: widget.onCancel, child: const Text('Cancel')),
            ]),
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
