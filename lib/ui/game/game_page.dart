import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/data/models/game_result.dart';
import '../../core/data/repositories/game_record_repository.dart';
import '../../core/data/repositories/progress_repository.dart';
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

/// 一局游戏的存档句柄。
///
/// [active] 为 false 表示这一局已被放弃（重新开始），旧对局销毁时不再写回存档；
/// [resultJson] 是已完成对局的结算数据，之后每次保存都会一并写入。
class _RoundHandle {
  bool active = true;
  Map<String, dynamic>? resultJson;
}

/// 已完成的一局：保留结算数据，供玩家收起弹窗后、或下次进入时再次查看。
class _RoundResult {
  const _RoundResult(this.finish, this.outcome);

  final GameFinish finish;
  final RecordOutcome outcome;
}

class _GamePageState extends State<GamePage> {
  late GameMode _mode;
  int _round = 0;
  _RoundHandle _handle = _RoundHandle();
  _RoundResult? _result;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final settings = AppScope.of(context).settings;
    _mode = widget.game.modeById(settings.lastMode(widget.game.id));
    _loadRound();
  }

  /// 为当前模式准备新的一局句柄；若存档里是已完成的对局，同时恢复结算数据。
  void _loadRound() {
    final services = AppScope.of(context);
    _handle = _RoundHandle();
    _result = null;
    final saved = services.progress.load(widget.game.id, _mode.id);
    final raw = saved?[ProgressRepository.resultKey];
    if (raw is! Map) return;
    try {
      final json = raw.cast<String, dynamic>();
      final finish = GameFinish.fromJson(
        (json['finish'] as Map).cast<String, dynamic>(),
      );
      _handle.resultJson = json;
      _result = _RoundResult(
        finish,
        RecordOutcome(
          record: services.records.recordOf(
            widget.game.id,
            widget.game.scoreKind,
          ),
          isNewBest: json['newBest'] as bool? ?? false,
        ),
      );
    } catch (_) {
      // 结算数据损坏：当作没有，不影响对局本身的恢复
    }
  }

  /// 放弃当前对局（清除存档）并开始新的一局。
  void _restart() {
    _handle.active = false;
    AppScope.of(context).progress.clear(widget.game.id, _mode.id);
    setState(() {
      _round++;
      _handle = _RoundHandle();
      _result = null;
    });
  }

  /// 切换难度：每个难度各有自己的存档，切回来时恢复。
  void _selectMode(GameMode mode) {
    if (mode.id == _mode.id) return;
    final services = AppScope.of(context);
    services.haptics.tap();
    services.settings.setLastMode(widget.game.id, mode.id);
    setState(() {
      _mode = mode;
      _round++;
      _loadRound();
    });
  }

  GameSession _buildSession() {
    final progress = AppScope.of(context).progress;
    final gameId = widget.game.id;
    // 固定住本局的模式与句柄：切换难度后，旧对局销毁时仍写回它自己的存档
    final modeId = _mode.id;
    final handle = _handle;
    return GameSession(
      mode: _mode,
      savedState: progress.load(gameId, modeId),
      saveProgress: (state) {
        if (!handle.active) return;
        progress.save(gameId, modeId, {
          ...state,
          if (handle.resultJson != null)
            ProgressRepository.resultKey: handle.resultJson,
        });
      },
      onFinish: (finish) => _handleFinish(finish, modeId, handle),
    );
  }

  Future<void> _handleFinish(
    GameFinish finish,
    String modeId,
    _RoundHandle handle,
  ) async {
    final services = AppScope.of(context);
    final gameId = widget.game.id;
    final result = GameResult(
      gameId: gameId,
      modeId: modeId,
      won: finish.won,
      score: finish.score,
      scoreKind: widget.game.scoreKind,
      durationMs: finish.durationMs,
    );
    final RecordOutcome outcome = await services.records.recordResult(result);
    // 接入服务器后，这里会在后台把结果推送上去；离线模式下是空操作。
    services.sync.sync();
    finish.won ? services.haptics.success() : services.haptics.error();

    // 把结算数据写进这一局的存档：退出再进来仍是完成画面，奖杯可查看成绩
    if (handle.active) {
      final resultJson = {
        'finish': finish.toJson(),
        'newBest': outcome.isNewBest,
      };
      handle.resultJson = resultJson;
      services.progress.save(gameId, modeId, {
        ...?services.progress.load(gameId, modeId),
        ProgressRepository.resultKey: resultJson,
      });
    }

    if (!mounted || handle != _handle) return;
    setState(() => _result = _RoundResult(finish, outcome));
    // 留一点时间让玩家看清最后一步
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || handle != _handle) return;
    await _showResult();
  }

  /// 打开结算页；玩家收起后停留在已完成的画面上，可随时点奖杯再打开。
  Future<void> _showResult() async {
    final result = _result;
    if (result == null) return;
    await showResultSheet(
      context,
      game: widget.game,
      mode: _mode,
      finish: result.finish,
      outcome: result.outcome,
    );
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
                  if (_result != null) ...[
                    _PopIn(
                      child: ChunkyIconButton(
                        icon: Icons.emoji_events_rounded,
                        tooltip: '查看成绩',
                        color: AppColors.lemon,
                        onTap: _showResult,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
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
                child: game.builder(context, _buildSession()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 出现时弹一下，吸引注意。
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      child: child,
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
