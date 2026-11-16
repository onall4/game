import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/data/models/score_kind.dart';
import '../ui/widgets/chunky.dart';

/// 游戏计时器：首次操作时开始，应用切到后台自动暂停。
///
/// 继续上一局时传入 [initialElapsedMs]，从上次的用时接着计。
/// [resolutionMs] 是界面显示的精度：显示的数字变化时才通知刷新。
class GameClock extends ChangeNotifier with WidgetsBindingObserver {
  GameClock({int initialElapsedMs = 0, this.resolutionMs = 1000})
    : _initialMs = initialElapsedMs {
    WidgetsBinding.instance.addObserver(this);
  }

  final int _initialMs;
  final int resolutionMs;
  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;
  bool _started = false;
  bool _stopped = false;
  int _lastShownTick = -1;

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
    // 显示的数字变化时才通知，避免无意义的重建
    final period = resolutionMs >= 1000 ? 250 : max(16, resolutionMs ~/ 2);
    _ticker ??= Timer.periodic(Duration(milliseconds: period), (_) {
      final tick = elapsedMs ~/ resolutionMs;
      if (tick != _lastShownTick) {
        _lastShownTick = tick;
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
  const GameClockPill({
    super.key,
    required this.clock,
    this.format = formatDuration,
    this.extraMs = 0,
  });

  final GameClock clock;
  final String Function(int ms) format;

  /// 额外计入的时间（如点错的罚时）。
  final int extraMs;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: clock,
        builder: (_, _) => StatPill(
          icon: Icons.timer_outlined,
          label: '用时',
          value: format(clock.elapsedMs + extraMs),
        ),
      ),
    );
  }
}
