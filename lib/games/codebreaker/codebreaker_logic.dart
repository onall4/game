import 'dart:math';

class CodeConfig {
  const CodeConfig({
    required this.length,
    required this.symbols,
    required this.maxAttempts,
    required this.allowRepeat,
    this.firstSymbol = 0,
  });

  /// 密码位数
  final int length;

  /// 可用符号数量，符号为 [firstSymbol] .. firstSymbol+symbols-1
  final int symbols;
  final int maxAttempts;
  final bool allowRepeat;
  final int firstSymbol;

  List<int> get alphabet => List.generate(symbols, (i) => firstSymbol + i);
}

class CodeFeedback {
  const CodeFeedback(this.exact, this.partial);

  /// 数字和位置都正确
  final int exact;

  /// 数字正确但位置不对
  final int partial;

  @override
  bool operator ==(Object other) =>
      other is CodeFeedback && other.exact == exact && other.partial == partial;

  @override
  int get hashCode => Object.hash(exact, partial);

  @override
  String toString() => '${exact}A${partial}B';
}

class GuessRow {
  const GuessRow(this.digits, this.feedback);

  final List<int> digits;
  final CodeFeedback feedback;
}

/// 计算一次猜测的反馈，正确处理重复数字。
CodeFeedback evaluate(List<int> secret, List<int> guess) {
  assert(secret.length == guess.length);
  var exact = 0;
  final secretCounts = <int, int>{};
  final guessCounts = <int, int>{};
  for (var i = 0; i < secret.length; i++) {
    if (secret[i] == guess[i]) {
      exact++;
    } else {
      secretCounts.update(secret[i], (v) => v + 1, ifAbsent: () => 1);
      guessCounts.update(guess[i], (v) => v + 1, ifAbsent: () => 1);
    }
  }
  var partial = 0;
  guessCounts.forEach((digit, count) {
    partial += min(count, secretCounts[digit] ?? 0);
  });
  return CodeFeedback(exact, partial);
}

enum GuessError { incomplete, repeated }

/// “密码锁”：根据每次尝试的反馈推理出隐藏密码。
class CodeBreakerGame {
  CodeBreakerGame(this.config, {Random? random, List<int>? secret})
    : secret = secret ?? _generate(config, random ?? Random());

  final CodeConfig config;
  final List<int> secret;
  final List<GuessRow> _history = [];

  List<GuessRow> get history => List.unmodifiable(_history);
  int get attemptsUsed => _history.length;
  int get attemptsLeft => config.maxAttempts - _history.length;

  bool get won =>
      _history.isNotEmpty && _history.last.feedback.exact == config.length;
  bool get lost => !won && attemptsLeft <= 0;
  bool get over => won || lost;

  GuessError? validate(List<int> guess) {
    if (guess.length != config.length) return GuessError.incomplete;
    if (!config.allowRepeat && guess.toSet().length != guess.length) {
      return GuessError.repeated;
    }
    return null;
  }

  /// 提交一次猜测；不合法时抛出 [ArgumentError]。
  GuessRow submit(List<int> guess) {
    if (over) throw StateError('游戏已结束');
    final err = validate(guess);
    if (err != null) throw ArgumentError(err.name);
    final row = GuessRow(List.unmodifiable(guess), evaluate(secret, guess));
    _history.add(row);
    return row;
  }

  static List<int> _generate(CodeConfig config, Random rng) {
    final alphabet = config.alphabet;
    if (config.allowRepeat) {
      return List.generate(
        config.length,
        (_) => alphabet[rng.nextInt(alphabet.length)],
      );
    }
    final pool = [...alphabet]..shuffle(rng);
    return pool.take(config.length).toList();
  }
}
