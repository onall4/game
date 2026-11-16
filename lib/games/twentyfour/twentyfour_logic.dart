import 'dart:math';

import '../seed.dart';

/// 分数，用于 24 点的中间结果（如 8/3）。总是约到最简、分母为正。
class Fraction {
  factory Fraction(int numerator, [int denominator = 1]) {
    if (denominator == 0) throw ArgumentError('分母不能为 0');
    if (denominator < 0) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final g = _gcd(numerator.abs(), denominator);
    return Fraction._(numerator ~/ g, denominator ~/ g);
  }

  const Fraction._(this.numerator, this.denominator);

  /// 解析 [toString] 的结果，如 "8/3"、"-2"。
  factory Fraction.parse(String s) {
    final parts = s.split('/');
    return Fraction(
      int.parse(parts[0]),
      parts.length > 1 ? int.parse(parts[1]) : 1,
    );
  }

  final int numerator;
  final int denominator;

  bool get isInteger => denominator == 1;

  Fraction operator +(Fraction o) => Fraction(
    numerator * o.denominator + o.numerator * denominator,
    denominator * o.denominator,
  );
  Fraction operator -(Fraction o) => Fraction(
    numerator * o.denominator - o.numerator * denominator,
    denominator * o.denominator,
  );
  Fraction operator *(Fraction o) =>
      Fraction(numerator * o.numerator, denominator * o.denominator);

  /// 除以 [o]；除数为 0 时返回 null。
  Fraction? divide(Fraction o) => o.numerator == 0
      ? null
      : Fraction(numerator * o.denominator, denominator * o.numerator);

  bool equalsInt(int v) => isInteger && numerator == v;

  @override
  bool operator ==(Object other) =>
      other is Fraction &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => isInteger ? '$numerator' : '$numerator/$denominator';

  static int _gcd(int a, int b) => b == 0 ? (a == 0 ? 1 : a) : _gcd(b, a % b);
}

enum Op {
  add('+'),
  sub('−'),
  mul('×'),
  div('÷');

  const Op(this.symbol);

  final String symbol;

  Fraction? apply(Fraction a, Fraction b) => switch (this) {
    Op.add => a + b,
    Op.sub => a - b,
    Op.mul => a * b,
    Op.div => a.divide(b),
  };
}

/// 一道题的特征，用来划分难度。
class TwentyFourStats {
  const TwentyFourStats({
    required this.solutions,
    required this.needsDivision,
    required this.needsFraction,
  });

  /// 能算出目标的运算方式数（含等价写法，只用来比较多少）。
  final int solutions;

  /// 所有解法都要用到除法。
  final bool needsDivision;

  /// 所有解法都要经过分数（如 3 3 8 8 → 8 ÷ (3 − 8 ÷ 3)）。
  final bool needsFraction;

  bool get solvable => solutions > 0;
}

/// 一个难度：数字范围、题数和选题条件。
enum TwentyFourLevel {
  /// 1–9，不用除法、解法很多
  beginner(maxNumber: 9, puzzles: 3),

  /// 1–10，不用除法、解法较多
  easy(maxNumber: 10, puzzles: 5),

  /// 1–13，不必经过分数
  medium(maxNumber: 13, puzzles: 5),

  /// 1–13，必须用除法或解法很少
  hard(maxNumber: 13, puzzles: 5),

  /// 1–13，必须经过分数
  master(maxNumber: 13, puzzles: 3);

  const TwentyFourLevel({required this.maxNumber, required this.puzzles});

  final int maxNumber;
  final int puzzles;

  bool accepts(TwentyFourStats s) =>
      s.solvable &&
      switch (this) {
        beginner => !s.needsDivision && s.solutions >= 40,
        easy => !s.needsDivision && s.solutions >= 8,
        medium => !s.needsFraction,
        hard => !s.needsFraction && (s.needsDivision || s.solutions <= 6),
        master => s.needsFraction,
      };
}

/// 24 点的一种算法及其文字写法。
class TwentyFourSolution {
  const TwentyFourSolution(this.expression, this.usesDivision, this.fractional);

  /// 如 "8 ÷ (3 − 8 ÷ 3)"
  final String expression;
  final bool usesDivision;

  /// 中间结果出现过分数
  final bool fractional;
}

/// 要算出的数。
const goal = 24;

/// 统计 [numbers] 能怎样算出 24。
TwentyFourStats analyze(List<int> numbers) {
  var count = 0, noDiv = false, anyInt = false;
  void search(List<(Fraction, bool, bool)> items) {
    // 每项：(值, 用过除法, 全程整数)
    if (items.length == 1) {
      final (v, usesDiv, allInt) = items.single;
      if (!v.equalsInt(goal)) return;
      count++;
      if (allInt) anyInt = true;
      // 不用除法时中间结果一定是整数
      if (!usesDiv) noDiv = true;
      return;
    }
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final rest = [
          for (var k = 0; k < items.length; k++)
            if (k != i && k != j) items[k],
        ];
        final (a, da, ia) = items[i];
        final (b, db, ib) = items[j];
        void push(Fraction? v, bool div) {
          if (v == null) return;
          search([...rest, (v, da || db || div, ia && ib && v.isInteger)]);
        }

        push(a + b, false);
        push(a * b, false);
        push(a - b, false);
        push(b - a, false);
        push(a.divide(b), true);
        push(b.divide(a), true);
      }
    }
  }

  search([for (final n in numbers) (Fraction(n), false, true)]);
  return TwentyFourStats(
    solutions: count,
    needsDivision: count > 0 && !noDiv,
    needsFraction: count > 0 && !anyInt,
  );
}

/// 列出 [numbers] 算出 24 的全部写法（去掉完全相同的文字）。
List<TwentyFourSolution> solutions(List<int> numbers) {
  final found = <String, TwentyFourSolution>{};
  // 每项：(值, 写法, 优先级 3=数字 2=乘除 1=加减, 用过除法, 出现过分数)
  void search(List<(Fraction, String, int, bool, bool)> items) {
    if (items.length == 1) {
      final (v, expr, _, div, frac) = items.single;
      if (v.equalsInt(goal)) {
        found.putIfAbsent(expr, () => TwentyFourSolution(expr, div, frac));
      }
      return;
    }
    for (var i = 0; i < items.length; i++) {
      for (var j = 0; j < items.length; j++) {
        if (i == j) continue;
        final rest = [
          for (var k = 0; k < items.length; k++)
            if (k != i && k != j) items[k],
        ];
        final (a, ea, pa, da, fa) = items[i];
        final (b, eb, pb, db, fb) = items[j];
        for (final op in Op.values) {
          // 加法和乘法满足交换律，只算一种顺序
          if ((op == Op.add || op == Op.mul) && i > j) continue;
          final v = op.apply(a, b);
          if (v == null) continue;
          final (l, r, p) = switch (op) {
            Op.add => (ea, eb, 1),
            Op.sub => (ea, pb <= 1 ? '($eb)' : eb, 1),
            Op.mul => (pa <= 1 ? '($ea)' : ea, pb <= 1 ? '($eb)' : eb, 2),
            Op.div => (pa <= 1 ? '($ea)' : ea, pb <= 2 ? '($eb)' : eb, 2),
          };
          search([
            ...rest,
            (
              v,
              '$l ${op.symbol} $r',
              p,
              da || db || op == Op.div,
              fa || fb || !v.isInteger,
            ),
          ]);
        }
      }
    }
  }

  search([for (final n in numbers) (Fraction(n), '$n', 3, false, false)]);
  return found.values.toList();
}

/// 最容易理解的一种写法：优先不经过分数、不用除法、写法最短。
TwentyFourSolution? bestSolution(List<int> numbers) {
  TwentyFourSolution? best;
  int score(TwentyFourSolution s) =>
      (s.fractional ? 1000 : 0) +
      (s.usesDivision ? 100 : 0) +
      s.expression.length;
  for (final s in solutions(numbers)) {
    if (best == null || score(s) < score(best)) best = s;
  }
  return best;
}

/// 1–13 中所有“必须经过分数才能算出 24”的组合（共 16 组）。
///
/// 随机抽到这类组合的概率只有约 0.6%，逐个试太慢，所以直接列出来；
/// `test/twentyfour_test.dart` 会用 [analyze] 核对这张表是否完整、准确。
const fractionOnlySets = [
  [1, 3, 4, 6], [1, 4, 5, 6], [1, 5, 5, 5], [1, 6, 6, 8], //
  [1, 8, 12, 12], [2, 2, 11, 11], [2, 2, 13, 13], [2, 3, 5, 12],
  [2, 4, 10, 10], [2, 5, 5, 10], [2, 7, 7, 10], [3, 3, 7, 7],
  [3, 3, 8, 8], [4, 4, 7, 7], [5, 5, 7, 11], [5, 7, 7, 11],
];

/// 按难度随机出一组题（同一组里不重复）。
List<List<int>> generatePuzzles(TwentyFourLevel level, Random random) {
  final puzzles = <List<int>>[];
  final seen = <String>{};
  while (puzzles.length < level.puzzles) {
    final List<int> numbers;
    if (level == TwentyFourLevel.master) {
      numbers = [...fractionOnlySets[random.nextInt(fractionOnlySets.length)]];
      shuffleWith(numbers, random);
    } else {
      numbers = [
        for (var i = 0; i < 4; i++) 1 + random.nextInt(level.maxNumber),
      ];
    }
    final key = ([...numbers]..sort()).join(',');
    if (seen.contains(key)) continue;
    if (!level.accepts(analyze(numbers))) continue;
    seen.add(key);
    puzzles.add(numbers);
  }
  return puzzles;
}

enum CombineResult {
  /// 合成了一张新牌
  combined,

  /// 最后一张牌正好是 24，这题完成
  solved,

  /// 最后一张牌不是 24
  wrong,

  /// 除数为 0
  divideByZero,

  /// 无效操作
  invalid,
}

/// “24点”的一局：若干道题，依次算出。
class TwentyFourGame {
  TwentyFourGame(this.level, {Random? random})
    : puzzles = generatePuzzles(level, random ?? Random()) {
    _loadPuzzle();
  }

  /// 用于测试：直接指定题目。
  TwentyFourGame.withPuzzles(this.level, this.puzzles) {
    _loadPuzzle();
  }

  TwentyFourGame._restored(this.level, this.puzzles);

  /// 从 [toJson] 的结果恢复；数据不合法时抛出异常。
  factory TwentyFourGame.fromJson(
    TwentyFourLevel level,
    Map<String, dynamic> json,
  ) {
    final puzzles = [
      for (final p in json['puzzles'] as List) List<int>.from(p as List),
    ];
    if (puzzles.length != level.puzzles || puzzles.any((p) => p.length != 4)) {
      throw const FormatException('24点存档与当前模式不匹配');
    }
    List<Fraction?> parseSlots(List raw) => [
      for (final s in raw) s == null ? null : Fraction.parse(s as String),
    ];
    final game = TwentyFourGame._restored(level, puzzles)
      .._index = json['index'] as int;
    if (game._index < 0 || game._index > puzzles.length) {
      throw const FormatException('24点存档进度不合法');
    }
    game._revealed.addAll(
      List<int>.from(json['revealed'] as List? ?? const []),
    );
    if (!game.completed) {
      game._slots = parseSlots(json['slots'] as List);
      if (game._slots.length != 4) throw const FormatException('24点存档不合法');
      for (final u in json['undo'] as List? ?? const []) {
        game._undo.add(parseSlots(u as List));
      }
    }
    return game;
  }

  Map<String, dynamic> toJson() => {
    'puzzles': puzzles,
    'index': _index,
    'slots': [for (final s in _slots) s?.toString()],
    'undo': [
      for (final u in _undo) [for (final s in u) s?.toString()],
    ],
    'revealed': _revealed.toList(),
  };

  final TwentyFourLevel level;
  final List<List<int>> puzzles;
  int _index = 0;
  List<Fraction?> _slots = const [];
  final List<List<Fraction?>> _undo = [];
  final Set<int> _revealed = {};

  /// 当前是第几题（从 0 开始）；全部完成后等于题数。
  int get index => _index;
  int get total => puzzles.length;
  bool get completed => _index >= puzzles.length;

  /// 四个牌位，合并掉的位置为 null。
  List<Fraction?> get slots => List.unmodifiable(_slots);
  bool get canUndo => _undo.isNotEmpty;

  /// 看过答案的题目数。
  int get answersShown => _revealed.length;
  bool get answerShown => _revealed.contains(_index);

  void _loadPuzzle() {
    _undo.clear();
    _slots = completed
        ? const []
        : [for (final n in puzzles[_index]) Fraction(n)];
  }

  /// 用第 [a] 张牌和第 [b] 张牌做运算：结果放到 [b] 的位置，[a] 移走。
  CombineResult combine(int a, Op op, int b) {
    if (completed ||
        a == b ||
        a < 0 ||
        b < 0 ||
        a >= 4 ||
        b >= 4 ||
        _slots[a] == null ||
        _slots[b] == null) {
      return CombineResult.invalid;
    }
    final v = op.apply(_slots[a]!, _slots[b]!);
    if (v == null) return CombineResult.divideByZero;
    _undo.add(List.of(_slots));
    _slots[b] = v;
    _slots[a] = null;
    if (_slots.where((s) => s != null).length > 1) {
      return CombineResult.combined;
    }
    if (!v.equalsInt(goal)) return CombineResult.wrong;
    _index++;
    _loadPuzzle();
    return CombineResult.solved;
  }

  bool undo() {
    if (_undo.isEmpty || completed) return false;
    _slots = _undo.removeLast();
    return true;
  }

  bool reset() {
    if (_undo.isEmpty || completed) return false;
    _loadPuzzle();
    return true;
  }

  /// 当前题的一种算法，并记为“看过答案”。
  String revealAnswer() {
    _revealed.add(_index);
    return bestSolution(puzzles[_index])!.expression;
  }
}
