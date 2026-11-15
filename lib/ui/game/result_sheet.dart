import 'package:flutter/material.dart';

import '../../core/data/repositories/game_record_repository.dart';
import '../../games/game_definition.dart';
import '../theme/app_theme.dart';
import '../widgets/chunky.dart';

enum ResultAction { again, home }

Future<ResultAction> showResultSheet(
  BuildContext context, {
  required GameDefinition game,
  required GameMode mode,
  required GameFinish finish,
  required RecordOutcome outcome,
}) async {
  final action = await showModalBottomSheet<ResultAction>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ResultSheet(game: game, mode: mode, finish: finish, outcome: outcome),
  );
  return action ?? ResultAction.again;
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({
    required this.game,
    required this.mode,
    required this.finish,
    required this.outcome,
  });

  final GameDefinition game;
  final GameMode mode;
  final GameFinish finish;
  final RecordOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final kind = game.scoreKind;
    final best = outcome.record.mode(mode.id).best;
    final won = finish.won;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: ChunkyBox(
            color: AppColors.cream,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: chunkyDecoration(
                    color: won ? game.color : AppColors.creamDeep,
                    radius: 22,
                  ),
                  child: Icon(
                    won
                        ? Icons.emoji_events_rounded
                        : Icons.sentiment_dissatisfied_rounded,
                    size: 40,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 14),
                Text(won ? '挑战成功！' : '差一点点…', style: AppText.display),
                const SizedBox(height: 6),
                Text(
                  finish.message ?? '${game.title} · ${mode.label}',
                  style: AppText.body,
                  textAlign: TextAlign.center,
                ),
                if (outcome.isNewBest) ...[
                  const SizedBox(height: 12),
                  const TagChip(label: '★ 新纪录', color: AppColors.lemon),
                ],
                const SizedBox(height: 18),
                ChunkyBox(
                  shadow: 0,
                  radius: 14,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      if (won) _row(kind.label, kind.format(finish.score)),
                      for (final (label, value) in finish.details)
                        _row(label, value),
                      _row('最佳纪录', best == null ? '暂无' : kind.format(best)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: ChunkyButton(
                        label: '返回',
                        color: AppColors.paper,
                        expand: true,
                        onTap: () =>
                            Navigator.of(context).pop(ResultAction.home),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ChunkyButton(
                        label: '再来一局',
                        icon: Icons.replay_rounded,
                        color: game.color,
                        expand: true,
                        onTap: () =>
                            Navigator.of(context).pop(ResultAction.again),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Text(label, style: AppText.body),
        const Spacer(),
        Text(value, style: AppText.number.copyWith(fontSize: 17)),
      ],
    ),
  );
}
