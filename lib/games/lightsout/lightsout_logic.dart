import 'dart:math';

import '../seed.dart';

/// 熄灯一种难度的生成参数。
class LightsOutConfig {
  const LightsOutConfig({
    required this.size,
    required this.minSteps,
    required this.maxSteps,
  });

  final int size;
  final int minSteps;
  final int maxSteps;
}

/// “电灯”（Lights On）：
/// 点击任意一格，会同时切换它自己与上下左右相邻格的电灯开关；
/// 把棋盘上所有电灯全部点亮即可过关。
class LightsOutGame {
  LightsOutGame._(this.size, this._board, this.optimalMoves)
    : _allOnMask = _fullMask(size);

  /// 每局可用的提示次数。
  static const maxHints = 3;

  static BigInt _fullMask(int size) =>
      (BigInt.one << (size * size)) - BigInt.one;

  factory LightsOutGame.generate(LightsOutConfig config, {Random? random}) {
    final rng = random ?? Random();
    final n = config.size * config.size;
    final solver = _Gf2Solver.forSize(config.size);
    final allOn = _fullMask(config.size);

    for (var attempt = 0; attempt < 300; attempt++) {
      final k =
          config.minSteps + rng.nextInt(config.maxSteps - config.minSteps + 1);
      final order = List<int>.generate(n, (i) => i);
      shuffleWith(order, rng);
      var board = allOn;
      for (final cell in order.take(k)) {
        board ^= solver.toggleMasks[cell];
      }
      if (board == allOn) continue;
      final opt = solver.minSolution(allOn ^ board)!;
      if (opt.length >= config.minSteps && opt.length <= config.maxSteps) {
        return LightsOutGame._(config.size, board, opt.length);
      }
    }
    // 兜底：至少保证非全亮且有解
    final k = max(1, config.minSteps);
    final order = List<int>.generate(n, (i) => i);
    shuffleWith(order, rng);
    var board = allOn;
    for (final cell in order.take(k)) {
      board ^= solver.toggleMasks[cell];
    }
    if (board == allOn) board ^= solver.toggleMasks[0];
    final opt = solver.minSolution(allOn ^ board)!;
    return LightsOutGame._(config.size, board, opt.length);
  }

  /// 用于测试：由给定的初始亮灯列表创建（必须能全部点亮）。
  factory LightsOutGame.fromLitCells({
    required int size,
    required Iterable<int> litCells,
  }) {
    var board = BigInt.zero;
    for (final i in litCells) {
      board |= BigInt.one << i;
    }
    final allOn = _fullMask(size);
    final opt = _Gf2Solver.forSize(size).minSolution(allOn ^ board);
    if (opt == null) throw ArgumentError('该电灯局面无解');
    return LightsOutGame._(size, board, opt.length);
  }

  /// 从 [toJson] 恢复；数据不合法时抛出异常。
  factory LightsOutGame.fromJson(int expectedSize, Map<String, dynamic> json) {
    final size = json['size'] as int;
    final n = size * size;
    if (size != expectedSize || size < 2 || size > 8) {
      throw const FormatException('电灯存档尺寸不匹配');
    }
    final lit = List<int>.from(json['lit'] as List);
    if (lit.any((i) => i < 0 || i >= n)) {
      throw const FormatException('电灯存档不合法');
    }
    var board = BigInt.zero;
    for (final i in lit) {
      board |= BigInt.one << i;
    }
    final allOn = _fullMask(size);
    if (board != allOn &&
        _Gf2Solver.forSize(size).minSolution(allOn ^ board) == null) {
      throw const FormatException('电灯存档局面无解');
    }
    final optimal = (json['optimal'] as int?) ?? 1;
    final game = LightsOutGame._(size, board, max(1, optimal))
      .._moves = json['moves'] as int? ?? 0
      .._hintsUsed = (json['hintsUsed'] as int? ?? 0).clamp(0, maxHints);
    final activeHint = json['activeHint'] as int?;
    if (activeHint != null &&
        activeHint >= 0 &&
        activeHint < n &&
        !game.solved) {
      game._activeHint = activeHint;
    }
    return game;
  }

  Map<String, dynamic> toJson() => {
    'size': size,
    'lit': [
      for (var i = 0; i < cellCount; i++)
        if (isLit(i)) i,
    ],
    'optimal': optimalMoves,
    'moves': _moves,
    if (_hintsUsed > 0) 'hintsUsed': _hintsUsed,
    if (_activeHint != null) 'activeHint': _activeHint,
  };

  final int size;
  final BigInt _allOnMask;

  /// 开局时的理论最少步数。
  final int optimalMoves;

  BigInt _board;
  int _moves = 0;
  int _hintsUsed = 0;
  int? _activeHint;

  int get cellCount => size * size;
  int get moves => _moves;
  bool get solved => _board == _allOnMask;

  int get litCount => _Gf2Solver.popcount(_board);
  bool isLit(int i) => (_board & (BigInt.one << i)) != BigInt.zero;

  int get hintsUsed => _hintsUsed;
  int get hintsLeft => maxHints - _hintsUsed;

  /// 当前高亮推荐点击的格子（点掉后清除）。
  int? get activeHint => _activeHint;

  /// 从当前盘面出发，把所有电灯点亮的最少步数解法。
  List<int> solveCurrent() =>
      _Gf2Solver.forSize(size).minSolution(_allOnMask ^ _board) ?? const [];

  /// 点击第 [i] 格，翻转自身与上下左右相邻格。
  bool toggle(int i) {
    if (solved || i < 0 || i >= cellCount) return false;
    final solver = _Gf2Solver.forSize(size);
    _board ^= solver.toggleMasks[i];
    _moves++;
    if (solved || _activeHint == i) {
      _activeHint = null;
    } else if (_activeHint != null) {
      // 若玩家点了别的格子，确保提示格仍在当前最优解中，否则更新为新的最优格
      final nextOpt = solveCurrent();
      if (!nextOpt.contains(_activeHint)) {
        _activeHint = nextOpt.isEmpty ? null : nextOpt.first;
      }
    }
    return true;
  }

  /// 使用一次提示：从当前盘面的最优解里标出一格供玩家点击。
  int? applyHint() {
    if (solved) return null;
    if (_activeHint != null) return _activeHint;
    if (hintsLeft <= 0) return null;
    final nextOpt = solveCurrent();
    if (nextOpt.isEmpty) return null;
    _hintsUsed++;
    _activeHint = nextOpt.first;
    return _activeHint;
  }
}

/// GF(2) 上的高斯—若尔当消元求解器（按棋盘边长缓存分解结果）。
///
/// 使用 [BigInt] 位运算，保证在 64 位原生环境与 32 位位运算的 Web 环境上结果完全一致。
class _Gf2Solver {
  _Gf2Solver._(
    this.size,
    this.toggleMasks,
    this._pivotRowForCol,
    this._invRows,
    this._rank,
    this._nullBasis,
  );

  static final Map<int, _Gf2Solver> _cache = {};

  static _Gf2Solver forSize(int size) =>
      _cache.putIfAbsent(size, () => _build(size));

  final int size;
  final List<BigInt> toggleMasks;
  final List<int> _pivotRowForCol;
  final List<BigInt> _invRows;
  final int _rank;
  final List<BigInt> _nullBasis;

  static _Gf2Solver _build(int size) {
    final m = size * size;
    final masks = List<BigInt>.generate(m, (i) {
      final r = i ~/ size, c = i % size;
      var mask = BigInt.one << i;
      if (r > 0) mask |= BigInt.one << (i - size);
      if (r < size - 1) mask |= BigInt.one << (i + size);
      if (c > 0) mask |= BigInt.one << (i - 1);
      if (c < size - 1) mask |= BigInt.one << (i + 1);
      return mask;
    });

    final rows = List<BigInt>.of(masks);
    final inv = List<BigInt>.generate(m, (i) => BigInt.one << i);
    final pivotRowForCol = List<int>.filled(m, -1);
    var rank = 0;

    for (var col = 0; col < m; col++) {
      var sel = -1;
      for (var r = rank; r < m; r++) {
        if (_bit(rows[r], col)) {
          sel = r;
          break;
        }
      }
      if (sel == -1) continue;
      final tmpR = rows[rank];
      rows[rank] = rows[sel];
      rows[sel] = tmpR;
      final tmpI = inv[rank];
      inv[rank] = inv[sel];
      inv[sel] = tmpI;

      pivotRowForCol[col] = rank;
      for (var r = 0; r < m; r++) {
        if (r != rank && _bit(rows[r], col)) {
          rows[r] ^= rows[rank];
          inv[r] ^= inv[rank];
        }
      }
      rank++;
    }

    final freeCols = <int>[
      for (var c = 0; c < m; c++)
        if (pivotRowForCol[c] == -1) c,
    ];
    final nullBasis = <BigInt>[];
    for (final f in freeCols) {
      var vec = BigInt.one << f;
      for (var p = 0; p < m; p++) {
        final r = pivotRowForCol[p];
        if (r != -1 && _bit(rows[r], f)) {
          vec |= BigInt.one << p;
        }
      }
      nullBasis.add(vec);
    }

    return _Gf2Solver._(size, masks, pivotRowForCol, inv, rank, nullBasis);
  }

  /// 求把 [board] 全部熄灭的最少按键集合；无解时返回 null。
  List<int>? minSolution(BigInt board) {
    final m = size * size;
    if (board == BigInt.zero) return const [];
    for (var r = _rank; r < m; r++) {
      if (_parity(_invRows[r] & board) != 0) return null;
    }
    var x0 = BigInt.zero;
    for (var p = 0; p < m; p++) {
      final r = _pivotRowForCol[p];
      if (r != -1 && _parity(_invRows[r] & board) != 0) {
        x0 |= BigInt.one << p;
      }
    }

    var best = x0;
    var bestWeight = popcount(x0);
    final d = _nullBasis.length;
    final combos = 1 << d;
    for (var mask = 1; mask < combos; mask++) {
      var cand = x0;
      for (var b = 0; b < d; b++) {
        if ((mask & (1 << b)) != 0) cand ^= _nullBasis[b];
      }
      final w = popcount(cand);
      if (w < bestWeight || (w == bestWeight && cand < best)) {
        best = cand;
        bestWeight = w;
      }
    }
    return [
      for (var i = 0; i < m; i++)
        if (_bit(best, i)) i,
    ];
  }

  static bool _bit(BigInt v, int i) => (v & (BigInt.one << i)) != BigInt.zero;

  static int _parity(BigInt v) => popcount(v) & 1;

  static int popcount(BigInt v) {
    var count = 0;
    var cur = v;
    while (cur != BigInt.zero) {
      cur &= cur - BigInt.one;
      count++;
    }
    return count;
  }
}
