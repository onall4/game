import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/chunky.dart';
import '../game_clock.dart';
import '../game_definition.dart';
import 'twentyfour_logic.dart';

class TwentyFourGameView extends StatefulWidget {
  const TwentyFourGameView({super.key, required this.session});

  final GameSession session;

  static TwentyFourLevel levelFor(String modeId) => switch (modeId) {
    't1' => TwentyFourLevel.beginner,
    't2' => TwentyFourLevel.easy,
    't4' => TwentyFourLevel.hard,
    't5' => TwentyFourLevel.master,
    _ => TwentyFourLevel.medium,
  };

  @override
  State<TwentyFourGameView> createState() => _TwentyFourGameViewState();
}

class _TwentyFourGameViewState extends State<TwentyFourGameView>
    with SingleTickerProviderStateMixin {
  late final TwentyFourGame _game;
  late final GameClock _clock;

  /// 选中的第一张牌与运算符。
  int? _selected;
  Op? _op;

  /// 当前题已看过的答案。
  String? _answer;

  /// 算错时让牌晃一下。
  int _shake = 0;

  /// 刚算出 24 的牌位：短暂展示合成出的 24，再切到下一题。
  int? _solvedSlot;
  late final AnimationController _solveAnim =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _solvedSlot = null);
        }
      });

  @override
  void initState() {
    super.initState();
    final level = TwentyFourGameView.levelFor(widget.session.mode.id);
    final saved = widget.session.savedState;
    TwentyFourGame? restored;
    if (saved != null) {
      try {
        restored = TwentyFourGame.fromJson(
          level,
          (saved['game'] as Map).cast<String, dynamic>(),
        );
      } catch (_) {
        // 存档损坏或格式变化：直接开新局
      }
    }
    _game =
        restored ??
        TwentyFourGame(level, random: widget.session.createRandom());
    if (!_game.completed && _game.answerShown) {
      _answer = bestSolution(_game.puzzles[_game.index])?.expression;
    }
    _clock = widget.session.createClock(
      initialElapsedMs: restored == null ? 0 : saved!['elapsedMs'] as int? ?? 0,
      onBackground: _save,
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
    _solveAnim.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _clearSelection() {
    _selected = null;
    _op = null;
  }

  void _tapCard(int i) {
    if (_solvedSlot != null || _game.completed || _game.slots[i] == null) {
      return;
    }
    final haptics = AppScope.of(context).haptics;
    final first = _selected, op = _op;
    if (first == null || op == null || first == i) {
      // 选牌 / 换一张 / 再点一次取消
      haptics.tap();
      setState(() {
        _selected = first == i ? null : i;
        _op = null;
      });
      return;
    }
    switch (_game.combine(first, op, i)) {
      case CombineResult.invalid:
        return;
      case CombineResult.divideByZero:
        haptics.error();
        setState(() => _op = null);
        return;
      case CombineResult.combined:
        haptics.tap();
        // 结果自动选中，方便接着算
        setState(() {
          _selected = i;
          _op = null;
        });
      case CombineResult.wrong:
        haptics.error();
        setState(() {
          _clearSelection();
          _shake++;
        });
        // 让玩家看一眼算出来的数，再自动退回上一步
        final shake = _shake;
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (!mounted || shake != _shake) return;
          if (_game.slots.where((s) => s != null).length == 1) {
            setState(_game.undo);
            _save();
          }
        });
      case CombineResult.solved:
        haptics.success();
        setState(() {
          _clearSelection();
          _answer = null;
          _solvedSlot = i;
        });
        _solveAnim.forward(from: 0);
    }
    if (_game.completed) _clock.stop();
    _save();
    if (_game.completed) _finish();
  }

  void _tapOp(Op op) {
    if (_solvedSlot != null) return;
    final haptics = AppScope.of(context).haptics;
    if (_selected == null) {
      haptics.error(); // 先选一张牌
      return;
    }
    haptics.tap();
    setState(() => _op = _op == op ? null : op);
  }

  void _undo() {
    if (_solvedSlot != null || !_game.undo()) return;
    AppScope.of(context).haptics.tap();
    setState(_clearSelection);
    _save();
  }

  void _reset() {
    if (_solvedSlot != null || !_game.reset()) return;
    AppScope.of(context).haptics.tap();
    setState(_clearSelection);
    _save();
  }

  Future<void> _reveal() async {
    if (_solvedSlot != null || _game.completed || _answer != null) return;
    // 第一次看答案前提醒一下：看过答案的对局不计入最佳纪录
    if (_game.answersShown == 0) {
      _clock.setPaused(true);
      final bool? ok;
      try {
        ok = await showDialog<bool>(
          context: context,
          builder: (context) => const _RevealDialog(),
        );
      } finally {
        _clock.setPaused(false);
      }
      if (ok != true || !mounted) return;
    }
    setState(() => _answer = _game.revealAnswer());
    _save();
  }

  void _finish() {
    final shown = _game.answersShown;
    widget.session.onFinish(
      GameFinish(
        won: true,
        score: _clock.elapsedMs,
        durationMs: _clock.elapsedMs,
        assisted: shown > 0,
        details: [
          ('题数', '${_game.total} 题'),
          if (shown > 0) ('看答案', '$shown 题'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final solvedSlot = _solvedSlot;
    final displayIndex = solvedSlot != null ? _game.index - 1 : _game.index;
    final current = min(displayIndex + 1, _game.total);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          StatBar(
            children: [
              StatPill(
                icon: Icons.style_outlined,
                label: '题目',
                value: '$current/${_game.total}',
                color: _game.completed && solvedSlot == null
                    ? AppColors.coral
                    : AppColors.paper,
              ),
              GameClockPill(clock: _clock),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) {
                  final side = min(c.maxWidth, c.maxHeight);
                  return SizedBox.square(
                    dimension: side,
                    child: solvedSlot != null
                        ? AnimatedBuilder(
                            animation: _solveAnim,
                            builder: (context, child) => Transform.scale(
                              scale: 1 + 0.06 * sin(_solveAnim.value * pi),
                              child: child,
                            ),
                            child: _CardGrid(
                              key: ValueKey('solved$displayIndex'),
                              slots: [
                                for (var k = 0; k < 4; k++)
                                  k == solvedSlot ? Fraction(goal) : null,
                              ],
                              selected: null,
                              solvedSlot: solvedSlot,
                              animateEntry: false,
                              onTap: _tapCard,
                            ),
                          )
                        : _game.completed
                        ? const _AllDone()
                        : _Shake(
                            count: _shake,
                            child: _CardGrid(
                              key: ValueKey('puzzle${_game.index}'),
                              slots: _game.slots,
                              selected: _selected,
                              onTap: _tapCard,
                            ),
                          ),
                  );
                },
              ),
            ),
          ),
          if (_answer case final answer?) ...[
            const SizedBox(height: 10),
            ChunkyBox(
              color: AppColors.cream,
              shadow: 0,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '答案：$answer = 24',
                  maxLines: 1,
                  style: AppText.subtitle,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (i, op) in Op.values.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Pressable(
                    semanticLabel: op.symbol,
                    color: _op == op ? AppColors.lemon : AppColors.paper,
                    radius: 14,
                    shadow: 3,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    onTap: _game.completed ? null : () => _tapOp(op),
                    child: Center(
                      child: Text(
                        op.symbol,
                        style: AppText.number.copyWith(fontSize: 26),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.undo_rounded,
                  label: '撤销',
                  onTap: _game.canUndo ? _undo : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.restart_alt_rounded,
                  label: '重置',
                  onTap: _game.canUndo ? _reset : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.lightbulb_outline_rounded,
                  label: '答案',
                  onTap: _game.completed || _answer != null ? null : _reveal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({
    super.key,
    required this.slots,
    required this.selected,
    required this.onTap,
    this.solvedSlot,
    this.animateEntry = true,
  });

  final List<Fraction?> slots;
  final int? selected;
  final int? solvedSlot;
  final bool animateEntry;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final grid = GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(4),
      children: [
        for (var i = 0; i < slots.length; i++)
          if (slots[i] case final value?)
            Pressable(
              key: ValueKey('card$i'),
              semanticLabel: '$value',
              color: solvedSlot == i
                  ? AppColors.lemon
                  : selected == i
                  ? AppColors.coral
                  : AppColors.paper,
              radius: 20,
              onTap: solvedSlot != null ? null : () => onTap(i),
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.7,
                  heightFactor: 0.5,
                  child: FittedBox(
                    child: Text('$value', style: AppText.number),
                  ),
                ),
              ),
            )
          else
            // 合并掉的牌位
            Padding(
              padding: const EdgeInsets.only(bottom: AppDims.shadow),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.creamDeep,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
      ],
    );
    if (!animateEntry) return grid;
    // 新的一题出现时弹一下
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: grid,
    );
  }
}

/// [count] 每变一次，左右晃动一下（算错时）。
class _Shake extends StatefulWidget {
  const _Shake({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_Shake old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Transform.translate(
          offset: Offset(sin(t * pi * 6) * 10 * (1 - t), 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _AllDone extends StatelessWidget {
  const _AllDone();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: chunkyDecoration(color: AppColors.coral, radius: 48),
        child: const Icon(Icons.check_rounded, size: 56, color: AppColors.ink),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: label,
      enabled: onTap != null,
      onTap: onTap,
      radius: 14,
      shadow: 3,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppColors.ink),
            const SizedBox(width: 6),
            Text(label, style: AppText.subtitle),
          ],
        ),
      ),
    );
  }
}

class _RevealDialog extends StatelessWidget {
  const _RevealDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ChunkyBox(
        color: AppColors.cream,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('看答案？', style: AppText.title),
            const SizedBox(height: 8),
            const Text(
              '看过答案的对局不计入最佳纪录。',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ChunkyButton(
                    label: '再想想',
                    color: AppColors.paper,
                    expand: true,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChunkyButton(
                    label: '看答案',
                    color: AppColors.coral,
                    expand: true,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页卡片插图
class TwentyFourCover extends StatelessWidget {
  const TwentyFourCover({super.key});

  @override
  Widget build(BuildContext context) {
    Widget card(String n) => Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.ink, width: 1.6),
      ),
      child: Text(
        n,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
        ),
      ),
    );
    return Container(
      color: AppColors.coral,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [card('3'), const SizedBox(width: 22), card('8')],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [card('8'), const SizedBox(width: 22), card('3')],
              ),
            ],
          ),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.lemon,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.ink, width: 2),
            ),
            child: const Text(
              '24',
              style: TextStyle(
                fontSize: 14,
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
