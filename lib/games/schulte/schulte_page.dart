import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/data/models/score_kind.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/chunky.dart';
import '../game_clock.dart';
import '../game_definition.dart';
import 'schulte_logic.dart';

class SchulteGameView extends StatefulWidget {
  const SchulteGameView({super.key, required this.session});

  final GameSession session;

  static SchulteConfig configFor(String modeId) => switch (modeId) {
    's3' => const SchulteConfig(size: 3),
    's4' => const SchulteConfig(size: 4),
    's6' => const SchulteConfig(size: 6),
    's7' => const SchulteConfig(size: 7),
    'rev' => const SchulteConfig(size: 5, descending: true),
    'shuf' => const SchulteConfig(size: 5, reshuffle: true),
    _ => const SchulteConfig(size: 5),
  };

  @override
  State<SchulteGameView> createState() => _SchulteGameViewState();
}

class _SchulteGameViewState extends State<SchulteGameView> {
  late final SchulteGame _game;
  late final GameClock _clock;

  /// 刚点错的格子，短暂标红。
  int? _wrongIndex;
  Timer? _wrongTimer;

  @override
  void initState() {
    super.initState();
    final config = SchulteGameView.configFor(widget.session.mode.id);
    final saved = widget.session.savedState;
    SchulteGame? restored;
    if (saved != null) {
      try {
        restored = SchulteGame.fromJson(
          config,
          (saved['game'] as Map).cast<String, dynamic>(),
        );
      } catch (_) {
        // 存档损坏或格式变化：直接开新局
      }
    }
    _game =
        restored ?? SchulteGame(config, random: widget.session.createRandom());
    _clock = GameClock(
      initialElapsedMs: restored == null ? 0 : saved!['elapsedMs'] as int? ?? 0,
      resolutionMs: 10,
    );
    // 用时从进入游戏开始算；已完成的对局停在最终用时
    if (!_game.completed) _clock.start();
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
    _wrongTimer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  void _tap(int i) {
    final haptics = AppScope.of(context).haptics;
    switch (_game.tap(i)) {
      case SchulteTap.ignored:
        return;
      case SchulteTap.wrong:
        haptics.error();
        _wrongTimer?.cancel();
        setState(() => _wrongIndex = i);
        _wrongTimer = Timer(const Duration(milliseconds: 260), () {
          if (mounted) setState(() => _wrongIndex = null);
        });
      case SchulteTap.correct:
        haptics.tap();
        setState(() {});
    }
    if (_game.completed) _clock.stop();
    _save();
    if (_game.completed) _finish();
  }

  void _finish() {
    final m = _game.mistakes;
    widget.session.onFinish(
      GameFinish(
        won: true,
        score: _clock.elapsedMs + m * SchulteGame.penaltyMs,
        durationMs: _clock.elapsedMs,
        details: [
          ('失误', m == 0 ? '0 次' : '$m 次 · +$m 秒'),
          if (m > 0) ('净用时', formatPreciseDuration(_clock.elapsedMs)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = _game.config.size;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          StatBar(
            children: [
              GameClockPill(
                clock: _clock,
                format: formatPreciseDuration,
                extraMs: _game.mistakes * SchulteGame.penaltyMs,
              ),
              StatPill(
                icon: Icons.ads_click_rounded,
                label: '下一个',
                value: _game.completed ? '完成' : '${_game.next}',
                color: _game.completed ? AppColors.sky : AppColors.paper,
              ),
              StatPill(
                icon: Icons.close_rounded,
                label: '失误',
                value: '${_game.mistakes}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) {
                  final side = min(c.maxWidth, c.maxHeight);
                  final gap = size >= 6 ? 5.0 : 7.0;
                  return Container(
                    key: const ValueKey('schulte-board'),
                    width: side,
                    height: side,
                    padding: EdgeInsets.all(gap + 2),
                    decoration: chunkyDecoration(
                      color: AppColors.creamDeep,
                      radius: 22,
                    ),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: size,
                        mainAxisSpacing: gap,
                        crossAxisSpacing: gap,
                      ),
                      itemCount: _game.cells.length,
                      itemBuilder: (context, i) {
                        final n = _game.cells[i];
                        return _Tile(
                          number: n,
                          found: _game.isFound(n),
                          wrong: _wrongIndex == i,
                          onTap: () => _tap(i),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.number,
    required this.found,
    required this.wrong,
    required this.onTap,
  });

  final int number;
  final bool found;
  final bool wrong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = wrong
        ? AppColors.coral
        : found
        ? AppColors.sky.withValues(alpha: 0.45)
        : AppColors.paper;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 按下即响应：比抬起手指才算更跟手，适合比快的游戏
      onTapDown: (_) => onTap(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: found ? AppColors.inkFaint : AppColors.ink,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: FractionallySizedBox(
          widthFactor: 0.62,
          heightFactor: 0.62,
          child: FittedBox(
            child: Text(
              '$number',
              style: AppText.number.copyWith(
                color: found ? AppColors.inkSoft : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 首页卡片插图
class SchulteCover extends StatelessWidget {
  const SchulteCover({super.key});

  @override
  Widget build(BuildContext context) {
    const numbers = [7, 2, 9, 4, 1, 6, 8, 5, 3];
    return Container(
      color: AppColors.sky,
      padding: const EdgeInsets.all(9),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (final n in numbers)
            Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: n <= 2 ? AppColors.lemon : AppColors.paper,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.ink, width: 1.6),
              ),
              child: Text(
                '$n',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
