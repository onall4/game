import 'dart:async';

import 'package:flutter/material.dart';

import '../core/data/models/score_kind.dart';
import '../ui/widgets/chunky.dart';

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
  int _lastShownSecond = -1;

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
    // 界面只显示到秒：秒数变化时才通知，避免每秒 4 次无意义的重建
    _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      final second = elapsedMs ~/ 1000;
      if (second != _lastShownSecond) {
        _lastShownSecond = second;
        notifyListeners();
      }
    });
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

/// 显示用时的数据块。单独放在 RepaintBoundary 里，每秒刷新时不会连带重绘整个游戏界面。
class GameClockPill extends StatelessWidget {
  const GameClockPill({super.key, required this.clock});

  final GameClock clock;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: clock,
        builder: (_, _) => StatPill(
          icon: Icons.timer_outlined,
          label: '用时',
          value: formatDuration(clock.elapsedMs),
        ),
      ),
    );
  }
}
