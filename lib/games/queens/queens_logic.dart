import 'dart:collection';
import 'dart:math';

import '../seed.dart';

/// 皇冠棋盘上单格的状态。
enum QueenMark {
  /// 空白
  empty,

  /// 玩家或提示做的排除标记（×）
  cross,

  /// 放置了皇冠
  crown,
}

/// “皇冠”（Queens / Star Battle 单星变体）：
/// 棋盘划分为 N 个彩色区域，在每行、每列、每个区域各放一顶皇冠，
/// 且任意两顶皇冠不能相邻（含斜角八方向）。
///
/// 生成方式：先放好一组合法皇冠，再从每顶皇冠出发向外扩展成连通区域，
/// 并用求解器验证并微调边界，确保每道题有且仅有唯一解。
class QueensPuzzle {
  QueensPuzzle._(this.size, this.regions, this._solution, this._marks);

  /// 每局可用的提示次数。
  static const maxHints = 3;

  factory QueensPuzzle.generate(int size, {Random? random}) {
    assert(size >= 4 && size <= 10);
    final rng = random ?? Random();
    for (var attempt = 0; attempt < 200; attempt++) {
      final queens = _randomQueens(size, rng);
      if (queens == null) continue;
      final regions = _growRegions(size, queens, rng);
      if (_refineToUnique(size, regions, queens, rng)) {
        return QueensPuzzle._(
          size,
          regions,
          queens,
          List<QueenMark>.filled(size * size, QueenMark.empty),
        );
      }
    }
    // 极端兜底：重新随机直到唯一解
    while (true) {
      final queens = _randomQueens(size, rng);
      if (queens == null) continue;
      final regions = _growRegions(size, queens, rng);
      if (countQueensSolutions(size, regions) == 1) {
        return QueensPuzzle._(
          size,
          regions,
          queens,
          List<QueenMark>.filled(size * size, QueenMark.empty),
        );
      }
    }
  }

  /// 用于测试：直接指定区域与唯一解。
  factory QueensPuzzle.fromRegions({
    required int size,
    required List<int> regions,
    required List<int> solution,
  }) => QueensPuzzle._(
    size,
    List<int>.of(regions),
    List<int>.of(solution),
    List<QueenMark>.filled(size * size, QueenMark.empty),
  );

  /// 从 [toJson] 恢复；数据不合法时抛出异常。
  factory QueensPuzzle.fromJson(Map<String, dynamic> json) {
    final size = json['size'] as int;
    final n = size * size;
    final regions = List<int>.from(json['regions'] as List);
    final solution = List<int>.from(json['solution'] as List);
    final rawMarks = List<int>.from(json['marks'] as List);
    if (size < 4 ||
        regions.length != n ||
        solution.length != size ||
        rawMarks.length != n ||
        regions.any((r) => r < 0 || r >= size) ||
        !_isValidSolution(size, regions, solution)) {
      throw const FormatException('皇冠存档不合法');
    }
    final marks = [
      for (final m in rawMarks)
        m >= 0 && m < QueenMark.values.length
            ? QueenMark.values[m]
            : QueenMark.empty,
    ];
    final puzzle = QueensPuzzle._(size, regions, solution, marks);
    for (final i in List<int>.from(json['hinted'] as List? ?? const [])) {
      if (i >= 0 && i < n && puzzle._hinted.length < maxHints) {
        puzzle._hinted.add(i);
        puzzle._marks[i] = puzzle._expectedMark(i);
      }
    }
    return puzzle.._recompute();
  }

  Map<String, dynamic> toJson() => {
    'size': size,
    'regions': regions,
    'solution': _solution,
    'marks': [for (final m in _marks) m.index],
    if (_hinted.isNotEmpty) 'hinted': _hinted.toList(),
  };

  final int size;

  /// 每格所属的区域编号（0 .. size-1）。
  final List<int> regions;

  /// 唯一解：第 r 行的皇冠在第 `_solution[r]` 列。
  final List<int> _solution;

  final List<QueenMark> _marks;
  final Set<int> _hinted = {};
  Set<int> _conflicts = const {};
  int _crownCount = 0;

  int get cellCount => size * size;
  int get crownCount => _crownCount;
  Set<int> get conflicts => _conflicts;
  bool get solved => _crownCount == size && _conflicts.isEmpty;

  int get hintsUsed => _hinted.length;
  int get hintsLeft => maxHints - _hinted.length;

  QueenMark markAt(int i) => _marks[i];
  bool isHinted(int i) => _hinted.contains(i);
  bool hasConflict(int i) => _conflicts.contains(i);
  List<int> get solution => List.unmodifiable(_solution);

  QueenMark _expectedMark(int i) {
    final r = i ~/ size, c = i % size;
    return _solution[r] == c ? QueenMark.crown : QueenMark.cross;
  }

  /// 单击格子：在「空白」与「×」之间切换（若原本是皇冠则取下变回空白）。
  bool toggleCross(int i) {
    if (solved || i < 0 || i >= cellCount || _hinted.contains(i)) return false;
    _marks[i] = switch (_marks[i]) {
      QueenMark.empty => QueenMark.cross,
      QueenMark.cross || QueenMark.crown => QueenMark.empty,
    };
    _recompute();
    return true;
  }

  /// 双击格子：放置皇冠。
  bool placeCrown(int i) {
    if (solved || i < 0 || i >= cellCount || _hinted.contains(i)) return false;
    if (_marks[i] == QueenMark.crown) return false;
    _marks[i] = QueenMark.crown;
    _recompute();
    return true;
  }

  /// 滑动批量标记或清除 ×（不覆盖已放的皇冠和提示锁定的格子）。
  bool setCross(int i, {required bool cross}) {
    if (solved || i < 0 || i >= cellCount || _hinted.contains(i)) return false;
    if (_marks[i] == QueenMark.crown) return false;
    final target = cross ? QueenMark.cross : QueenMark.empty;
    if (_marks[i] == target) return false;
    _marks[i] = target;
    return true;
  }

  /// 使用一次提示：揭晓并锁定第 [i] 格是皇冠还是 ×。
  bool applyHint(int i) {
    if (solved ||
        hintsLeft <= 0 ||
        i < 0 ||
        i >= cellCount ||
        _hinted.contains(i)) {
      return false;
    }
    _marks[i] = _expectedMark(i);
    _hinted.add(i);
    _recompute();
    return true;
  }

  void _recompute() {
    final crowns = <int>[
      for (var i = 0; i < cellCount; i++)
        if (_marks[i] == QueenMark.crown) i,
    ];
    _crownCount = crowns.length;
    final bad = <int>{};
    for (var a = 0; a < crowns.length; a++) {
      final i = crowns[a];
      final r1 = i ~/ size, c1 = i % size;
      for (var b = a + 1; b < crowns.length; b++) {
        final j = crowns[b];
        final r2 = j ~/ size, c2 = j % size;
        if (r1 == r2 ||
            c1 == c2 ||
            regions[i] == regions[j] ||
            ((r1 - r2).abs() <= 1 && (c1 - c2).abs() <= 1)) {
          bad
            ..add(i)
            ..add(j);
        }
      }
    }
    _conflicts = bad;
  }

  static bool _isValidSolution(
    int size,
    List<int> regions,
    List<int> solution,
  ) {
    final cols = <int>{};
    final regs = <int>{};
    for (var r = 0; r < size; r++) {
      final c = solution[r];
      if (c < 0 || c >= size || !cols.add(c)) return false;
      if (!regs.add(regions[r * size + c])) return false;
      if (r > 0 && (c - solution[r - 1]).abs() < 2) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // 题目生成与唯一解校验

  static List<int>? _randomQueens(int size, Random rng) {
    final cols = List<int>.filled(size, -1);
    var used = 0;
    bool dfs(int r) {
      if (r == size) return true;
      final order = List<int>.generate(size, (i) => i);
      shuffleWith(order, rng);
      for (final c in order) {
        if ((used & (1 << c)) != 0) continue;
        if (r > 0 && (c - cols[r - 1]).abs() < 2) continue;
        cols[r] = c;
        used |= 1 << c;
        if (dfs(r + 1)) return true;
        used &= ~(1 << c);
      }
      return false;
    }

    return dfs(0) ? cols : null;
  }

  /// 从每顶皇冠所在格向外随机生长成 [size] 个连通区域。
  static List<int> _growRegions(int size, List<int> queens, Random rng) {
    final n = size * size;
    final regions = List<int>.filled(n, -1);
    final sizes = List<int>.filled(size, 1);
    // 让 1~2 个区域尽量保持较小（1~3 格），形成自然的推理突破口
    final caps = List<int>.filled(size, n);
    final order = List<int>.generate(size, (i) => i);
    shuffleWith(order, rng);
    caps[order[0]] = 1 + rng.nextInt(2);
    if (size >= 6) caps[order[1]] = 2 + rng.nextInt(2);

    final frontier = <(int, int)>[];
    void pushNeighbors(int cell, int reg) {
      for (final nb in _neighbors(size, cell)) {
        if (regions[nb] == -1) frontier.add((nb, reg));
      }
    }

    for (var r = 0; r < size; r++) {
      final seed = r * size + queens[r];
      regions[seed] = r;
      pushNeighbors(seed, r);
    }

    var unassigned = n - size;
    while (unassigned > 0) {
      if (frontier.isEmpty) {
        // 个别空格被小区域围住时放开上限继续填充
        for (var i = 0; i < size; i++) {
          caps[i] = n;
        }
        for (var cell = 0; cell < n; cell++) {
          if (regions[cell] != -1) pushNeighbors(cell, regions[cell]);
        }
      }
      final idx = rng.nextInt(frontier.length);
      final (cell, reg) = frontier[idx];
      frontier[idx] = frontier.last;
      frontier.removeLast();
      if (regions[cell] != -1) continue;
      if (sizes[reg] >= caps[reg] && frontier.isNotEmpty) continue;
      regions[cell] = reg;
      sizes[reg]++;
      unassigned--;
      pushNeighbors(cell, reg);
    }
    return regions;
  }

  /// 若存在多余解，微调区域边界以消除多余解，保持预设皇冠合法且各区域连通。
  static bool _refineToUnique(
    int size,
    List<int> regions,
    List<int> queens,
    Random rng,
  ) {
    for (var step = 0; step < 24; step++) {
      final alt = _findOtherSolution(size, regions, queens);
      if (alt == null) return true;
      final diffRows = [
        for (var r = 0; r < size; r++)
          if (alt[r] != queens[r]) r,
      ];
      shuffleWith(diffRows, rng);
      var changed = false;
      for (final r in diffRows) {
        final cell = r * size + alt[r];
        final oldReg = regions[cell];
        if (!_staysConnectedWithout(size, regions, oldReg, cell)) continue;
        final nbs = _neighbors(size, cell)
          ..removeWhere((nb) => regions[nb] == oldReg);
        if (nbs.isEmpty) continue;
        shuffleWith(nbs, rng);
        regions[cell] = regions[nbs.first];
        changed = true;
        break;
      }
      if (!changed) return false;
    }
    return countQueensSolutions(size, regions) == 1;
  }

  static bool _staysConnectedWithout(
    int size,
    List<int> regions,
    int reg,
    int removed,
  ) {
    final members = <int>[
      for (var i = 0; i < regions.length; i++)
        if (i != removed && regions[i] == reg) i,
    ];
    if (members.isEmpty) return false;
    final seen = <int>{members.first};
    final queue = Queue<int>()..add(members.first);
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      for (final nb in _neighbors(size, cur)) {
        if (nb != removed && regions[nb] == reg && seen.add(nb)) {
          queue.add(nb);
        }
      }
    }
    return seen.length == members.length;
  }

  static List<int> _neighbors(int size, int cell) {
    final r = cell ~/ size, c = cell % size;
    return [
      if (r > 0) cell - size,
      if (c < size - 1) cell + 1,
      if (r < size - 1) cell + size,
      if (c > 0) cell - 1,
    ];
  }
}

/// 统计皇冠谜题的解数（最多数到 [limit] 种即停）。
int countQueensSolutions(int size, List<int> regions, {int limit = 2}) {
  var count = 0;
  _searchQueens(size, regions, (sol) {
    count++;
    return count < limit;
  });
  return count;
}

List<int>? _findOtherSolution(int size, List<int> regions, List<int> known) {
  List<int>? other;
  _searchQueens(size, regions, (sol) {
    var same = true;
    for (var i = 0; i < size; i++) {
      if (sol[i] != known[i]) {
        same = false;
        break;
      }
    }
    if (same) return true;
    other = List<int>.of(sol);
    return false;
  });
  return other;
}

void _searchQueens(
  int size,
  List<int> regions,
  bool Function(List<int> solution) onSolution,
) {
  final allMask = (1 << size) - 1;
  // suffixReg[r]：第 r .. size-1 行里还会出现的区域集合，用于提前剪枝
  final suffixReg = List<int>.filled(size + 1, 0);
  for (var r = size - 1; r >= 0; r--) {
    var mask = suffixReg[r + 1];
    for (var c = 0; c < size; c++) {
      mask |= 1 << regions[r * size + c];
    }
    suffixReg[r] = mask;
  }
  final cols = List<int>.filled(size, 0);
  var stop = false;

  void dfs(int r, int usedCols, int usedRegs, int prevCol) {
    if (stop) return;
    if ((usedRegs | suffixReg[r]) != allMask) return;
    if (r == size) {
      if (!onSolution(cols)) stop = true;
      return;
    }
    final base = r * size;
    for (var c = 0; c < size; c++) {
      if ((usedCols & (1 << c)) != 0) continue;
      if (prevCol >= 0 && (c - prevCol).abs() < 2) continue;
      final regBit = 1 << regions[base + c];
      if ((usedRegs & regBit) != 0) continue;
      cols[r] = c;
      dfs(r + 1, usedCols | (1 << c), usedRegs | regBit, c);
      if (stop) return;
    }
  }

  dfs(0, 0, 0, -2);
}
