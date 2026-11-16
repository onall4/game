import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/chunky.dart';
import '../game_clock.dart';
import '../game_definition.dart';
import 'circuit_logic.dart';

const _powerColor = AppColors.lemon;
const _idleColor = Color(0xFF6E6690);

class CircuitGame extends StatefulWidget {
  const CircuitGame({super.key, required this.session});

  final GameSession session;

  /// 模式 ID → 边长。'normal' 沿用旧 ID，保留 6×6 的历史纪录。
  static int sizeFor(String modeId) => switch (modeId) {
    'size4' => 4,
    'size8' => 8,
    'size10' => 10,
    _ => 6,
  };

  @override
  State<CircuitGame> createState() => _CircuitGameState();
}

class _CircuitGameState extends State<CircuitGame> {
  late final CircuitPuzzle _puzzle;
  late final GameClock _clock;

  @override
  void initState() {
    super.initState();
    final size = CircuitGame.sizeFor(widget.session.mode.id);
    final saved = widget.session.savedState;
    CircuitPuzzle? restored;
    if (saved != null) {
      try {
        final p = CircuitPuzzle.fromJson(
          (saved['puzzle'] as Map).cast<String, dynamic>(),
        );
        if (p.size == size) restored = p;
      } catch (_) {
        // 存档损坏或格式变化：直接开新局
      }
    }
    _puzzle = restored ?? CircuitPuzzle.generate(size);
    _clock = GameClock(
      initialElapsedMs: restored == null ? 0 : saved!['elapsedMs'] as int? ?? 0,
    );
    // 用时从进入游戏开始算；已完成的对局停在最终用时
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

  void _onTap(int i) {
    if (_puzzle.solved) return;
    final haptics = AppScope.of(context).haptics;
    if (_puzzle.isLocked(i)) {
      haptics.error();
      return;
    }
    final before = _puzzle.poweredCount;
    setState(() => _puzzle.rotate(i));
    _puzzle.poweredCount > before ? haptics.light() : haptics.tap();
    if (_puzzle.solved) _clock.stop();
    _save();
    if (_puzzle.solved) {
      widget.session.onFinish(
        GameFinish(
          won: true,
          score: _clock.elapsedMs,
          durationMs: _clock.elapsedMs,
          details: [('旋转次数', '${_puzzle.moves}')],
        ),
      );
    }
  }

  void _onLongPress(int i) {
    if (_puzzle.solved) return;
    AppScope.of(context).haptics.light();
    setState(() => _puzzle.toggleLock(i));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          StatBar(
            children: [
              GameClockPill(clock: _clock),
              StatPill(
                icon: Icons.rotate_right_rounded,
                label: '旋转',
                value: '${_puzzle.moves}',
              ),
              StatPill(
                icon: Icons.bolt_rounded,
                label: '通电',
                value: '${_puzzle.poweredCount}/${_puzzle.cellCount}',
                color: _puzzle.solved ? AppColors.lemon : AppColors.paper,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) {
                  final side = min(c.maxWidth, c.maxHeight);
                  return SizedBox(
                    width: side,
                    height: side,
                    // 棋盘单独成层：计时器、顶部数据变化时不重绘棋盘
                    child: RepaintBoundary(
                      child: _Board(
                        puzzle: _puzzle,
                        onTap: _onTap,
                        onLongPress: _onLongPress,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _puzzle.solved ? '全部点亮！' : '点击旋转导线 · 长按锁定格子',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.puzzle,
    required this.onTap,
    required this.onLongPress,
  });

  final CircuitPuzzle puzzle;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onLongPress;

  @override
  Widget build(BuildContext context) {
    final n = puzzle.size;
    // 大棋盘（8×8 起）收紧边距和格间距，把空间留给格子本身
    final gap = n >= 8 ? 2.0 : 3.0;
    return Container(
      padding: EdgeInsets.all(n >= 8 ? 6 : 8),
      decoration: chunkyDecoration(color: AppColors.board, radius: 22),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: n,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
        ),
        itemCount: n * n,
        itemBuilder: (context, i) => _Tile(
          key: ValueKey(i),
          mask: puzzle.baseMask(i),
          turns: puzzle.turnsAt(i),
          powered: puzzle.isPowered(i),
          locked: puzzle.isLocked(i),
          isSource: i == puzzle.source,
          isEndpoint: puzzle.isEndpoint(i),
          solved: puzzle.solved,
          onTap: () => onTap(i),
          onLongPress: () => onLongPress(i),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.mask,
    required this.turns,
    required this.powered,
    required this.locked,
    required this.isSource,
    required this.isEndpoint,
    required this.solved,
    required this.onTap,
    required this.onLongPress,
  });

  final int mask;
  final int turns;
  final bool powered;
  final bool locked;
  final bool isSource;
  final bool isEndpoint;
  final bool solved;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: locked
              ? const Color(0xFF4A4268)
              : solved
              ? const Color(0xFF3D3560)
              : AppColors.boardCell,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedRotation(
              turns: turns / 4,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              child: CustomPaint(
                painter: _WirePainter(
                  mask: mask,
                  powered: powered,
                  isSource: isSource,
                  isEndpoint: isEndpoint,
                ),
              ),
            ),
            if (isSource)
              const Center(
                child: FractionallySizedBox(
                  widthFactor: 0.34,
                  heightFactor: 0.34,
                  child: FittedBox(
                    child: Icon(Icons.bolt_rounded, color: AppColors.ink),
                  ),
                ),
              ),
            if (locked)
              const Positioned(
                right: 3,
                top: 3,
                child: Icon(
                  Icons.lock_rounded,
                  size: 11,
                  color: Color(0xFFB9B0DA),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WirePainter extends CustomPainter {
  _WirePainter({
    required this.mask,
    required this.powered,
    required this.isSource,
    required this.isEndpoint,
  });

  final int mask;
  final bool powered;
  final bool isSource;
  final bool isEndpoint;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final width = s * 0.2;
    final color = powered ? _powerColor : _idleColor;

    final ends = <Offset>[
      if (mask & Dir.up != 0) Offset(c.dx, -1),
      if (mask & Dir.right != 0) Offset(size.width + 1, c.dy),
      if (mask & Dir.down != 0) Offset(c.dx, size.height + 1),
      if (mask & Dir.left != 0) Offset(-1, c.dy),
    ];

    // 通电光晕：贴预先模糊好的位图（见 _GlowCache），不在每帧实时模糊。
    if (powered) {
      _GlowCache.paint(canvas, c, s, mask, isEndpoint);
    }

    final wire = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    for (final e in ends) {
      canvas.drawLine(c, e, wire);
    }
    // 中心接头
    canvas.drawCircle(c, width / 2, Paint()..color = color);

    if (isSource) {
      final r = s * 0.3;
      canvas.drawCircle(c, r, Paint()..color = _powerColor);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    } else if (isEndpoint) {
      final r = s * 0.22;
      canvas.drawCircle(
        c,
        r,
        Paint()..color = powered ? _powerColor : AppColors.boardCell,
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = powered ? AppColors.ink : _idleColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_WirePainter old) =>
      old.mask != mask ||
      old.powered != powered ||
      old.isSource != isSource ||
      old.isEndpoint != isEndpoint;
}

/// 通电光晕的位图缓存。
///
/// 光晕需要高斯模糊（MaskFilter.blur），代价很高；而 Impeller 渲染器不会
/// 自动缓存绘制结果，通电格子一多，进出页面的每一帧都要做上百次模糊，导致卡顿。
/// 这里每种「形状 × 尺寸」只模糊一次生成位图，之后直接贴图，外观与实时模糊一致。
abstract final class _GlowCache {
  /// 模糊会溢出格子边界，位图四周留出的余量（逻辑像素）。
  static const _pad = 12.0;
  static const _maxEntries = 96;
  static final Map<(int, int), ui.Image> _images = {};

  static void paint(
    Canvas canvas,
    Offset center,
    double size,
    int mask,
    bool endpoint,
  ) {
    final key = (mask | (endpoint ? 16 : 0), (size * 4).round());
    var image = _images[key];
    if (image == null) {
      if (_images.length >= _maxEntries) {
        for (final img in _images.values) {
          img.dispose();
        }
        _images.clear();
      }
      image = _images[key] = _render(size, mask, endpoint);
    }
    final full = size + _pad * 2;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: center, width: full, height: full),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  static ui.Image _render(double size, int mask, bool endpoint) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(size / 2 + _pad, size / 2 + _pad);
    final width = size * 0.2;
    final glow = Paint()
      ..color = _powerColor.withValues(alpha: 0.35)
      ..strokeWidth = width * 1.9
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final half = size / 2 + 1;
    for (final (d, dx, dy) in const [
      (Dir.up, 0, -1),
      (Dir.right, 1, 0),
      (Dir.down, 0, 1),
      (Dir.left, -1, 0),
    ]) {
      if (mask & d != 0) {
        canvas.drawLine(c, c + Offset(dx * half, dy * half), glow);
      }
    }
    if (endpoint) {
      canvas.drawCircle(
        c,
        size * 0.22 * 1.6,
        Paint()
          ..color = _powerColor.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    final picture = recorder.endRecording();
    final px = (size + _pad * 2).ceil();
    final image = picture.toImageSync(px, px);
    picture.dispose();
    return image;
  }
}

/// 首页卡片插图
class CircuitCover extends StatelessWidget {
  const CircuitCover({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.board,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(6),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (final (mask, powered, src, end) in const [
            (Dir.right | Dir.down, true, false, false),
            (Dir.left | Dir.right, true, false, false),
            (Dir.left, true, false, true),
            (Dir.up | Dir.down, true, false, false),
            (Dir.up | Dir.right | Dir.down, true, true, false),
            (Dir.down, false, false, true),
            (Dir.up, true, false, true),
            (Dir.up | Dir.right, true, false, false),
            (Dir.left | Dir.up, false, false, false),
          ])
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.boardCell,
                borderRadius: BorderRadius.circular(4),
              ),
              child: CustomPaint(
                painter: _WirePainter(
                  mask: mask,
                  powered: powered,
                  isSource: src,
                  isEndpoint: end,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
