import 'dart:collection';
import 'dart:math';

import 'circuit_solver.dart';

/// 方向位掩码：上=1 右=2 下=4 左=8。
abstract final class Dir {
  static const up = 1;
  static const right = 2;
  static const down = 4;
  static const left = 8;
  static const all = [up, right, down, left];

  static int opposite(int d) => switch (d) {
    up => down,
    right => left,
    down => up,
    _ => right,
  };
}

/// 顺时针旋转 [times] 次 90°。
int rotateMask(int mask, int times) {
  var m = mask & 0xF;
  for (var i = 0; i < times % 4; i++) {
    m = ((m << 1) | (m >> 3)) & 0xF;
  }
  return m;
}

int bitCount(int mask) {
  var c = 0;
  for (var m = mask; m != 0; m &= m - 1) {
    c++;
  }
  return c;
}

/// “回路”谜题：网格中每格是一段导线，点击旋转，让所有格子都连通电源。
///
/// 生成方式：从中心电源出发做随机生成树（随机 Prim），保证一定有解；
/// 再用求解器确认只有唯一解（否则重新生成），最后把每格随机旋转打乱。
class CircuitPuzzle {
  CircuitPuzzle._(this.size, this.source, this._tiles, this._turns) {
    _recompute();
  }

  /// 每局可用的提示次数。
  static const maxHints = 3;

  factory CircuitPuzzle.generate(int size, {Random? random}) {
    final rng = random ?? Random();
    final n = size * size;
    final source = (size ~/ 2) * size + size ~/ 2;
    // 只接受求解器确认“恰好一种解”的题目；理论上极少需要重试
    var tiles = _randomTree(size, source, rng);
    for (var attempt = 0; attempt < 500; attempt++) {
      if (countCircuitSolutions(size, tiles) == 1) break;
      tiles = _randomTree(size, source, rng);
    }

    late CircuitPuzzle puzzle;
    do {
      final turns = List<int>.generate(n, (_) => rng.nextInt(4));
      puzzle = CircuitPuzzle._(size, source, List.of(tiles), turns);
    } while (puzzle.solved);
    return puzzle;
  }

  /// 以 [source] 为根的随机生成树；每格的值是它连出去的方向集合。
  static List<int> _randomTree(int size, int source, Random rng) {
    final n = size * size;
    final tiles = List<int>.filled(n, 0);
    final inTree = List<bool>.filled(n, false);
    inTree[source] = true;

    // 前沿边列表：(from, dir)
    final frontier = <(int, int)>[];
    void addFrontier(int cell) {
      for (final d in Dir.all) {
        final nb = _neighbor(size, cell, d);
        if (nb != null && !inTree[nb]) frontier.add((cell, d));
      }
    }

    addFrontier(source);
    while (frontier.isNotEmpty) {
      final idx = rng.nextInt(frontier.length);
      final (from, d) = frontier.removeAt(idx);
      final to = _neighbor(size, from, d)!;
      if (inTree[to]) continue;
      // 避免出现十字（4 向）格子之外的过多分叉：度数 >= 3 时降低连接概率
      if (bitCount(tiles[from]) >= 3 && rng.nextDouble() < 0.6) {
        frontier.add((from, d));
        // 若前沿只剩这一条，必须接受，否则会死循环
        if (frontier.length > 1) continue;
        frontier.removeLast();
      }
      tiles[from] |= d;
      tiles[to] |= Dir.opposite(d);
      inTree[to] = true;
      addFrontier(to);
    }
    return tiles;
  }

  /// 用于测试：直接指定格子与旋转。
  factory CircuitPuzzle.fromTiles({
    required int size,
    required int source,
    required List<int> tiles,
    List<int>? turns,
  }) => CircuitPuzzle._(
    size,
    source,
    List.of(tiles),
    turns ?? List.filled(tiles.length, 0),
  );

  /// 从 [toJson] 的结果恢复；数据不合法时抛出异常。
  factory CircuitPuzzle.fromJson(Map<String, dynamic> json) {
    final size = json['size'] as int;
    final tiles = List<int>.from(json['tiles'] as List);
    final turns = List<int>.from(json['turns'] as List);
    final source = json['source'] as int;
    if (tiles.length != size * size || turns.length != tiles.length) {
      throw const FormatException('回路存档尺寸不匹配');
    }
    // 旧版的手动锁定（'locked'）已取消，不再恢复
    return CircuitPuzzle._(size, source, tiles, turns)
      .._hinted.addAll(List<int>.from(json['hinted'] as List? ?? const []))
      .._moves = json['moves'] as int? ?? 0;
  }

  Map<String, dynamic> toJson() => {
    'size': size,
    'source': source,
    'tiles': _tiles,
    'turns': [for (final t in _turns) t % 4],
    'hinted': _hinted.toList(),
    'moves': _moves,
  };

  final int size;
  final int source;

  /// 每格的“原始形状”掩码，即唯一解中的朝向。
  final List<int> _tiles;

  /// 每格累计被旋转的次数（不取模，便于界面做连续旋转动画）。
  final List<int> _turns;

  /// 通过提示转正并锁定的格子（不能再旋转）。
  final Set<int> _hinted = {};
  Set<int> _powered = {};
  int _moves = 0;

  int get cellCount => size * size;
  int get moves => _moves;
  int get poweredCount => _powered.length;
  bool get solved => _powered.length == cellCount;

  int baseMask(int i) => _tiles[i];
  int turnsAt(int i) => _turns[i];
  int maskAt(int i) => rotateMask(_tiles[i], _turns[i]);
  bool isPowered(int i) => _powered.contains(i);
  bool isHinted(int i) => _hinted.contains(i);
  bool isEndpoint(int i) => bitCount(_tiles[i]) == 1 && i != source;

  int get hintsUsed => _hinted.length;
  int get hintsLeft => maxHints - _hinted.length;

  /// 旋转一格，返回是否真的发生了旋转。提示锁定的格子不能旋转。
  bool rotate(int i) {
    if (solved || _hinted.contains(i)) return false;
    _turns[i]++;
    _moves++;
    _recompute();
    return true;
  }

  /// 使用一次提示：把第 [i] 格转到正确方向并锁定。
  ///
  /// 题目只有唯一解，所以“正确方向”没有歧义。返回顺时针补转的次数
  /// （0~3，供界面做动画）；没有提示次数、该格已提示过或已通关时返回 null。
  int? applyHint(int i) {
    if (solved || hintsLeft <= 0 || _hinted.contains(i)) return null;
    var k = 0;
    while (rotateMask(_tiles[i], _turns[i] + k) != _tiles[i]) {
      k++;
    }
    _turns[i] += k;
    _hinted.add(i);
    _recompute();
    return k;
  }

  void _recompute() {
    final seen = <int>{source};
    final queue = Queue<int>()..add(source);
    while (queue.isNotEmpty) {
      final cell = queue.removeFirst();
      final mask = maskAt(cell);
      for (final d in Dir.all) {
        if (mask & d == 0) continue;
        final nb = _neighbor(size, cell, d);
        if (nb == null || seen.contains(nb)) continue;
        if (maskAt(nb) & Dir.opposite(d) == 0) continue;
        seen.add(nb);
        queue.add(nb);
      }
    }
    _powered = seen;
  }

  static int? _neighbor(int size, int cell, int d) {
    final r = cell ~/ size, c = cell % size;
    return switch (d) {
      Dir.up => r > 0 ? cell - size : null,
      Dir.down => r < size - 1 ? cell + size : null,
      Dir.left => c > 0 ? cell - 1 : null,
      Dir.right => c < size - 1 ? cell + 1 : null,
      _ => null,
    };
  }
}
