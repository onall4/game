import 'dart:async';

import 'package:flutter/widgets.dart';

/// 游戏计时器：首次操作时开始，应用切到后台自动暂停。
///
/// 继续上一局时传入 [initialElapsedMs]，从上次的用时接着计。
class GameClock extends ChangeNotifier with WidgetsBindingObserver {
  GameClock({int initialElapsedMs = 0}) : _initialMs = initialElapsedMs {
    WidgetsBinding.instance.addObserver(this);
  }

  final int _initialMs;
  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;
  bool _started = false;
  bool _stopped = false;

  int get elapsedMs => _initialMs + _watch.elapsedMilliseconds;
  bool get isRunning => _watch.isRunning;
  bool get started => _started;

  void start() {
    if (_started || _stopped) return;
    _started = true;
    _resume();
  }

  void stop() {
    _stopped = true;
    _pause();
    notifyListeners();
  }

  void _resume() {
    if (!_started || _stopped || _watch.isRunning) return;
    _watch.start();
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => notifyListeners(),
    );
  }

  void _pause() {
    _watch.stop();
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pause();
    super.dispose();
  }
}
