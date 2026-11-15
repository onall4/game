import 'dart:math';

class CodeConfig {
  const CodeConfig({
    required this.length,
    required this.symbols,
    required this.allowRepeat,
    this.firstSymbol = 0,
  });

  /// 密码位数
  final int length;

  /// 可用符号数量，符号为 [firstSymbol] .. firstSymbol+symbols-1
  final int symbols;
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

/// “密码锁”：根据每次尝试的反馈推理出隐藏密码。不限尝试次数，猜中为止。
class CodeBreakerGame {
  CodeBreakerGame(this.config, {Random? random, List<int>? secret})
    : secret = secret ?? _generate(config, random ?? Random());

  /// 从 [toJson] 的结果恢复（重放历史猜测）；数据不合法时抛出异常。
  factory CodeBreakerGame.fromJson(
    CodeConfig config,
    Map<String, dynamic> json,
  ) {
    final secret = List<int>.from(json['secret'] as List);
    final alphabet = config.alphabet.toSet();
    if (secret.length != config.length || !secret.every(alphabet.contains)) {
      throw const FormatException('密码锁存档与当前模式不匹配');
    }
    final game = CodeBreakerGame(config, secret: secret);
    for (final guess in json['history'] as List) {
      game.submit(List<int>.from(guess as List));
    }
    return game;
  }

  Map<String, dynamic> toJson() => {
    'secret': secret,
    'history': [for (final row in _history) row.digits],
  };

  final CodeConfig config;
  final List<int> secret;
  final List<GuessRow> _history = [];

  List<GuessRow> get history => List.unmodifiable(_history);
  int get attemptsUsed => _history.length;

  bool get won =>
      _history.isNotEmpty && _history.last.feedback.exact == config.length;

  GuessError? validate(List<int> guess) {
    if (guess.length != config.length) return GuessError.incomplete;
    if (!config.allowRepeat && guess.toSet().length != guess.length) {
      return GuessError.repeated;
    }
    return null;
  }

  /// 提交一次猜测；不合法时抛出 [ArgumentError]。
  GuessRow submit(List<int> guess) {
    if (won) throw StateError('游戏已结束');
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
