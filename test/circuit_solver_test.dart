import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:game/games/circuit/circuit_logic.dart';
import 'package:game/games/circuit/circuit_solver.dart';

void main() {
  test('风车局面有两种解（十字电源，四条臂可顺时针或逆时针）', () {
    // o  ┌──o
    // │  │
    // └──S──┐
    //    │  │
    // o──┘  o
    const tiles = [4, 6, 8, 3, 15, 12, 2, 9, 1];
    expect(countCircuitSolutions(3, tiles), 2);
  });

  test('一条直线只有一种接法', () {
    // o──S──o 放在 1 行 3 列里无法表示，这里用 3×3 的“梳子”：
    // o──┬──o
    //    │
    // o──S──o
    //    │
    // o──┴──o
    const tiles = [2, 14, 8, 2, 15, 8, 2, 11, 8];
    expect(countCircuitSolutions(3, tiles), 1);
  });

  test('与暴力穷举结果一致（含多解局面）', () {
    var multi = 0;
    for (final size in [3, 4, 5]) {
      for (var seed = 0; seed < 300; seed++) {
        final tiles = _randomTree(size, Random(seed));
        final fast = countCircuitSolutions(size, tiles, limit: 50);
        final slow = _bruteForceCount(size, tiles);
        expect(fast, slow, reason: '$size×$size seed $seed');
        if (slow > 1) multi++;
      }
    }
    expect(multi, greaterThan(0), reason: '样本里应包含多解局面，才能检验出区分能力');
  });

  test('生成的题目都只有唯一解，且生成足够快', () {
    for (final size in [4, 5, 6, 7, 8, 9, 10]) {
      final watch = Stopwatch()..start();
      const rounds = 12;
      for (var seed = 0; seed < rounds; seed++) {
        final p = CircuitPuzzle.generate(
          size,
          random: Random(seed * 31 + size),
        );
        final tiles = [for (var i = 0; i < p.cellCount; i++) p.baseMask(i)];
        expect(
          countCircuitSolutions(size, tiles),
          1,
          reason: '$size×$size seed $seed 应只有唯一解',
        );
      }
      final perPuzzle = watch.elapsedMilliseconds / rounds;
      // ignore: avoid_print
      print('$size×$size 平均生成+校验 ${perPuzzle.toStringAsFixed(1)} ms');
      expect(perPuzzle, lessThan(1500), reason: '$size×$size 生成太慢');
    }
  });

  test('提示：转到正确方向并锁定，每局最多 3 次', () {
    final p = CircuitPuzzle.generate(6, random: Random(7));
    final targets = [
      for (var i = 0; i < p.cellCount; i++)
        if (p.maskAt(i) != p.baseMask(i)) i,
    ].take(4).toList();
    expect(targets.length, 4);

    for (final i in targets.take(3)) {
      final movesBefore = p.moves;
      expect(p.applyHint(i), isNotNull);
      expect(p.maskAt(i), p.baseMask(i), reason: '提示后应为正确方向');
      expect(p.isHinted(i), isTrue);
      expect(p.rotate(i), isFalse, reason: '提示锁定的格子不能再转');
      expect(p.moves, movesBefore, reason: '提示不计入玩家的旋转次数');
    }
    expect(p.hintsLeft, 0);
    expect(p.applyHint(targets[3]), isNull, reason: '提示用完了');

    // 存档往返后提示状态还在
    final r = CircuitPuzzle.fromJson(p.toJson());
    expect(r.hintsUsed, 3);
    expect(r.isHinted(targets.first), isTrue);
  });
}

/// 测试用：与游戏无关的独立随机生成树（随机 Prim，不做任何筛选）。
List<int> _randomTree(int size, Random rng) {
  final n = size * size;
  final tiles = List<int>.filled(n, 0);
  final inTree = List<bool>.filled(n, false)..[0] = true;
  final frontier = <(int, int, int)>[];
  void add(int c) {
    final r = c ~/ size, col = c % size;
    if (r > 0 && !inTree[c - size]) frontier.add((c, Dir.up, c - size));
    if (r < size - 1 && !inTree[c + size]) {
      frontier.add((c, Dir.down, c + size));
    }
    if (col > 0 && !inTree[c - 1]) frontier.add((c, Dir.left, c - 1));
    if (col < size - 1 && !inTree[c + 1]) frontier.add((c, Dir.right, c + 1));
  }

  add(0);
  while (frontier.isNotEmpty) {
    final (from, d, to) = frontier.removeAt(rng.nextInt(frontier.length));
    if (inTree[to]) continue;
    tiles[from] |= d;
    tiles[to] |= Dir.opposite(d);
    inTree[to] = true;
    add(to);
  }
  return tiles;
}

/// 测试用：最朴素的穷举——逐格试所有朝向，只检查接口一致，最后检查连通。
int _bruteForceCount(int size, List<int> tiles) {
  final n = size * size;
  final cur = List<int>.filled(n, 0);
  var count = 0;
  bool fits(int i, int m) {
    final r = i ~/ size, c = i % size;
    if (r == 0 && m & Dir.up != 0) return false;
    if (r == size - 1 && m & Dir.down != 0) return false;
    if (c == 0 && m & Dir.left != 0) return false;
    if (c == size - 1 && m & Dir.right != 0) return false;
    if (r > 0 && ((cur[i - size] & Dir.down != 0) != (m & Dir.up != 0))) {
      return false;
    }
    if (c > 0 && ((cur[i - 1] & Dir.right != 0) != (m & Dir.left != 0))) {
      return false;
    }
    return true;
  }

  bool connected() {
    final seen = <int>{0};
    final stack = [0];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final r = i ~/ size, c = i % size;
      void visit(int d, int j) {
        if (cur[i] & d != 0 && seen.add(j)) stack.add(j);
      }

      if (r > 0) visit(Dir.up, i - size);
      if (r < size - 1) visit(Dir.down, i + size);
      if (c > 0) visit(Dir.left, i - 1);
      if (c < size - 1) visit(Dir.right, i + 1);
    }
    return seen.length == n;
  }

  void go(int i) {
    if (i == n) {
      if (connected()) count++;
      return;
    }
    final tried = <int>{};
    for (var t = 0; t < 4; t++) {
      final m = rotateMask(tiles[i], t);
      if (!tried.add(m) || !fits(i, m)) continue;
      cur[i] = m;
      go(i + 1);
    }
  }

  go(0);
  return count;
}
