import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/data/models/score_kind.dart';
import '../ui/widgets/chunky.dart';

/// 游戏计时器：应用切到后台、页面转场或弹出面板时自动暂停。
///
/// 继续上一局时传入 [initialElapsedMs]，从上次的用时接着计。
/// [resolutionMs] 是界面显示的精度：显示的数字变化时才通知刷新。
class GameClock extends ChangeNotifier with WidgetsBindingObserver {
  GameClock({
    int initialElapsedMs = 0,
    this.resolutionMs = 1000,
    ValueListenable<bool>? paused,
    this.onBackground,
  }) : _initialMs = initialElapsedMs,
       _pausedListenable = paused {
    WidgetsBinding.instance.addObserver(this);
    _externalPaused = paused?.value ?? false;
    _pausedListenable?.addListener(_onExternalPauseChanged);
  }

  final int _initialMs;
  final int resolutionMs;
  final ValueListenable<bool>? _pausedListenable;

  /// 应用切到后台时回调（此时计时器已暂停，适合立即保存对局进度）。
  final VoidCallback? onBackground;

  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;
  bool _started = false;
  bool _stopped = false;
  bool _appPaused = false;
  bool _externalPaused = false;
  bool _dialogPaused = false;
  int _lastShownTick = -1;

  int get elapsedMs => _initialMs + _watch.elapsedMilliseconds;
  bool get isRunning => _watch.isRunning;
  bool get started => _started;

  bool get _shouldRun =>
      _started &&
      !_stopped &&
      !_appPaused &&
      !_externalPaused &&
      !_dialogPaused;

  void start() {
    if (_started || _stopped) return;
    _started = true;
    _syncRunning();
  }

  void stop() {
    _stopped = true;
    _syncRunning();
    notifyListeners();
  }

  /// 游戏内部弹出确认框时临时暂停或恢复计时。
  void setPaused(bool value) {
    if (_dialogPaused == value) return;
    _dialogPaused = value;
    _syncRunning();
  }

  void _onExternalPauseChanged() {
    _externalPaused = _pausedListenable?.value ?? false;
    _syncRunning();
  }

  void _syncRunning() {
    if (_shouldRun) {
      if (_watch.isRunning) return;
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
    } else {
      _watch.stop();
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appPaused = false;
      _syncRunning();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      final wasActive = !_appPaused;
      _appPaused = true;
      _syncRunning();
      if (wasActive) onBackground?.call();
    }
  }

  @override
  void dispose() {
    _pausedListenable?.removeListener(_onExternalPauseChanged);
    WidgetsBinding.instance.removeObserver(this);
    _stopped = true;
    _syncRunning();
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
