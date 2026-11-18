import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/data/models/score_kind.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/chunky.dart';
import '../game_clock.dart';
import '../game_definition.dart';
import 'lightsout_logic.dart';

class LightsOutGameView extends StatefulWidget {
  const LightsOutGameView({super.key, required this.session});

  final GameSession session;

  static LightsOutConfig configFor(String modeId) => switch (modeId) {
    'lo3' => const LightsOutConfig(size: 3, minSteps: 2, maxSteps: 3),
    'lo4e' => const LightsOutConfig(size: 4, minSteps: 3, maxSteps: 4),
    'lo4' => const LightsOutConfig(size: 4, minSteps: 5, maxSteps: 7),
    'lo5e' => const LightsOutConfig(size: 5, minSteps: 5, maxSteps: 7),
    'lo5' => const LightsOutConfig(size: 5, minSteps: 8, maxSteps: 12),
    'lo6' => const LightsOutConfig(size: 6, minSteps: 10, maxSteps: 16),
    _ => const LightsOutConfig(size: 4, minSteps: 5, maxSteps: 7),
  };

  @override
  State<LightsOutGameView> createState() => _LightsOutGameViewState();
}

class _LightsOutGameViewState extends State<LightsOutGameView> {
  late final LightsOutGame _game;
  late final GameClock _clock;

  @override
  void initState() {
    super.initState();
    final config = LightsOutGameView.configFor(widget.session.mode.id);
    final saved = widget.session.savedState;
    LightsOutGame? restored;
    if (saved != null) {
      try {
        restored = LightsOutGame.fromJson(
          config.size,
          (saved['game'] as Map).cast<String, dynamic>(),
        );
      } catch (_) {
        // 存档损坏或格式变化：直接开新局
      }
    }
    _game =
        restored ??
        LightsOutGame.generate(config, random: widget.session.createRandom());
    _clock = widget.session.createClock(
      initialElapsedMs: restored == null ? 0 : saved!['elapsedMs'] as int? ?? 0,
      onBackground: _save,
    );
    if (!_game.solved) _clock.start();
  }

  void _save() {
    widget.session.saveProgress({
      'elapsedMs': _clock.elapsedMs,
      'game': _game.toJson(),
    });
  }

  @override
  void dispose() {
    _save();
    _clock.dispose();
    super.dispose();
  }

  void _tap(int i) {
    if (_game.solved) return;
    final haptics = AppScope.of(context).haptics;
    setState(() => _game.toggle(i));
    _game.solved ? haptics.success() : haptics.tap();
    _afterChange();
  }

  void _useHint() {
    if (_game.solved) return;
    final haptics = AppScope.of(context).haptics;
    if (_game.activeHint != null) {
      haptics.tap();
      return;
    }
    if (_game.applyHint() == null) {
      haptics.error();
      return;
    }
    haptics.light();
    setState(() {});
    _save();
  }

  void _afterChange() {
    final solved = _game.solved;
    if (solved) _clock.stop();
    _save();
    if (!solved) return;
    final hints = _game.hintsUsed;
    widget.session.onFinish(
      GameFinish(
        score: _game.moves,
        durationMs: _clock.elapsedMs,
        assisted: hints > 0,
        details: [
          ('理论最少', '${_game.optimalMoves} 步'),
          ('用时', formatDuration(_clock.elapsedMs)),
          if (hints > 0) ('使用提示', '$hints 次'),
        ],
      ),
    );
  }

  String get _status {
    if (_game.solved) return '全部点亮！';
    if (_game.activeHint != null) return '点击蓝框标出的格子，向最少步数靠近一步';
    return '点击格子会翻转它与上下左右四格的电灯';
  }

  @override
  Widget build(BuildContext context) {
    final n = _game.size;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          StatBar(
            children: [
              StatPill(
                icon: Icons.touch_app_outlined,
                label: '步数',
                value: '${_game.moves}',
              ),
              GameClockPill(clock: _clock),
              StatPill(
                icon: Icons.lightbulb_rounded,
                label: '已亮',
                value: '${_game.litCount}/${_game.cellCount}',
                color: _game.solved ? AppColors.lemon : AppColors.paper,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) {
                  final side = min(c.maxWidth, c.maxHeight);
                  final gap = n >= 6 ? 6.0 : 8.0;
                  return RepaintBoundary(
                    child: Container(
                      key: const ValueKey('lightsout-board'),
                      width: side,
                      height: side,
                      padding: EdgeInsets.all(gap + 2),
                      decoration: chunkyDecoration(
                        color: AppColors.board,
                        radius: 22,
                      ),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: n,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
                        ),
                        itemCount: _game.cellCount,
                        itemBuilder: (context, i) => _LampTile(
                          key: ValueKey('lamp-$i'),
                          lit: _game.isLit(i),
                          hinted: _game.activeHint == i,
                          onTap: () => _tap(i),
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
                left: _game.hintsLeft,
                picking: false,
                enabled:
                    !_game.solved &&
                    _game.activeHint == null &&
                    _game.hintsLeft > 0,
                onTap: _useHint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _status,
                  style: AppText.caption.copyWith(
                    color: _game.activeHint != null
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

class _LampTile extends StatelessWidget {
  const _LampTile({
    super.key,
    required this.lit,
    required this.hinted,
    required this.onTap,
  });

  final bool lit;
  final bool hinted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: lit ? AppColors.lemon : AppColors.boardCell,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hinted
                ? AppColors.sky
                : lit
                ? AppColors.ink
                : const Color(0xFF4A4268),
            width: hinted ? 3 : 2,
          ),
          boxShadow: lit
              ? [
                  BoxShadow(
                    color: AppColors.lemon.withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.38,
            heightFactor: 0.38,
            child: FittedBox(
              child: Icon(
                hinted
                    ? Icons.ads_click_rounded
                    : lit
                    ? Icons.lightbulb_rounded
                    : Icons.lightbulb_outline_rounded,
                color: lit
                    ? AppColors.ink
                    : hinted
                    ? AppColors.sky
                    : const Color(0xFF6B628C),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 首页卡片插图
class LightsOutCover extends StatelessWidget {
  const LightsOutCover({super.key});

  @override
  Widget build(BuildContext context) {
    const lit = [
      false, true, false, //
      true, true, true,
      false, true, false,
    ];
    return Container(
      color: AppColors.board,
      padding: const EdgeInsets.all(9),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (final on in lit)
            Container(
              decoration: BoxDecoration(
                color: on ? AppColors.lemon : AppColors.boardCell,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: on ? AppColors.ink : const Color(0xFF4A4268),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? AppColors.ink : const Color(0xFF5D547D),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
