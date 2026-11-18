import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/chunky.dart';
import '../game_clock.dart';
import '../game_definition.dart';
import 'queens_logic.dart';

/// 9 种柔和区域底色，彼此区分明显且衬托深墨色皇冠与描边。
const _regionPalette = <Color>[
  Color(0xFFFFE57F),
  Color(0xFF9BE7C8),
  Color(0xFF9AD9FF),
  Color(0xFFCBB9FF),
  Color(0xFFFFB8D2),
  Color(0xFFFFAB94),
  Color(0xFFC4EA8C),
  Color(0xFFA6EBE8),
  Color(0xFFFFCF96),
  Color(0xFFE7C6FF),
];

class QueensGameView extends StatefulWidget {
  const QueensGameView({super.key, required this.session});

  final GameSession session;

  static int sizeFor(String modeId) => switch (modeId) {
    'q5' => 5,
    'q6' => 6,
    'q7' => 7,
    'q8' => 8,
    'q9' => 9,
    _ => 6,
  };

  @override
  State<QueensGameView> createState() => _QueensGameViewState();
}

class _QueensGameViewState extends State<QueensGameView> {
  static const _doubleTapWindow = Duration(milliseconds: 320);

  late final QueensPuzzle _puzzle;
  late final GameClock _clock;

  bool _picking = false;

  /// 手势跟踪：停留在按下格内抬起算点击；滑入其他格子转为批量切换 × / 空白。
  int? _downCell;
  bool _sweeping = false;
  bool _sweepCross = true;
  int? _lastSweepCell;

  /// 双击检测：单击立即切换 × / 空白，窗口期内再次点击同一格则升级为放置皇冠。
  int? _lastTapCell;
  Timer? _doubleTapTimer;

  @override
  void initState() {
    super.initState();
    final size = QueensGameView.sizeFor(widget.session.mode.id);
    final saved = widget.session.savedState;
    QueensPuzzle? restored;
    if (saved != null) {
      try {
        final p = QueensPuzzle.fromJson(
          (saved['puzzle'] as Map).cast<String, dynamic>(),
        );
        if (p.size == size) restored = p;
      } catch (_) {
        // 存档损坏或格式变化：直接开新局
      }
    }
    _puzzle =
        restored ??
        QueensPuzzle.generate(size, random: widget.session.createRandom());
    _clock = widget.session.createClock(
      initialElapsedMs: restored == null ? 0 : saved!['elapsedMs'] as int? ?? 0,
      onBackground: _save,
    );
    if (!_puzzle.solved) _clock.start();
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
    _doubleTapTimer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  void _clearDoubleTap() {
    _doubleTapTimer?.cancel();
    _doubleTapTimer = null;
    _lastTapCell = null;
  }

  int? _cellAt(Offset pos, double cell) {
    final c = (pos.dx / cell).floor(), r = (pos.dy / cell).floor();
    if (c < 0 || r < 0 || c >= _puzzle.size || r >= _puzzle.size) return null;
    return r * _puzzle.size + c;
  }

  void _toggleHintMode() {
    if (_puzzle.solved) return;
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
      haptics.error();
      return;
    }
    haptics.success();
    setState(() => _picking = false);
    _afterChange();
  }

  void _tapCell(int i) {
    if (_puzzle.solved) return;
    if (_picking) {
      _clearDoubleTap();
      _useHint(i);
      return;
    }
    final haptics = AppScope.of(context).haptics;
    if (_puzzle.isHinted(i)) {
      _clearDoubleTap();
      haptics.error();
      return;
    }

    if (_lastTapCell == i && (_doubleTapTimer?.isActive ?? false)) {
      _clearDoubleTap();
      final beforeConflicts = _puzzle.conflicts.length;
      setState(() => _puzzle.placeCrown(i));
      _puzzle.conflicts.length > beforeConflicts
          ? haptics.error()
          : haptics.light();
      _afterChange();
      return;
    }

    // 已有皇冠：单击直接取下变回空白，且不作为下一次双击的起点
    if (_puzzle.markAt(i) == QueenMark.crown) {
      _clearDoubleTap();
      setState(() => _puzzle.toggleCross(i));
      haptics.tap();
      _afterChange();
      return;
    }

    // 空白 ↔ × 立即切换，并开启短暂窗口等待可能的第二次点击（双击放皇冠）
    _doubleTapTimer?.cancel();
    _lastTapCell = i;
    _doubleTapTimer = Timer(_doubleTapWindow, () => _lastTapCell = null);
    setState(() => _puzzle.toggleCross(i));
    haptics.tap();
    _save();
  }

  void _onPanDown(DragDownDetails d, double cell) {
    if (_picking || _puzzle.solved) return;
    final i = _cellAt(d.localPosition, cell);
    _downCell = i;
    _sweeping = false;
    _lastSweepCell = i;
    if (i != null) {
      _sweepCross = _puzzle.markAt(i) != QueenMark.cross;
    }
  }

  void _onPanUpdate(DragUpdateDetails d, double cell) {
    if (_picking || _puzzle.solved) return;
    final i = _cellAt(d.localPosition, cell);
    if (i == null) return;
    if (!_sweeping) {
      if (i == _downCell) return;
      _sweeping = true;
      _clearDoubleTap();
      final first = _downCell;
      if (first != null && _puzzle.setCross(first, cross: _sweepCross)) {
        AppScope.of(context).haptics.tap();
      }
    }
    if (i != _lastSweepCell) {
      _lastSweepCell = i;
      if (_puzzle.setCross(i, cross: _sweepCross)) {
        AppScope.of(context).haptics.tap();
      }
    }
    setState(() {});
  }

  void _onPanEnd() {
    if (_sweeping) {
      _sweeping = false;
      _downCell = null;
      _lastSweepCell = null;
      _save();
      return;
    }
    final tapped = _downCell;
    _downCell = null;
    _lastSweepCell = null;
    if (tapped != null) _tapCell(tapped);
  }

  void _onPanCancel() {
    final wasSweeping = _sweeping;
    _sweeping = false;
    _downCell = null;
    _lastSweepCell = null;
    if (wasSweeping) _save();
  }

  void _onTapUp(TapUpDetails d, double cell) {
    if (_sweeping) return;
    final i = _downCell ?? _cellAt(d.localPosition, cell);
    _downCell = null;
    _lastSweepCell = null;
    if (i != null) _tapCell(i);
  }

  void _afterChange() {
    final solved = _puzzle.solved;
    if (solved) {
      _clock.stop();
      _picking = false;
    }
    _save();
    if (!solved) return;
    final hints = _puzzle.hintsUsed;
    widget.session.onFinish(
      GameFinish(
        score: _clock.elapsedMs,
        durationMs: _clock.elapsedMs,
        assisted: hints > 0,
        details: [
          ('棋盘', '${_puzzle.size}×${_puzzle.size}'),
          if (hints > 0) ('使用提示', '$hints 次'),
        ],
      ),
    );
  }

  String get _status {
    if (_puzzle.solved) return '全部就位！';
    if (_picking) return '点一格，揭晓并锁定它是皇冠还是 ×';
    if (_puzzle.conflicts.isNotEmpty) return '红框皇冠存在同行、同列、同区或相邻冲突';
    return '单击或滑动切换 ×，双击放置皇冠';
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
                icon: Icons.workspace_premium_rounded,
                label: '皇冠',
                value: '${p.crownCount}/${p.size}',
                color: p.solved
                    ? AppColors.lemon
                    : p.conflicts.isNotEmpty
                    ? AppColors.coral
                    : AppColors.paper,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) {
                  const pad = 6.0;
                  final side = min(c.maxWidth, c.maxHeight);
                  final inner = side - pad * 2;
                  final cell = inner / p.size;
                  return RepaintBoundary(
                    child: Container(
                      width: side,
                      height: side,
                      padding: const EdgeInsets.all(pad - AppDims.border),
                      decoration: chunkyDecoration(
                        color: AppColors.ink,
                        radius: 20,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: GestureDetector(
                          key: const ValueKey('queens-board'),
                          behavior: HitTestBehavior.opaque,
                          dragStartBehavior: DragStartBehavior.down,
                          onPanDown: (d) => _onPanDown(d, cell),
                          onPanUpdate: (d) => _onPanUpdate(d, cell),
                          onPanEnd: (_) => _onPanEnd(),
                          onPanCancel: _onPanCancel,
                          onTapUp: (d) => _onTapUp(d, cell),
                          child: CustomPaint(
                            size: Size.square(inner),
                            painter: _QueensBoardPainter(
                              puzzle: p,
                              picking: _picking,
                            ),
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
                enabled: !p.solved && (_picking || p.hintsLeft > 0),
                onTap: _toggleHintMode,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _status,
                  style: AppText.caption.copyWith(
                    color: _picking || p.conflicts.isNotEmpty
                        ? AppColors.ink
                        : AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QueensBoardPainter extends CustomPainter {
  _QueensBoardPainter({required this.puzzle, required this.picking})
    : _marks = [for (var i = 0; i < puzzle.cellCount; i++) puzzle.markAt(i)],
      _conflicts = Set.of(puzzle.conflicts),
      _hinted = {
        for (var i = 0; i < puzzle.cellCount; i++)
          if (puzzle.isHinted(i)) i,
      };

  final QueensPuzzle puzzle;
  final bool picking;
  final List<QueenMark> _marks;
  final Set<int> _conflicts;
  final Set<int> _hinted;

  @override
  void paint(Canvas canvas, Size size) {
    final n = puzzle.size;
    final cell = size.width / n;
    final fill = Paint();

    // 1. 区域底色与冲突高亮
    for (var i = 0; i < n * n; i++) {
      final r = i ~/ n, c = i % n;
      final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
      fill.color = _regionPalette[puzzle.regions[i] % _regionPalette.length];
      canvas.drawRect(rect, fill);
      if (_conflicts.contains(i)) {
        canvas.drawRect(
          rect.deflate(cell * 0.06),
          Paint()..color = AppColors.coral.withValues(alpha: 0.55),
        );
      }
      if (picking && !_hinted.contains(i)) {
        canvas.drawRect(
          rect.deflate(cell * 0.08),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = AppColors.ink.withValues(alpha: 0.45),
        );
      }
    }

    // 2. 同区域内部细网格线 + 跨区域粗分界线
    final thin = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    final thick = Paint()
      ..color = AppColors.ink
      ..strokeWidth = max(2.4, cell * 0.065)
      ..strokeCap = StrokeCap.square;

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final i = r * n + c;
        if (c < n - 1) {
          final x = (c + 1) * cell;
          final same = puzzle.regions[i] == puzzle.regions[i + 1];
          canvas.drawLine(
            Offset(x, r * cell),
            Offset(x, (r + 1) * cell),
            same ? thin : thick,
          );
        }
        if (r < n - 1) {
          final y = (r + 1) * cell;
          final same = puzzle.regions[i] == puzzle.regions[i + n];
          canvas.drawLine(
            Offset(c * cell, y),
            Offset((c + 1) * cell, y),
            same ? thin : thick,
          );
        }
      }
    }

    // 3. 标记（× 与皇冠）与锁定小圆点
    final crossPaint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.55)
      ..strokeWidth = max(1.8, cell * 0.055)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n * n; i++) {
      final center = Offset((i % n + 0.5) * cell, (i ~/ n + 0.5) * cell);
      switch (_marks[i]) {
        case QueenMark.empty:
          break;
        case QueenMark.cross:
          final d = cell * 0.14;
          canvas.drawLine(
            center + Offset(-d, -d),
            center + Offset(d, d),
            crossPaint,
          );
          canvas.drawLine(
            center + Offset(d, -d),
            center + Offset(-d, d),
            crossPaint,
          );
        case QueenMark.crown:
          _drawCrown(
            canvas,
            center,
            cell * 0.56,
            conflict: _conflicts.contains(i),
          );
      }
      if (_hinted.contains(i)) {
        canvas.drawCircle(
          Offset((i % n + 0.84) * cell, (i ~/ n + 0.16) * cell),
          max(2.5, cell * 0.055),
          Paint()..color = AppColors.ink,
        );
      }
    }
  }

  static void _drawCrown(
    Canvas canvas,
    Offset c,
    double s, {
    bool conflict = false,
  }) {
    final w = s * 0.46;
    final top = c.dy - s * 0.34;
    final mid = c.dy - s * 0.04;
    final bot = c.dy + s * 0.30;
    final path = Path()
      ..moveTo(c.dx - w * 0.82, bot)
      ..lineTo(c.dx - w, top + s * 0.08)
      ..lineTo(c.dx - w * 0.42, mid)
      ..lineTo(c.dx, top - s * 0.04)
      ..lineTo(c.dx + w * 0.42, mid)
      ..lineTo(c.dx + w, top + s * 0.08)
      ..lineTo(c.dx + w * 0.82, bot)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = conflict ? AppColors.coral : AppColors.paper,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.8, s * 0.09)
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.ink,
    );
  }

  @override
  bool shouldRepaint(_QueensBoardPainter old) =>
      old.picking != picking ||
      old.puzzle.size != puzzle.size ||
      !listEquals(old.puzzle.regions, puzzle.regions) ||
      !listEquals(old._marks, _marks) ||
      !setEquals(old._conflicts, _conflicts) ||
      !setEquals(old._hinted, _hinted);
}

/// 首页卡片插图
class QueensCover extends StatelessWidget {
  const QueensCover({super.key});

  @override
  Widget build(BuildContext context) {
    final puzzle =
        QueensPuzzle.fromRegions(
            size: 4,
            regions: const [
              0, 0, 1, 1, //
              0, 2, 1, 1,
              2, 2, 3, 1,
              2, 3, 3, 3,
            ],
            solution: const [1, 3, 0, 2],
          )
          ..placeCrown(1)
          ..placeCrown(7)
          ..placeCrown(8)
          ..toggleCross(5);
    return Container(
      color: AppColors.ink,
      padding: const EdgeInsets.all(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: CustomPaint(
          painter: _QueensBoardPainter(puzzle: puzzle, picking: false),
        ),
      ),
    );
  }
}
