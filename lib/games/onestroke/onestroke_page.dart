import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/chunky.dart';
import '../game_clock.dart';
import '../game_definition.dart';
import 'onestroke_logic.dart';

/// 一种难度：棋盘大小与障碍数量范围。
typedef OneStrokeConfig = ({int cols, int rows, int minWalls, int maxWalls});

class OneStrokeGameView extends StatefulWidget {
  const OneStrokeGameView({super.key, required this.session});

  final GameSession session;

  static OneStrokeConfig configFor(String modeId) => switch (modeId) {
    'o4' => (cols: 4, rows: 4, minWalls: 1, maxWalls: 2),
    'o6' => (cols: 6, rows: 6, minWalls: 3, maxWalls: 5),
    'o7' => (cols: 7, rows: 7, minWalls: 4, maxWalls: 6),
    'o8' => (cols: 8, rows: 8, minWalls: 5, maxWalls: 8),
    'o9' => (cols: 9, rows: 9, minWalls: 7, maxWalls: 10),
    _ => (cols: 5, rows: 5, minWalls: 2, maxWalls: 3),
  };

  @override
  State<OneStrokeGameView> createState() => _OneStrokeGameViewState();
}

class _OneStrokeGameViewState extends State<OneStrokeGameView> {
  late final OneStrokePuzzle _puzzle;
  late final GameClock _clock;

  /// 拖动时上一次处理到的位置与格子，用来补上手指划得太快时跳过的格子。
  Offset? _lastPos;
  int? _lastCell;

  /// 正在使用提示：等玩家点选要看走向的格子。
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final config = OneStrokeGameView.configFor(widget.session.mode.id);
    final saved = widget.session.savedState;
    OneStrokePuzzle? restored;
    if (saved != null) {
      try {
        final p = OneStrokePuzzle.fromJson(
          (saved['puzzle'] as Map).cast<String, dynamic>(),
        );
        if (p.cols == config.cols && p.rows == config.rows) restored = p;
      } catch (_) {
        // 存档损坏或格式变化：直接开新局
      }
    }
    _puzzle =
        restored ??
        OneStrokePuzzle.generate(
          cols: config.cols,
          rows: config.rows,
          minWalls: config.minWalls,
          maxWalls: config.maxWalls,
          random: widget.session.createRandom(),
        );
    _clock = widget.session.createClock(
      initialElapsedMs: restored == null ? 0 : saved!['elapsedMs'] as int? ?? 0,
      onBackground: _save,
    );
    // 用时从进入游戏开始算；已完成的对局停在最终用时
    if (!_puzzle.completed) _clock.start();
  }

  void _save() {
    widget.session.saveProgress({
      'elapsedMs': _clock.elapsedMs,
      'puzzle': _puzzle.toJson(),
    });
  }

  @override
  void dispose() {
    _save();
    _clock.dispose();
    super.dispose();
  }

  int? _cellAt(Offset pos, double cell) {
    final c = (pos.dx / cell).floor(), r = (pos.dy / cell).floor();
    if (c < 0 || r < 0 || c >= _puzzle.cols || r >= _puzzle.rows) return null;
    return r * _puzzle.cols + c;
  }

  /// 走到第 [i] 格（前进或退回）；返回是否有变化。
  bool _step(int i) {
    final result = _puzzle.moveTo(i);
    if (result == StrokeMove.ignored) return false;
    AppScope.of(context).haptics.tap();
    return true;
  }

  void _toggleHintMode() {
    if (_puzzle.completed) return;
    final haptics = AppScope.of(context).haptics;
    if (!_picking && _puzzle.hintsLeft <= 0) {
      haptics.error();
      return;
    }
    haptics.tap();
    setState(() => _picking = !_picking);
  }

  void _useHint(int i) {
    final haptics = AppScope.of(context).haptics;
    if (!_puzzle.applyHint(i)) {
      haptics.error(); // 障碍或已经提示过的格子
      return;
    }
    haptics.success();
    setState(() => _picking = false);
    _save();
  }

  void _onPanStart(DragStartDetails d, double cell) {
    if (_picking) return;
    final i = _cellAt(d.localPosition, cell);
    _lastPos = d.localPosition;
    _lastCell = i;
    if (i == null || _puzzle.completed) return;
    // 从路径中间开始拖：先截到那里，接着往下画
    if (_puzzle.truncateTo(i)) {
      AppScope.of(context).haptics.tap();
    } else if (!_step(i)) {
      return;
    }
    setState(() {});
    if (_puzzle.completed) _afterChange();
  }

  void _onPanUpdate(DragUpdateDetails d, double cell) {
    if (_picking) return;
    final from = _lastPos ?? d.localPosition;
    final to = d.localPosition;
    _lastPos = to;
    // 沿手指轨迹每 1/4 格取一个点，划得再快也不会漏格
    final steps = max(1, ((to - from).distance / (cell / 4)).ceil());
    var changed = false;
    for (var s = 1; s <= steps; s++) {
      final i = _cellAt(Offset.lerp(from, to, s / steps)!, cell);
      if (i == null || i == _lastCell) continue;
      _lastCell = i;
      if (_step(i)) changed = true;
      if (_puzzle.completed) break;
    }
    if (changed) {
      setState(() {});
      if (_puzzle.completed) _afterChange();
    }
  }

  void _onPanEnd() {
    _lastPos = null;
    _lastCell = null;
    _save();
  }

  void _onTapUp(TapUpDetails d, double cell) {
    final i = _cellAt(d.localPosition, cell);
    if (i == null) return;
    if (_picking) {
      _useHint(i);
      return;
    }
    if (_puzzle.truncateTo(i)) {
      AppScope.of(context).haptics.tap();
    } else if (!_step(i)) {
      return;
    }
    setState(() {});
    _afterChange();
  }

  /// 每次路径变化后：保存；走遍了就结算。
  void _afterChange() {
    final done = _puzzle.completed;
    if (done) {
      _clock.stop();
      _picking = false;
    }
    _save();
    if (!done) return;
    final hints = _puzzle.hintsUsed;
    widget.session.onFinish(
      GameFinish(
        won: true,
        score: _clock.elapsedMs,
        durationMs: _clock.elapsedMs,
        assisted: hints > 0,
        details: [
          ('格子', '${_puzzle.openCount} 格'),
          if (hints > 0) ('使用提示', '$hints 次'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _puzzle;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          StatBar(
            children: [
              GameClockPill(clock: _clock),
              StatPill(
                icon: Icons.gesture_rounded,
                label: '进度',
                value: '${p.path.length}/${p.openCount}',
                color: p.completed ? AppColors.lemon : AppColors.paper,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) {
                  const pad = 8.0;
                  final cell = min(
                    (c.maxWidth - pad * 2) / p.cols,
                    (c.maxHeight - pad * 2) / p.rows,
                  );
                  return RepaintBoundary(
                    child: Container(
                      padding: const EdgeInsets.all(pad - AppDims.border),
                      decoration: chunkyDecoration(
                        color: AppColors.creamDeep,
                        radius: 20,
                      ),
                      child: GestureDetector(
                        key: const ValueKey('onestroke-board'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onPanStart: (d) => _onPanStart(d, cell),
                        onPanUpdate: (d) => _onPanUpdate(d, cell),
                        onPanEnd: (_) => _onPanEnd(),
                        onPanCancel: _onPanEnd,
                        onTapUp: (d) => _onTapUp(d, cell),
                        child: CustomPaint(
                          size: Size(cell * p.cols, cell * p.rows),
                          painter: _BoardPainter(
                            cols: p.cols,
                            rows: p.rows,
                            walls: p.walls,
                            start: p.start,
                            path: p.path,
                            completed: p.completed,
                            hints: p.hints,
                            picking: _picking,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              HintButton(
                left: p.hintsLeft,
                picking: _picking,
                enabled: !p.completed && (_picking || p.hintsLeft > 0),
                onTap: _toggleHintMode,
              ),
              const SizedBox(width: 12),
              if (_picking)
                Expanded(
                  child: Text(
                    '答案可能不止一种，提示按同一种固定走法给出。点一个格子看它的走向',
                    style: AppText.caption.copyWith(color: AppColors.ink),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.cols,
    required this.rows,
    required this.walls,
    required this.start,
    required this.path,
    required this.completed,
    this.hints = const {},
    this.picking = false,
  });

  final int cols;
  final int rows;
  final List<bool> walls;
  final int start;
  final List<int> path;
  final bool completed;

  /// 已提示的格子及参考路线在那里的走向。
  final Map<int, ({int? from, int? to})> hints;

  /// 正在选提示格子：可选的格子描蓝边。
  final bool picking;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cols;
    final gap = max(2.0, cell * 0.07);
    final radius = Radius.circular(cell * 0.2);
    final visited = path.toSet();
    Offset center(int i) =>
        Offset((i % cols + 0.5) * cell, (i ~/ cols + 0.5) * cell);

    final fill = Paint();
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, cell * 0.04)
      ..color = AppColors.ink;
    final pickBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = border.strokeWidth * 2
      ..color = AppColors.sky;
    for (var i = 0; i < cols * rows; i++) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (i % cols) * cell + gap / 2,
          (i ~/ cols) * cell + gap / 2,
          cell - gap,
          cell - gap,
        ),
        radius,
      );
      if (walls[i]) {
        canvas.drawRRect(
          rect,
          fill..color = AppColors.ink.withValues(alpha: 0.78),
        );
        continue;
      }
      fill.color = visited.contains(i) ? AppColors.lemon : AppColors.paper;
      canvas.drawRRect(rect, fill);
      if (picking && !hints.containsKey(i)) {
        canvas.drawRRect(rect.deflate(border.strokeWidth / 2), pickBorder);
      } else {
        canvas.drawRRect(rect, border);
      }
    }

    // 提示：参考路线在这格的走向，蓝色线段 + 指向前进方向的箭头
    final hintLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.24
      ..strokeCap = StrokeCap.round
      ..color = AppColors.sky;
    final arrow = Paint()..color = AppColors.ink.withValues(alpha: 0.75);
    for (final MapEntry(key: i, value: (:from, :to)) in hints.entries) {
      final c = center(i);
      for (final n in [from, to]) {
        if (n != null) {
          canvas.drawLine(c, Offset.lerp(c, center(n), 0.5)!, hintLine);
        }
      }
      if (to == null) {
        // 路线在这里结束
        canvas.drawCircle(c, cell * 0.16, Paint()..color = AppColors.sky);
        continue;
      }
      final dir = (center(to) - c) / cell;
      final normal = Offset(-dir.dy, dir.dx);
      Offset at(double along, double side) =>
          c + (dir * along + normal * side) * cell;
      canvas.drawPath(
        Path()
          ..moveTo(at(0.44, 0).dx, at(0.44, 0).dy)
          ..lineTo(at(0.24, 0.13).dx, at(0.24, 0.13).dy)
          ..lineTo(at(0.24, -0.13).dx, at(0.24, -0.13).dy)
          ..close(),
        arrow,
      );
    }

    if (path.length > 1) {
      final line = Path()..moveTo(center(path.first).dx, center(path.first).dy);
      for (final i in path.skip(1)) {
        line.lineTo(center(i).dx, center(i).dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.18
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.ink,
      );
    }
    // 起点：实心圆点；路径末端：圆环，提示从这里接着画
    canvas.drawCircle(center(start), cell * 0.17, fill..color = AppColors.ink);
    if (path.length > 1 && !completed) {
      canvas.drawCircle(
        center(path.last),
        cell * 0.22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.08
          ..color = AppColors.ink,
      );
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.completed != completed ||
      old.picking != picking ||
      !listEquals(old.path, path) ||
      !listEquals(old.walls, walls) ||
      !mapEquals(old.hints, hints);
}

/// 首页卡片插图
class OneStrokeCover extends StatelessWidget {
  const OneStrokeCover({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.lemon,
      padding: const EdgeInsets.all(10),
      child: CustomPaint(
        painter: _BoardPainter(
          cols: 3,
          rows: 3,
          walls: List.generate(9, (i) => i == 5),
          start: 6,
          path: const [6, 3, 0, 1, 4, 7, 8],
          completed: false,
        ),
      ),
    );
  }
}
