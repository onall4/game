import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/data/models/score_kind.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/chunky.dart';
import '../game_clock.dart';
import '../game_definition.dart';
import 'codebreaker_logic.dart';

/// 每个数字对应一种颜色，帮助玩家形成视觉记忆。
const _digitColors = [
  Color(0xFFFFD84D),
  Color(0xFFFF8E72),
  Color(0xFF7FDDB8),
  Color(0xFF7CCBFF),
  Color(0xFFB9A3FF),
  Color(0xFFFFA6C9),
  Color(0xFFA8E06A),
  Color(0xFFFFB766),
  Color(0xFF8FE3E8),
  Color(0xFFE0B8FF),
];

Color digitColor(int d) => _digitColors[d % _digitColors.length];

class CodeBreakerGameView extends StatefulWidget {
  const CodeBreakerGameView({super.key, required this.session});

  final GameSession session;

  static CodeConfig configFor(String modeId) => switch (modeId) {
    'easy' => const CodeConfig(
      length: 3,
      symbols: 6,
      firstSymbol: 1,
      allowRepeat: false,
    ),
    'lv2' => const CodeConfig(
      length: 4,
      symbols: 6,
      firstSymbol: 1,
      allowRepeat: false,
    ),
    'lv3' => const CodeConfig(
      length: 4,
      symbols: 8,
      firstSymbol: 1,
      allowRepeat: false,
    ),
    'lv5' => const CodeConfig(length: 5, symbols: 10, allowRepeat: false),
    'lv6' => const CodeConfig(length: 6, symbols: 10, allowRepeat: false),
    // 困难：6 位、可重复（用新 ID，避免和旧版 4 位困难的纪录混在一起）
    'hard6' => const CodeConfig(length: 6, symbols: 10, allowRepeat: true),
    _ => const CodeConfig(length: 4, symbols: 10, allowRepeat: false),
  };

  @override
  State<CodeBreakerGameView> createState() => _CodeBreakerGameViewState();
}

class _CodeBreakerGameViewState extends State<CodeBreakerGameView>
    with SingleTickerProviderStateMixin {
  late final CodeBreakerGame _game;
  late final GameClock _clock;

  /// 输入区的每一位（null 表示还没填）与当前要填的位置。
  late List<int?> _slots;
  int _cursor = 0;
  final Set<int> _excluded = {};
  final ScrollController _scroll = ScrollController();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  CodeConfig get _config => _game.config;

  bool get _filled => _slots.every((d) => d != null);

  /// 不重复模式下，其他位置已经用掉的数字（当前位置可以被替换）。
  Set<int> get _usedElsewhere => {
    for (final (i, d) in _slots.indexed)
      if (i != _cursor && d != null) d,
  };

  @override
  void initState() {
    super.initState();
    final config = CodeBreakerGameView.configFor(widget.session.mode.id);
    _slots = List<int?>.filled(config.length, null);
    final saved = widget.session.savedState;
    CodeBreakerGame? restored;
    if (saved != null) {
      try {
        final g = CodeBreakerGame.fromJson(
          config,
          (saved['game'] as Map).cast<String, dynamic>(),
        );
        restored = g;
        final alphabet = config.alphabet.toSet();
        _excluded.addAll(
          List<int>.from(saved['excluded'] as List? ?? const [])
              .where(alphabet.contains),
        );
        final input = List<int?>.from(saved['input'] as List? ?? const []);
        if (!g.won &&
            input.length <= config.length &&
            input.every((d) => d == null || alphabet.contains(d))) {
          // 旧版存档的 input 是从第一位起连续填写的列表，同样适用
          for (final (i, d) in input.indexed) {
            _slots[i] = d;
          }
          final cursor = saved['cursor'] as int?;
          _cursor = cursor != null && cursor >= 0 && cursor < config.length
              ? cursor
              : _firstEmpty() ?? 0;
        }
      } catch (_) {
        // 存档损坏或格式变化：直接开新局
        _excluded.clear();
        _slots = List<int?>.filled(config.length, null);
        _cursor = 0;
      }
    }
    _game = restored ?? CodeBreakerGame(config);
    _clock = GameClock(
      initialElapsedMs: restored == null ? 0 : saved!['elapsedMs'] as int? ?? 0,
    );
    // 用时从进入游戏开始算；已完成的对局停在最终用时
    if (!_game.won) _clock.start();
    if (restored != null && restored.history.isNotEmpty) {
      // 继续上一局时，直接滚到最新一次试开
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _save() {
    widget.session.saveProgress({
      'elapsedMs': _clock.elapsedMs,
      'game': _game.toJson(),
      'input': _slots,
      'cursor': _cursor,
      'excluded': _excluded.toList(),
    });
  }

  @override
  void dispose() {
    _save();
    _clock.dispose();
    _scroll.dispose();
    _shake.dispose();
    super.dispose();
  }

  int? _firstEmpty() {
    final i = _slots.indexOf(null);
    return i < 0 ? null : i;
  }

  /// 在当前位置填入数字，然后跳到下一个空位（找不到就停在原地）。
  void _press(int digit) {
    if (_game.won) return;
    if (!_config.allowRepeat && _usedElsewhere.contains(digit)) return;
    AppScope.of(context).haptics.tap();
    setState(() {
      _slots[_cursor] = digit;
      final n = _slots.length;
      for (var step = 1; step < n; step++) {
        final i = (_cursor + step) % n;
        if (_slots[i] == null) {
          _cursor = i;
          break;
        }
      }
    });
    _save();
  }

  /// 点选输入区的某一位，之后的数字填到这里。
  void _selectSlot(int i) {
    if (_game.won || i == _cursor) return;
    AppScope.of(context).haptics.tap();
    setState(() => _cursor = i);
    _save();
  }

  void _toggleExclude(int digit) {
    if (_game.won) return;
    AppScope.of(context).haptics.light();
    setState(() {
      if (!_excluded.remove(digit)) _excluded.add(digit);
    });
    _save();
  }

  /// 删除：当前位置有数字就清掉它；否则清掉它左边最近的一个数字并移过去。
  void _backspace() {
    if (_game.won) return;
    var target = _cursor;
    if (_slots[target] == null) {
      target = -1;
      for (var i = _cursor - 1; i >= 0; i--) {
        if (_slots[i] != null) {
          target = i;
          break;
        }
      }
      if (target < 0) return;
    }
    AppScope.of(context).haptics.tap();
    setState(() {
      _slots[target] = null;
      _cursor = target;
    });
    _save();
  }

  void _submit() {
    if (_game.won) return;
    final haptics = AppScope.of(context).haptics;
    if (!_filled) {
      // 还有空位：抖一下，并把光标移到第一个空位
      haptics.error();
      _shake.forward(from: 0);
      setState(() => _cursor = _firstEmpty() ?? _cursor);
      return;
    }
    final guess = [for (final d in _slots) d!];
    if (_game.validate(guess) != null) {
      haptics.error();
      _shake.forward(from: 0);
      return;
    }
    final row = _game.submit(guess);
    setState(() {
      _slots = List<int?>.filled(_config.length, null);
      _cursor = 0;
    });
    row.feedback.exact > 0 ? haptics.light() : haptics.tap();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    if (_game.won) _clock.stop();
    _save();
    if (_game.won) {
      widget.session.onFinish(
        GameFinish(
          won: true,
          score: _game.attemptsUsed,
          durationMs: _clock.elapsedMs,
          details: [('用时', formatDuration(_clock.elapsedMs))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StatPill(
                  icon: Icons.key_rounded,
                  label: '已试',
                  value: '${_game.attemptsUsed} 次',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: GameClockPill(clock: _clock)),
              const SizedBox(width: 12),
              const _Legend(),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ChunkyBox(
              color: AppColors.creamDeep,
              shadow: 0,
              padding: const EdgeInsets.all(10),
              child: _game.history.isEmpty
                  ? _EmptyHint(config: _config)
                  : ListView.separated(
                      controller: _scroll,
                      itemCount: _game.history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _HistoryRow(index: i + 1, row: _game.history[i]),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                sin(_shake.value * pi * 6) * 10 * (1 - _shake.value),
                0,
              ),
              child: child,
            ),
            child: _InputRow(
              slots: _game.won ? _game.secret : _slots,
              cursor: _game.won ? null : _cursor,
              onTapSlot: _selectSlot,
            ),
          ),
          const SizedBox(height: 14),
          _Keypad(
            alphabet: _config.alphabet,
            disabled: _config.allowRepeat ? const {} : _usedElsewhere,
            excluded: _excluded,
            onDigit: _press,
            onLongDigit: _toggleExclude,
            onBackspace: _backspace,
            onSubmit: _submit,
            canSubmit: _filled && !_game.won,
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.config});

  final CodeConfig config;

  @override
  Widget build(BuildContext context) {
    final first = config.alphabet.first, last = config.alphabet.last;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: chunkyDecoration(
                color: AppColors.lavender,
                radius: 20,
              ),
              child: const Icon(
                Icons.lock_rounded,
                size: 32,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            Text('保险箱已上锁', style: AppText.subtitle),
            const SizedBox(height: 6),
            Text(
              '密码共 ${config.length} 位，由 $first–$last 组成'
              '${config.allowRepeat ? '，数字可能重复' : '，数字互不重复'}。\n'
              '输入你的第一次猜测吧！长按数字键可以做排除标记。',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 右上角图例：说明两种颜色圆点的含义。
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: color, size: 10),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: AppText.caption.copyWith(fontSize: 11),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(AppColors.mint, '位置对'),
        const SizedBox(height: 4),
        item(AppColors.lemon, '数字对'),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.index, required this.row});

  final int index;
  final GuessRow row;

  @override
  Widget build(BuildContext context) {
    // 6 位密码时收紧间距，让数字块尽量保持大一些
    final compact = row.digits.length > 4;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
      child: ChunkyBox(
        radius: 14,
        shadow: 2.5,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: 8,
        ),
        child: Row(
          children: [
            SizedBox(
              width: compact ? 22 : 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('#$index', style: AppText.caption, maxLines: 1),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, d) in row.digits.indexed) ...[
                        if (i > 0) SizedBox(width: compact ? 4 : 6),
                        _DigitToken(digit: d, size: 34),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _FeedbackSummary(feedback: row.feedback),
          ],
        ),
      ),
    );
  }
}

/// 单次试开的结果：绿点后是“位置对”的个数，黄点后是“数字对”的个数。
class _FeedbackSummary extends StatelessWidget {
  const _FeedbackSummary({required this.feedback});

  final CodeFeedback feedback;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DotCount(color: AppColors.mint, count: feedback.exact),
        const SizedBox(width: 10),
        _DotCount(color: AppColors.lemon, count: feedback.partial),
      ],
    );
  }
}

class _DotCount extends StatelessWidget {
  const _DotCount({required this.color, required this.count});

  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: active ? color : null, size: 14),
        const SizedBox(width: 4),
        Text(
          '$count',
          maxLines: 1,
          softWrap: false,
          style: AppText.number.copyWith(
            fontSize: 16,
            color: active ? AppColors.ink : AppColors.inkFaint,
          ),
        ),
      ],
    );
  }
}

/// 彩色小圆点；[color] 为 null 时显示空心灰圈。
class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? Colors.transparent,
        border: Border.all(
          color: color == null ? AppColors.inkFaint : AppColors.ink,
          width: 1.8,
        ),
      ),
    );
  }
}

enum _PegState { exact, partial, none }

class _Peg extends StatelessWidget {
  const _Peg({required this.state, this.size = 14});

  final _PegState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (state) {
          _PegState.exact => AppColors.mint,
          _PegState.partial => AppColors.lemon,
          _PegState.none => Colors.transparent,
        },
        border: Border.all(
          color: state == _PegState.none ? AppColors.inkFaint : AppColors.ink,
          width: 1.8,
        ),
      ),
    );
  }
}

class _DigitToken extends StatelessWidget {
  const _DigitToken({required this.digit, required this.size});

  final int digit;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: digitColor(digit),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: Text(
        '$digit',
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

/// 输入区：每一位都能点选；[cursor] 指示下一个数字会填到哪一位。
/// 已开锁时 [cursor] 为 null，显示揭晓的密码。
class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.slots,
    required this.cursor,
    required this.onTapSlot,
  });

  final List<int?> slots;
  final int? cursor;
  final ValueChanged<int> onTapSlot;

  @override
  Widget build(BuildContext context) {
    final length = slots.length;
    // 6 位密码时一行放不下 56 宽的格子：按可用宽度等比缩小
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = length > 4 ? 8.0 : 10.0;
        final w = min(
          56.0,
          (constraints.maxWidth - gap * (length - 1)) / length,
        );
        final k = w / 56;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              GestureDetector(
                key: ValueKey('code-slot-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: cursor == null ? null : () => onTapSlot(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _slot(i, w, k),
                    const SizedBox(height: 5),
                    // 光标：下一个数字会填到这一位
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22 * k,
                      height: 4,
                      decoration: BoxDecoration(
                        color: i == cursor ? AppColors.ink : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _slot(int i, double w, double k) {
    final value = slots[i];
    final active = i == cursor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: w,
      height: 60 * k,
      alignment: Alignment.center,
      decoration: chunkyDecoration(
        color: value != null ? digitColor(value) : AppColors.paper,
        radius: 14 * k,
        shadow: value != null ? 3.5 : 0,
        borderColor: active || value != null
            ? AppColors.ink
            : AppColors.ink.withValues(alpha: 0.35),
      ),
      child: value != null
          ? Text('$value', style: AppText.number.copyWith(fontSize: 28 * k))
          : null,
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.alphabet,
    required this.disabled,
    required this.excluded,
    required this.onDigit,
    required this.onLongDigit,
    required this.onBackspace,
    required this.onSubmit,
    required this.canSubmit,
  });

  final List<int> alphabet;
  final Set<int> disabled;
  final Set<int> excluded;
  final ValueChanged<int> onDigit;
  final ValueChanged<int> onLongDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    final perRow = alphabet.length <= 6
        ? alphabet.length
        : (alphabet.length <= 8 ? 4 : 5);
    final rows = <List<int>>[
      for (var i = 0; i < alphabet.length; i += perRow)
        alphabet.sublist(i, min(i + perRow, alphabet.length)),
    ];
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (final (i, d) in r.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _key(d)),
                ],
              ],
            ),
          ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Pressable(
                onTap: onBackspace,
                radius: 14,
                shadow: 3,
                semanticLabel: '删除',
                child: const SizedBox(
                  height: 48,
                  child: Icon(Icons.backspace_outlined, color: AppColors.ink),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Pressable(
                onTap: onSubmit,
                radius: 14,
                shadow: 3,
                color: canSubmit ? AppColors.lavender : AppColors.paper,
                child: SizedBox(
                  height: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.lock_open_rounded,
                        color: AppColors.ink,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text('试开', style: AppText.subtitle),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(int d) {
    final isDisabled = disabled.contains(d);
    final isExcluded = excluded.contains(d);
    return Pressable(
      onTap: () => onDigit(d),
      onLongPress: () => onLongDigit(d),
      enabled: !isDisabled,
      radius: 12,
      shadow: 3,
      color: isExcluded ? AppColors.creamDeep : digitColor(d),
      semanticLabel: '$d',
      child: SizedBox(
        height: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$d',
              style: AppText.number.copyWith(
                color: isExcluded ? AppColors.inkFaint : AppColors.ink,
              ),
            ),
            if (isExcluded)
              Transform.rotate(
                angle: -0.6,
                child: Container(
                  width: 30,
                  height: 2.5,
                  color: AppColors.inkSoft,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 首页卡片插图
class CodeBreakerCover extends StatelessWidget {
  const CodeBreakerCover({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lavender,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_rounded, size: 30, color: AppColors.ink),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in const [3, 7, 1]) ...[
                _DigitToken(digit: d, size: 18),
                const SizedBox(width: 3),
              ],
            ],
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Peg(state: _PegState.exact, size: 8),
              SizedBox(width: 3),
              _Peg(state: _PegState.partial, size: 8),
              SizedBox(width: 3),
              _Peg(state: _PegState.none, size: 8),
            ],
          ),
        ],
      ),
    );
  }
}
