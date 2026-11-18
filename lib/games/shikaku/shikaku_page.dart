import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/chunky.dart';
import '../game_clock.dart';
import '../game_definition.dart';
import 'shikaku_logic.dart';

const _rectColors = <Color>[
  Color(0xFFA6F0D0),
  Color(0xFFFFE680),
  Color(0xFFA8DCFF),
  Color(0xFFD5C4FF),
  Color(0xFFFFC2D9),
  Color(0xFFFFC7A6),
  Color(0xFFCCF09D),
];

class ShikakuGameView extends StatefulWidget {
  const ShikakuGameView({super.key, required this.session});

  final GameSession session;

  static ({int size, int maxArea}) configFor(String modeId) => switch (modeId) {
    'sk5' => (size: 5, maxArea: 6),
    'sk6' => (size: 6, maxArea: 8),
    'sk7' => (size: 7, maxArea: 9),
    'sk8' => (size: 8, maxArea: 12),
    'sk9' => (size: 9, maxArea: 12),
    'sk10' => (size: 10, maxArea: 15),
    _ => (size: 6, maxArea: 8),
  };

  @override
  State<ShikakuGameView> createState() => _ShikakuGameViewState();
}

class _ShikakuGameViewState extends State<ShikakuGameView> {
  late final ShikakuPuzzle _puzzle;
  late final GameClock _clock;

  bool _picking = false;
  (int, int)? _dragStart;
  (int, int)? _dragCurrent;

  ShikakuRect? get _preview {
    final s = _dragStart, e = _dragCurrent;
    if (s == null || e == null) return null;
    return ShikakuRect.fromCorners(s.$1, s.$2, e.$1, e.$2);
  }

  @override
  void initState() {
    super.initState();
    final cfg = ShikakuGameView.configFor(widget.session.mode.id);
    final saved = widget.session.savedState;
    ShikakuPuzzle? restored;
    if (saved != null) {
      try {
        final p = ShikakuPuzzle.fromJson(
          (saved['puzzle'] as Map).cast<String, dynamic>(),
        );
        if (p.size == cfg.size) restored = p;
      } catch (_) {
        // 存档损坏或格式变化：直接开新局
      }
    }
    _puzzle =
        restored ??
        ShikakuPuzzle.generate(
          cfg.size,
          maxArea: cfg.maxArea,
          random: widget.session.createRandom(),
        );
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
    _clock.dispose();
    super.dispose();
  }

  (int, int) _clampedCell(Offset pos, double cell) {
    final n = _puzzle.size;
    final c = (pos.dx / cell).floor().clamp(0, n - 1);
    final r = (pos.dy / cell).floor().clamp(0, n - 1);
    return (r, c);
  }

  (int, int)? _exactCell(Offset pos, double cell) {
    final n = _puzzle.size;
    final c = (pos.dx / cell).floor(), r = (pos.dy / cell).floor();
    if (r < 0 || c < 0 || r >= n || c >= n) return null;
    return (r, c);
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

  void _useHint(int r, int c) {
    final haptics = AppScope.of(context).haptics;
    if (!_puzzle.applyHint(r * _puzzle.size + c)) {
      haptics.error();
      return;
    }
    haptics.success();
    setState(() => _picking = false);
    _afterChange();
  }

  void _onPanStart(DragStartDetails d, double cell) {
    if (_picking || _puzzle.solved) return;
    final rc = _exactCell(d.localPosition, cell);
    if (rc == null) return;
    setState(() {
      _dragStart = rc;
      _dragCurrent = rc;
    });
  }

  void _onPanUpdate(DragUpdateDetails d, double cell) {
    if (_picking || _puzzle.solved || _dragStart == null) return;
    final rc = _clampedCell(d.localPosition, cell);
    if (rc == _dragCurrent) return;
    AppScope.of(context).haptics.tap();
    setState(() => _dragCurrent = rc);
  }

  void _onPanEnd() {
    final rect = _preview;
    _dragStart = null;
    _dragCurrent = null;
    if (rect == null || _puzzle.solved) {
      setState(() {});
      return;
    }
    final haptics = AppScope.of(context).haptics;
    // 单格轻点（或未拖出范围）：取消该处已有的矩形
    if (rect.area == 1) {
      final removed = _puzzle.removeAt(rect.r1, rect.c1);
      setState(() {});
      if (removed) {
        haptics.tap();
        _save();
      }
      return;
    }
    final placed = _puzzle.place(rect);
    setState(() {});
    if (!placed) {
      haptics.error();
      return;
    }
    _puzzle.isRectValid(rect) ? haptics.light() : haptics.tap();
    _afterChange();
  }

  void _onPanCancel() {
    if (_dragStart == null) return;
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
  }

  void _onTapUp(TapUpDetails d, double cell) {
    final rc = _exactCell(d.localPosition, cell);
    if (rc == null || _puzzle.solved) return;
    if (_picking) {
      _useHint(rc.$1, rc.$2);
      return;
    }
    if (_puzzle.removeAt(rc.$1, rc.$2)) {
      AppScope.of(context).haptics.tap();
      setState(() {});
      _save();
    }
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
          ('矩形数', '${_puzzle.clueCount} 块'),
          if (hints > 0) ('使用提示', '$hints 次'),
        ],
      ),
    );
  }

  String get _status {
    if (_puzzle.solved) return '分割完成！';
    if (_picking) return '点任意一格，画出并锁定覆盖它的正确矩形';
    if (_preview case final p? when p.area > 1) {
      return '正在框选：${p.width}×${p.height} = ${p.area} 格';
    }
    return '拖动框出矩形（面积 = 数字），点击已有矩形可清除';
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
                icon: Icons.grid_view_rounded,
                label: '矩形',
                value: '${p.validRectCount}/${p.clueCount}',
                color: p.solved ? AppColors.mint : AppColors.paper,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) {
                  const pad = 8.0;
                  final side = min(c.maxWidth, c.maxHeight);
                  final inner = side - pad * 2;
                  final cell = inner / p.size;
                  return RepaintBoundary(
                    child: Container(
                      width: side,
                      height: side,
                      padding: const EdgeInsets.all(pad - AppDims.border),
                      decoration: chunkyDecoration(
                        color: AppColors.paper,
                        radius: 20,
                      ),
                      child: GestureDetector(
                        key: const ValueKey('shikaku-board'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onPanStart: (d) => _onPanStart(d, cell),
                        onPanUpdate: (d) => _onPanUpdate(d, cell),
                        onPanEnd: (_) => _onPanEnd(),
                        onPanCancel: _onPanCancel,
                        onTapUp: (d) => _onTapUp(d, cell),
                        child: CustomPaint(
                          size: Size.square(inner),
                          painter: _ShikakuPainter(
                            size: p.size,
                            clues: p.clues,
                            rects: p.rects,
                            validFlags: [
                              for (final r in p.rects) p.isRectValid(r),
                            ],
                            hintedFlags: [
                              for (final r in p.rects) p.isHinted(r),
                            ],
                            preview: _preview,
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
                enabled: !p.solved && (_picking || p.hintsLeft > 0),
                onTap: _toggleHintMode,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _status,
                  style: AppText.caption.copyWith(
                    color: _picking || (_preview != null && _preview!.area > 1)
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

class _ShikakuPainter extends CustomPainter {
  _ShikakuPainter({
    required this.size,
    required this.clues,
    required this.rects,
    required this.validFlags,
    required this.hintedFlags,
    required this.preview,
    required this.picking,
  });

  final int size;
  final List<int> clues;
  final List<ShikakuRect> rects;
  final List<bool> validFlags;
  final List<bool> hintedFlags;
  final ShikakuRect? preview;
  final bool picking;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final cell = canvasSize.width / size;
    final gridPaint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.14)
      ..strokeWidth = 1;

    // 1. 基础细网格线
    for (var i = 0; i <= size; i++) {
      final p = i * cell;
      canvas.drawLine(Offset(p, 0), Offset(p, canvasSize.height), gridPaint);
      canvas.drawLine(Offset(0, p), Offset(canvasSize.width, p), gridPaint);
    }

    // 2. 已划出的矩形
    for (var idx = 0; idx < rects.length; idx++) {
      final r = rects[idx];
      final valid = validFlags[idx];
      final hinted = hintedFlags[idx];
      final colorIdx =
          (r.r1 * 7 + r.c1 * 3 + r.r2 * 5 + r.c2) % _rectColors.length;
      final baseColor = valid
          ? _rectColors[colorIdx]
          : AppColors.coral.withValues(alpha: 0.32);
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          r.c1 * cell + 2,
          r.r1 * cell + 2,
          r.width * cell - 4,
          r.height * cell - 4,
        ),
        Radius.circular(max(5, cell * 0.16)),
      );
      canvas.drawRRect(box, Paint()..color = baseColor);
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = valid ? 2.2 : 1.8
          ..color = valid ? AppColors.ink : AppColors.coral,
      );
      if (hinted) {
        canvas.drawCircle(
          Offset((r.c2 + 0.82) * cell, (r.r1 + 0.18) * cell),
          max(2.6, cell * 0.055),
          Paint()..color = AppColors.ink,
        );
      }
    }

    // 3. 拖动预览框
    if (preview case final p? when p.area > 1) {
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          p.c1 * cell + 1.5,
          p.r1 * cell + 1.5,
          p.width * cell - 3,
          p.height * cell - 3,
        ),
        Radius.circular(max(5, cell * 0.16)),
      );
      canvas.drawRRect(
        box,
        Paint()..color = AppColors.sky.withValues(alpha: 0.36),
      );
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = AppColors.ink,
      );
    }

    // 4. 提示选格边框
    if (picking) {
      final pickPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppColors.sky;
      for (var i = 0; i < size * size; i++) {
        final r = i ~/ size, c = i % size;
        canvas.drawRect(
          Rect.fromLTWH(c * cell + 2, r * cell + 2, cell - 4, cell - 4),
          pickPaint,
        );
      }
    }

    // 5. 数字线索
    final fontSize = (cell * 0.44).clamp(11.0, 22.0);
    for (var i = 0; i < clues.length; i++) {
      final v = clues[i];
      if (v <= 0) continue;
      final r = i ~/ size, c = i % size;
      final tp = TextPainter(
        text: TextSpan(
          text: '$v',
          style: AppText.number.copyWith(fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (c + 0.5) * cell - tp.width / 2,
          (r + 0.5) * cell - tp.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_ShikakuPainter old) =>
      old.picking != picking ||
      old.preview != preview ||
      !listEquals(old.rects, rects) ||
      !listEquals(old.validFlags, validFlags) ||
      !listEquals(old.hintedFlags, hintedFlags);
}

/// 首页卡片插图
class ShikakuCover extends StatelessWidget {
  const ShikakuCover({super.key});

  @override
  Widget build(BuildContext context) {
    const rects = [
      ShikakuRect(0, 0, 0, 2),
      ShikakuRect(1, 0, 2, 1),
      ShikakuRect(1, 2, 2, 2),
    ];
    return Container(
      color: AppColors.paper,
      padding: const EdgeInsets.all(7),
      child: CustomPaint(
        painter: _ShikakuPainter(
          size: 3,
          clues: const [
            0, 3, 0, //
            4, 0, 2,
            0, 0, 0,
          ],
          rects: rects,
          validFlags: const [true, true, true],
          hintedFlags: const [false, false, false],
          preview: null,
          picking: false,
        ),
      ),
    );
  }
}
