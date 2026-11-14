import 'dart:async';
import 'package:flutter/material.dart';
import '../core/audit.dart';
import '../core/security.dart';
import '../core/settings.dart';
import 'lock_screen.dart';

/// Set to true from Settings to open the "change puzzle" screen.
final ValueNotifier<bool> changePuzzleRequest = ValueNotifier<bool>(false);

/// Sits above the whole app. The app underneath keeps its state while locked.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _locked = true;
  bool _changing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    changePuzzleRequest.addListener(_onChangeRequest);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    changePuzzleRequest.removeListener(_onChangeRequest);
    _timer?.cancel();
    super.dispose();
  }

  void _onChangeRequest() {
    if (changePuzzleRequest.value) setState(() => _changing = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if ((s == AppLifecycleState.paused) && Security.hasLock && !_locked) {
      setState(() => _locked = true);
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    final mins = Settings.getInt('lock_timeout_min', 5);
    if (mins <= 0 || !Security.hasLock || _locked) return;
    _timer = Timer(Duration(minutes: mins), () {
      if (mounted) setState(() => _locked = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstRun = !Security.hasLock;
    Widget? overlay;
    if (firstRun || _changing) {
      overlay = LockScreen(
        setup: true,
        onCancel: (firstRun) ? null : () {
          changePuzzleRequest.value = false;
          setState(() => _changing = false);
        },
        onDone: () async {
          await Audit.log(firstRun ? 'PUZZLE_CREATED' : 'PUZZLE_CHANGED');
          changePuzzleRequest.value = false;
          setState(() {
            _changing = false;
            _locked = false;
          });
          _resetTimer();
        },
      );
    } else if (_locked) {
      overlay = LockScreen(
        setup: false,
        onDone: () {
          Audit.log('UNLOCKED');
          setState(() => _locked = false);
          _resetTimer();
        },
      );
    }
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      onPointerHover: (_) => _resetTimer(),
      child: Stack(children: [
        widget.child,
        if (overlay != null) Positioned.fill(child: overlay),
      ]),
    );
  }
}
