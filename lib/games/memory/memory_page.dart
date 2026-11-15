import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/data/models/score_kind.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/chunky.dart';
import '../game_clock.dart';
import '../game_definition.dart';
import 'memory_logic.dart';

/// 卡面图案：图标 + 底色。数量必须 >= [MemoryGame.symbolPool]。
const _faces = <(IconData, Color)>[
  (Icons.favorite_rounded, Color(0xFFFF8E9E)),
  (Icons.star_rounded, Color(0xFFFFD84D)),
  (Icons.bolt_rounded, Color(0xFFFFB766)),
  (Icons.pets_rounded, Color(0xFFD9B38C)),
  (Icons.local_florist_rounded, Color(0xFFFFA6C9)),
  (Icons.eco_rounded, Color(0xFFA8E06A)),
  (Icons.cake_rounded, Color(0xFFFFC2D4)),
  (Icons.music_note_rounded, Color(0xFFB9A3FF)),
  (Icons.anchor_rounded, Color(0xFF7CCBFF)),
  (Icons.beach_access_rounded, Color(0xFFFF8E72)),
  (Icons.cloud_rounded, Color(0xFFBFE3FF)),
  (Icons.icecream_rounded, Color(0xFFFFE0A3)),
  (Icons.rocket_launch_rounded, Color(0xFFE0B8FF)),
  (Icons.sailing_rounded, Color(0xFF8FE3E8)),
  (Icons.wb_sunny_rounded, Color(0xFFFFE066)),
  (Icons.nightlight_round, Color(0xFFC7C2FF)),
  (Icons.diamond_rounded, Color(0xFF7FDDB8)),
  (Icons.spa_rounded, Color(0xFFCDEB9C)),
];

class MemoryGameView extends StatefulWidget {
  const MemoryGameView({super.key, required this.session});

  final GameSession session;

  /// (列数, 行数)
  static (int, int) gridFor(String modeId) => switch (modeId) {
    'easy' => (3, 4),
    'hard' => (5, 6),
    _ => (4, 4),
  };

  @override
  State<MemoryGameView> createState() => _MemoryGameViewState();
}

class _MemoryGameViewState extends State<MemoryGameView> {
  late final (int, int) _grid = MemoryGameView.gridFor(widget.session.mode.id);
  late final MemoryGame _game = MemoryGame(pairs: _grid.$1 * _grid.$2 ~/ 2);
  final GameClock _clock = GameClock();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _flip(int i) {
    final haptics = AppScope.of(context).haptics;
    final outcome = _game.flip(i);
    if (outcome == FlipOutcome.ignored) return;
    _clock.start();
    setState(() {});

    switch (outcome) {
      case FlipOutcome.first:
        haptics.tap();
      case FlipOutcome.match:
        haptics.light();
        if (_game.completed) _finish();
      case FlipOutcome.mismatch:
        haptics.tap();
        Future<void>.delayed(const Duration(milliseconds: 750), () {
          if (!mounted) return;
          setState(_game.hideMismatch);
        });
      case FlipOutcome.ignored:
        break;
    }
  }

  void _finish() {
    _clock.stop();
    widget.session.onFinish(
      GameFinish(
        won: true,
        score: _game.moves,
        durationMs: _clock.elapsedMs,
        details: [
          ('用时', formatDuration(_clock.elapsedMs)),
          ('最高连击', '×${_game.bestCombo}'),
          ('评价', '★' * _game.stars + '☆' * (3 - _game.stars)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (cols, rows) = _grid;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              StatPill(
                icon: Icons.touch_app_outlined,
                label: '步数',
                value: '${_game.moves}',
              ),
              const SizedBox(width: 10),
              ListenableBuilder(
                listenable: _clock,
                builder: (_, _) => StatPill(
                  icon: Icons.timer_outlined,
                  label: '用时',
                  value: formatDuration(_clock.elapsedMs),
                ),
              ),
              const Spacer(),
              StatPill(
                icon: Icons.style_outlined,
                label: '配对',
                value: '${_game.matchedPairs}/${_game.pairs}',
                color: _game.completed ? AppColors.pink : AppColors.paper,
              ),
            ],
          ),
          SizedBox(
            height: 36,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: CurvedAnimation(
                    parent: anim,
                    curve: Curves.easeOutBack,
                  ),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: _game.combo >= 2
                    ? TagChip(
                        key: ValueKey(_game.combo),
                        label: '连击 ×${_game.combo}',
                        color: AppColors.lemon,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                const gap = 10.0;
                const aspect = 0.78; // 宽 / 高
                final byWidth = (c.maxWidth - gap * (cols - 1)) / cols;
                final byHeight =
                    ((c.maxHeight - gap * (rows - 1)) / rows) * aspect;
                final w = min(byWidth, byHeight);
                final h = w / aspect;
                return Center(
                  child: SizedBox(
                    width: w * cols + gap * (cols - 1),
                    height: h * rows + gap * (rows - 1),
                    child: Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (var i = 0; i < _game.cards.length; i++)
                          SizedBox(
                            width: w,
                            height: h,
                            child: _FlipCard(
                              card: _game.cards[i],
                              onTap: () => _flip(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FlipCard extends StatelessWidget {
  const _FlipCard({required this.card, required this.onTap});

  final MemoryCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showFront = card.faceUp || card.matched;
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: showFront ? pi : 0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        builder: (context, angle, _) {
          final front = angle > pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            child: front
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(pi),
                    child: _Front(card: card),
                  )
                : const _Back(),
          );
        },
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: chunkyDecoration(color: AppColors.ink, radius: 14, shadow: 3),
      child: LayoutBuilder(
        builder: (context, c) => CustomPaint(
          painter: _BackPatternPainter(),
          child: Center(
            child: Container(
              width: c.maxWidth * 0.42,
              height: c.maxWidth * 0.42,
              decoration: BoxDecoration(
                color: AppColors.pink,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cream, width: 2),
              ),
              child: Icon(
                Icons.question_mark_rounded,
                color: AppColors.ink,
                size: c.maxWidth * 0.26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF3A3352);
    const step = 10.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BackPatternPainter oldDelegate) => false;
}

class _Front extends StatelessWidget {
  const _Front({required this.card});

  final MemoryCard card;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _faces[card.symbol % _faces.length];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: chunkyDecoration(
        color: card.matched ? color : AppColors.paper,
        radius: 14,
        shadow: card.matched ? 0 : 3,
      ),
      child: LayoutBuilder(
        builder: (context, c) => Center(
          child: Container(
            width: c.maxWidth * 0.66,
            height: c.maxWidth * 0.66,
            decoration: BoxDecoration(
              color: card.matched ? AppColors.paper : color,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.ink, width: 2),
            ),
            child: Icon(icon, size: c.maxWidth * 0.4, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

/// 首页卡片插图
class MemoryCover extends StatelessWidget {
  const MemoryCover({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pink,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: const Offset(-12, 2),
            child: Transform.rotate(
              angle: -0.22,
              child: const SizedBox(width: 40, height: 52, child: _Back()),
            ),
          ),
          Transform.translate(
            offset: const Offset(13, -2),
            child: Transform.rotate(
              angle: 0.18,
              child: SizedBox(
                width: 40,
                height: 52,
                child: _Front(card: MemoryCard(1)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
