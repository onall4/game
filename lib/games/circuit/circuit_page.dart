import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/data/models/score_kind.dart';
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

  static int sizeFor(String modeId) => switch (modeId) {
    'easy' => 5,
    'hard' => 7,
    _ => 6,
  };

  @override
  State<CircuitGame> createState() => _CircuitGameState();
}

class _CircuitGameState extends State<CircuitGame> {
  late final CircuitPuzzle _puzzle = CircuitPuzzle.generate(
    CircuitGame.sizeFor(widget.session.mode.id),
  );
  final GameClock _clock = GameClock();

  @override
  void dispose() {
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
    _clock.start();
    final before = _puzzle.poweredCount;
    setState(() => _puzzle.rotate(i));
    _puzzle.poweredCount > before ? haptics.light() : haptics.tap();
    if (_puzzle.solved) {
      _clock.stop();
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
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              ListenableBuilder(
                listenable: _clock,
                builder: (_, _) => StatPill(
                  icon: Icons.timer_outlined,
                  label: '用时',
                  value: formatDuration(_clock.elapsedMs),
                ),
              ),
              const SizedBox(width: 10),
              StatPill(
                icon: Icons.rotate_right_rounded,
                label: '旋转',
                value: '${_puzzle.moves}',
              ),
              const Spacer(),
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
                    child: _Board(
                      puzzle: _puzzle,
                      onTap: _onTap,
                      onLongPress: _onLongPress,
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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: chunkyDecoration(color: AppColors.board, radius: 22),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: n,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
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

    if (powered) {
      final glow = Paint()
        ..color = _powerColor.withValues(alpha: 0.35)
        ..strokeWidth = width * 1.9
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      for (final e in ends) {
        canvas.drawLine(c, e, glow);
      }
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
      if (powered) {
        canvas.drawCircle(
          c,
          r * 1.6,
          Paint()
            ..color = _powerColor.withValues(alpha: 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
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
