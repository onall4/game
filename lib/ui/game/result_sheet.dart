import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_services.dart';
import '../../core/data/repositories/game_record_repository.dart';
import '../../games/game_definition.dart';
import '../../games/seed.dart';
import '../theme/app_theme.dart';
import '../widgets/chunky.dart';

/// 弹出结算页。弹窗只展示成绩、不含按钮：下滑或点空白处即可收起，
/// 方便玩家回看自己的棋盘 / 解法；之后可通过游戏页右上角的奖杯再次打开。
Future<void> showResultSheet(
  BuildContext context, {
  required GameDefinition game,
  required GameMode mode,
  required GameFinish finish,
  required RecordOutcome outcome,
  GameSeed? seed,
  bool customSeed = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ResultSheet(
      game: game,
      mode: mode,
      finish: finish,
      outcome: outcome,
      seed: seed,
      customSeed: customSeed,
    ),
  );
}

class _ResultSheet extends StatefulWidget {
  const _ResultSheet({
    required this.game,
    required this.mode,
    required this.finish,
    required this.outcome,
    required this.seed,
    required this.customSeed,
  });

  final GameDefinition game;
  final GameMode mode;
  final GameFinish finish;
  final RecordOutcome outcome;
  final GameSeed? seed;
  final bool customSeed;

  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  bool _copied = false;

  void _copySeed(GameSeed seed) {
    Clipboard.setData(ClipboardData(text: seed.code));
    AppScope.of(context).haptics.tap();
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final mode = widget.mode;
    final finish = widget.finish;
    final outcome = widget.outcome;
    final kind = game.scoreKind;
    final best = outcome.record.mode(mode.id).best;

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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖动条：提示这个弹窗可以下滑收起
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.inkFaint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: 72,
                  height: 72,
                  decoration: chunkyDecoration(color: game.color, radius: 22),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    size: 40,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('挑战成功！', style: AppText.display),
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
                if (widget.customSeed) ...[
                  const SizedBox(height: 10),
                  Text('指定种子，不计入纪录', style: AppText.caption),
                ] else if (finish.assisted) ...[
                  const SizedBox(height: 10),
                  Text('本局使用了提示，不计入最佳纪录', style: AppText.caption),
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
                      _row(kind.label, kind.format(finish.score)),
                      for (final (label, value) in finish.details)
                        _row(label, value),
                      _row('最佳纪录', best == null ? '暂无' : kind.format(best)),
                      if (widget.seed case final seed?) _seedRow(seed),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 4,
                  children: const [
                    _Hint(icon: Icons.swipe_down_alt_rounded, text: '下滑收起'),
                    _Hint(icon: Icons.emoji_events_outlined, text: '奖杯：再看成绩'),
                    _Hint(icon: Icons.refresh_rounded, text: '刷新：新的一局'),
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

  Widget _seedRow(GameSeed seed) => Semantics(
    button: true,
    label: '复制种子',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _copySeed(seed),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(_copied ? '种子 · 已复制' : '种子', style: AppText.body),
            const Spacer(),
            Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 15,
              color: _copied ? AppColors.ink : AppColors.inkSoft,
            ),
            const SizedBox(width: 5),
            Text('#${seed.code}', style: AppText.number.copyWith(fontSize: 17)),
          ],
        ),
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.inkSoft),
        const SizedBox(width: 3),
        Text(text, style: AppText.caption),
      ],
    );
  }
}
