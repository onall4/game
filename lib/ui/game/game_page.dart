import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/data/models/game_result.dart';
import '../../core/data/repositories/game_record_repository.dart';
import '../../games/game_definition.dart';
import '../theme/app_theme.dart';
import '../widgets/chunky.dart';
import 'result_sheet.dart';

/// 所有小游戏共用的外壳：顶栏、难度切换、规则说明、重开与结算。
class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.game});

  final GameDefinition game;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late GameMode _mode;
  int _round = 0;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final settings = AppScope.of(context).settings;
    _mode = widget.game.modeById(settings.lastMode(widget.game.id));
  }

  void _restart() => setState(() => _round++);

  void _selectMode(GameMode mode) {
    if (mode.id == _mode.id) return;
    final services = AppScope.of(context);
    services.haptics.tap();
    services.settings.setLastMode(widget.game.id, mode.id);
    setState(() {
      _mode = mode;
      _round++;
    });
  }

  Future<void> _handleFinish(GameFinish finish) async {
    final services = AppScope.of(context);
    final result = GameResult(
      gameId: widget.game.id,
      modeId: _mode.id,
      won: finish.won,
      score: finish.score,
      scoreKind: widget.game.scoreKind,
      durationMs: finish.durationMs,
    );
    final RecordOutcome outcome = await services.records.recordResult(result);
    // 接入服务器后，这里会在后台把结果推送上去；离线模式下是空操作。
    services.sync.sync();
    finish.won ? services.haptics.success() : services.haptics.error();

    if (!mounted) return;
    // 留一点时间让玩家看清最后一步
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    final action = await showResultSheet(
      context,
      game: widget.game,
      mode: _mode,
      finish: finish,
      outcome: outcome,
    );
    if (!mounted) return;
    if (action == ResultAction.home) {
      Navigator.of(context).pop();
    } else {
      _restart();
    }
  }

  void _showRules() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RulesSheet(game: widget.game),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  ChunkyIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: '返回',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(game.title, style: AppText.title),
                        Text(
                          _mode.description,
                          style: AppText.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  ChunkyIconButton(
                    icon: Icons.question_mark_rounded,
                    tooltip: '玩法',
                    onTap: _showRules,
                  ),
                  const SizedBox(width: 10),
                  ChunkyIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '重新开始',
                    color: game.color,
                    onTap: () {
                      AppScope.of(context).haptics.tap();
                      _restart();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _ModeSelector(
                modes: game.modes,
                selected: _mode,
                color: game.color,
                onSelect: _selectMode,
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('${_mode.id}#$_round'),
                child: game.builder(
                  context,
                  GameSession(mode: _mode, onFinish: _handleFinish),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.modes,
    required this.selected,
    required this.color,
    required this.onSelect,
  });

  final List<GameMode> modes;
  final GameMode selected;
  final Color color;
  final ValueChanged<GameMode> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.creamDeep,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink, width: AppDims.border),
      ),
      child: Row(
        children: [
          for (final m in modes)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: m.id == selected.id ? color : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: m.id == selected.id
                          ? AppColors.ink
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    m.label,
                    style: AppText.subtitle.copyWith(
                      fontSize: 14,
                      color: m.id == selected.id
                          ? AppColors.ink
                          : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RulesSheet extends StatelessWidget {
  const _RulesSheet({required this.game});

  final GameDefinition game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ChunkyBox(
          color: AppColors.cream,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TagChip(label: '玩法', color: game.color),
                  const SizedBox(width: 10),
                  Text(game.title, style: AppText.title),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, rule) in game.rules.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.ink,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: AppColors.cream,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  rule,
                                  style: AppText.body.copyWith(
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ChunkyButton(
                label: '明白了',
                color: game.color,
                expand: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
