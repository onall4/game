import 'dart:collection';
import 'dart:math';

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
/// 生成方式：从中心电源出发做随机生成树（随机 Prim），
/// 保证一定有解；再把每格随机旋转打乱。
class CircuitPuzzle {
  CircuitPuzzle._(this.size, this.source, this._tiles, this._turns) {
    _recompute();
  }

  factory CircuitPuzzle.generate(int size, {Random? random}) {
    final rng = random ?? Random();
    final n = size * size;
    final source = (size ~/ 2) * size + size ~/ 2;
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

    late CircuitPuzzle puzzle;
    do {
      final turns = List<int>.generate(n, (_) => rng.nextInt(4));
      puzzle = CircuitPuzzle._(size, source, List.of(tiles), turns);
    } while (puzzle.solved);
    return puzzle;
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

  final int size;
  final int source;

  /// 每格的“原始形状”掩码（解中的朝向）。
  final List<int> _tiles;

  /// 每格累计被旋转的次数（不取模，便于界面做连续旋转动画）。
  final List<int> _turns;
  final Set<int> _locked = {};
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
  bool isLocked(int i) => _locked.contains(i);
  bool isEndpoint(int i) => bitCount(_tiles[i]) == 1 && i != source;

  /// 旋转一格，返回是否真的发生了旋转。
  bool rotate(int i) {
    if (solved || _locked.contains(i)) return false;
    _turns[i]++;
    _moves++;
    _recompute();
    return true;
  }

  void toggleLock(int i) {
    if (!_locked.remove(i)) _locked.add(i);
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
