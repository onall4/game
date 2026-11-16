import 'dart:typed_data';

import 'circuit_logic.dart';

/// 统计回路谜题有几种解（最多数到 [limit] 种就停）。
///
/// [tiles] 是每格导线的形状（任意朝向均可，只用到形状）。
/// 搜索步数超过 [budget] 时返回 null，表示“没能在预算内确定”。
///
/// 解法和人推理的思路一致：
/// 1. 每格先列出所有可能朝向，去掉伸出棋盘的；
/// 2. 相邻两格的接口必须一致，反复互相排除（约束传播）；
/// 3. 已确定的导线不能连成环，也不能围出一块与外界不通的“孤岛”；
/// 4. 仍不确定时，挑候选最少的格子逐个试。
int? countCircuitSolutions(
  int size,
  List<int> tiles, {
  int limit = 2,
  int budget = 50000,
}) {
  final solver = _Solver(size, tiles, limit, budget);
  return solver.run();
}

class _Solver {
  _Solver(this.size, this.tiles, this.limit, this.budget) : n = size * size;

  final int size;
  final int n;
  final List<int> tiles;
  final int limit;
  final int budget;

  int _solutions = 0;
  int _nodes = 0;
  bool _exhausted = false;

  int? run() {
    // 候选集合：16 位，第 m 位为 1 表示朝向掩码 m 仍可能
    final cand = Uint16List(n);
    for (var i = 0; i < n; i++) {
      var set = 0;
      for (var t = 0; t < 4; t++) {
        final m = rotateMask(tiles[i], t);
        if (_fitsBorder(i, m)) set |= 1 << m;
      }
      if (set == 0) return 0;
      cand[i] = set;
    }
    if (_propagate(cand, [for (var i = 0; i < n; i++) i]) &&
        _structureOk(cand)) {
      _search(cand);
    }
    return _exhausted ? null : _solutions;
  }

  void _search(Uint16List cand) {
    if (_solutions >= limit || _exhausted) return;
    if (++_nodes > budget) {
      _exhausted = true;
      return;
    }
    var best = -1;
    var bestCount = 99;
    for (var i = 0; i < n; i++) {
      final c = _popcount(cand[i]);
      if (c > 1 && c < bestCount) {
        best = i;
        bestCount = c;
        if (c == 2) break;
      }
    }
    if (best == -1) {
      // 全部确定：传播保证接口一致，结构检查保证无环且连成一片 —— 是一个解
      _solutions++;
      return;
    }
    for (var m = 0; m < 16; m++) {
      if (cand[best] & (1 << m) == 0) continue;
      final next = Uint16List.fromList(cand);
      next[best] = 1 << m;
      if (_propagate(next, [best]) && _structureOk(next)) _search(next);
      if (_solutions >= limit || _exhausted) return;
    }
  }

  /// 相邻格接口必须一致：一侧不可能有边，另一侧就不能有；一侧必定有，另一侧也必须有。
  bool _propagate(Uint16List cand, List<int> queue) {
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      final set = cand[i];
      if (set == 0) return false;
      final any = _any(set);
      final all = _all(set);
      for (final d in Dir.all) {
        final j = _neighbor(i, d);
        if (j == null) continue;
        final opp = Dir.opposite(d);
        final old = cand[j];
        var filtered = 0;
        for (var m = 0; m < 16; m++) {
          if (old & (1 << m) == 0) continue;
          final has = m & opp != 0;
          if (has && any & d == 0) continue;
          if (!has && all & d != 0) continue;
          filtered |= 1 << m;
        }
        if (filtered != old) {
          if (filtered == 0) return false;
          cand[j] = filtered;
          queue.add(j);
        }
      }
    }
    return true;
  }

  /// 已确定的导线不能成环；若出现多个连通块，每块都必须还有可能向外连接。
  bool _structureOk(Uint16List cand) {
    final parent = List<int>.generate(n, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    for (var i = 0; i < n; i++) {
      final all = _all(cand[i]);
      for (final d in const [Dir.right, Dir.down]) {
        if (all & d == 0) continue;
        final j = _neighbor(i, d)!;
        final a = find(i), b = find(j);
        if (a == b) return false; // 成环
        parent[a] = b;
      }
    }

    final open = List<bool>.filled(n, false);
    final roots = <int>{};
    for (var i = 0; i < n; i++) {
      final root = find(i);
      roots.add(root);
      final any = _any(cand[i]);
      final all = _all(cand[i]);
      for (final d in Dir.all) {
        // 只看“可能但未确定”的边：已确定的边两端本来就在同一块里
        if (any & d == 0 || all & d != 0) continue;
        final j = _neighbor(i, d);
        if (j != null && find(j) != root) open[root] = true;
      }
    }
    if (roots.length == 1) return true;
    for (final r in roots) {
      if (!open[r]) return false; // 封闭的孤岛，不可能与其余部分连通
    }
    return true;
  }

  bool _fitsBorder(int i, int m) {
    final r = i ~/ size, c = i % size;
    if (r == 0 && m & Dir.up != 0) return false;
    if (r == size - 1 && m & Dir.down != 0) return false;
    if (c == 0 && m & Dir.left != 0) return false;
    if (c == size - 1 && m & Dir.right != 0) return false;
    return true;
  }

  int? _neighbor(int i, int d) {
    final r = i ~/ size, c = i % size;
    return switch (d) {
      Dir.up => r > 0 ? i - size : null,
      Dir.down => r < size - 1 ? i + size : null,
      Dir.left => c > 0 ? i - 1 : null,
      Dir.right => c < size - 1 ? i + 1 : null,
      _ => null,
    };
  }

  /// 集合中任一朝向含有的方向
  static int _any(int set) {
    var r = 0;
    for (var m = 0; m < 16; m++) {
      if (set & (1 << m) != 0) r |= m;
    }
    return r;
  }

  /// 集合中所有朝向都含有的方向
  static int _all(int set) {
    var r = 0xF;
    for (var m = 0; m < 16; m++) {
      if (set & (1 << m) != 0) r &= m;
    }
    return r;
  }

  static int _popcount(int x) {
    var c = 0;
    for (var v = x; v != 0; v &= v - 1) {
      c++;
    }
    return c;
  }
}
