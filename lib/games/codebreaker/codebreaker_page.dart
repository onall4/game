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
      maxAttempts: 8,
      allowRepeat: false,
    ),
    'hard' => const CodeConfig(
      length: 4,
      symbols: 10,
      maxAttempts: 8,
      allowRepeat: true,
    ),
    _ => const CodeConfig(
      length: 4,
      symbols: 10,
      maxAttempts: 10,
      allowRepeat: false,
    ),
  };

  @override
  State<CodeBreakerGameView> createState() => _CodeBreakerGameViewState();
}

class _CodeBreakerGameViewState extends State<CodeBreakerGameView>
    with SingleTickerProviderStateMixin {
  late final CodeBreakerGame _game = CodeBreakerGame(
    CodeBreakerGameView.configFor(widget.session.mode.id),
  );
  final GameClock _clock = GameClock();
  final List<int> _input = [];
  final Set<int> _excluded = {};
  final ScrollController _scroll = ScrollController();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  CodeConfig get _config => _game.config;

  @override
  void dispose() {
    _clock.dispose();
    _scroll.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _press(int digit) {
    if (_game.over || _input.length >= _config.length) return;
    if (!_config.allowRepeat && _input.contains(digit)) return;
    _clock.start();
    AppScope.of(context).haptics.tap();
    setState(() => _input.add(digit));
  }

  void _toggleExclude(int digit) {
    if (_game.over) return;
    AppScope.of(context).haptics.light();
    setState(() {
      if (!_excluded.remove(digit)) _excluded.add(digit);
    });
  }

  void _backspace() {
    if (_input.isEmpty || _game.over) return;
    AppScope.of(context).haptics.tap();
    setState(_input.removeLast);
  }

  void _submit() {
    if (_game.over) return;
    final haptics = AppScope.of(context).haptics;
    if (_game.validate(_input) != null) {
      haptics.error();
      _shake.forward(from: 0);
      return;
    }
    final row = _game.submit(List.of(_input));
    setState(_input.clear);
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

    if (_game.over) {
      _clock.stop();
      widget.session.onFinish(
        GameFinish(
          won: _game.won,
          score: _game.attemptsUsed,
          durationMs: _clock.elapsedMs,
          details: [('用时', formatDuration(_clock.elapsedMs))],
          message: _game.won ? null : '正确密码是 ${_game.secret.join(' ')}',
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
              StatPill(
                icon: Icons.key_rounded,
                label: '剩余机会',
                value: '${_game.attemptsLeft}',
                color: _game.attemptsLeft <= 2 && !_game.over
                    ? AppColors.coral
                    : AppColors.paper,
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
                      itemBuilder: (context, i) => _HistoryRow(
                        index: i + 1,
                        row: _game.history[i],
                        length: _config.length,
                      ),
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
              length: _config.length,
              input: _input,
              revealed: _game.over ? _game.secret : null,
            ),
          ),
          const SizedBox(height: 14),
          _Keypad(
            alphabet: _config.alphabet,
            disabled: _config.allowRepeat ? const {} : _input.toSet(),
            excluded: _excluded,
            onDigit: _press,
            onLongDigit: _toggleExclude,
            onBackspace: _backspace,
            onSubmit: _submit,
            canSubmit: _input.length == _config.length && !_game.over,
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            const _Peg(state: _PegState.exact, size: 10),
            const SizedBox(width: 4),
            Text('位置对', style: AppText.caption.copyWith(fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const _Peg(state: _PegState.partial, size: 10),
            const SizedBox(width: 4),
            Text('数字对', style: AppText.caption.copyWith(fontSize: 11)),
          ],
        ),
      ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: chunkyDecoration(color: AppColors.lavender, radius: 20),
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
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.index,
    required this.row,
    required this.length,
  });

  final int index;
  final GuessRow row;
  final int length;

  @override
  Widget build(BuildContext context) {
    final fb = row.feedback;
    final pegs = <_PegState>[
      for (var i = 0; i < fb.exact; i++) _PegState.exact,
      for (var i = 0; i < fb.partial; i++) _PegState.partial,
      for (var i = fb.exact + fb.partial; i < length; i++) _PegState.none,
    ];
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 26, child: Text('#$index', style: AppText.caption)),
            const SizedBox(width: 4),
            for (final d in row.digits) ...[
              _DigitToken(digit: d, size: 34),
              const SizedBox(width: 6),
            ],
            const Spacer(),
            SizedBox(
              width: 40,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [for (final p in pegs) _Peg(state: p)],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: Text(
                '${fb.exact}A${fb.partial}B',
                textAlign: TextAlign.right,
                style: AppText.caption.copyWith(
                  color: AppColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
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

class _InputRow extends StatelessWidget {
  const _InputRow({required this.length, required this.input, this.revealed});

  final int length;
  final List<int> input;
  final List<int>? revealed;

  @override
  Widget build(BuildContext context) {
    final values = revealed ?? input;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 56,
            height: 60,
            alignment: Alignment.center,
            decoration: chunkyDecoration(
              color: i < values.length
                  ? digitColor(values[i])
                  : AppColors.paper,
              radius: 14,
              shadow: i < values.length ? 3.5 : 0,
              borderColor: revealed == null && i == input.length
                  ? AppColors.ink
                  : AppColors.ink.withValues(
                      alpha: i < values.length ? 1 : 0.35,
                    ),
            ),
            child: i < values.length
                ? Text(
                    '${values[i]}',
                    style: AppText.number.copyWith(fontSize: 28),
                  )
                : (revealed == null && i == input.length
                      ? Container(width: 18, height: 3, color: AppColors.ink)
                      : null),
          ),
        ],
      ],
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
    final perRow = alphabet.length <= 6 ? alphabet.length : 5;
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
