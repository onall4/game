import 'dart:math';

import '../seed.dart';

enum StrokeMove {
  /// 路径向前走了一格
  extended,

  /// 退回了一格
  retracted,

  /// 无效（不相邻、走过了、是障碍或已完成）
  ignored,
}

/// “一笔画”：从起点出发，上下左右移动，一笔走遍所有空格，每格只经过一次。
///
/// 生成方式：随机放置障碍，再用深度优先搜索（Warnsdorff 启发 + 剪枝）
/// 确认能从选定的起点走遍所有空格，所以每道题一定有解。
///
/// 提示：玩家点选一个格子，显示一条正确路线在这格的走向（从哪边来、往哪边去）。
class OneStrokePuzzle {
  OneStrokePuzzle._(this.cols, this.rows, this.walls, this.start, this._path)
    : openCount = walls.where((w) => !w).length;

  /// 随机生成一道题。障碍数在 [minWalls]–[maxWalls] 之间。
  factory OneStrokePuzzle.generate({
    required int cols,
    required int rows,
    required int minWalls,
    required int maxWalls,
    Random? random,
  }) {
    final rng = random ?? Random();
    final n = cols * rows;
    for (var attempt = 0; ; attempt++) {
      // 一直找不到时逐步减少障碍；没有障碍时从角上出发一定有解
      final relax = attempt ~/ 40;
      final lo = max(0, minWalls - relax);
      final hi = max(lo, maxWalls - relax);
      final k = lo + rng.nextInt(hi - lo + 1);
      final order = List.generate(n, (i) => i);
      shuffleWith(order, rng);
      final walls = List.filled(n, false);
      for (final i in order.take(k)) {
        walls[i] = true;
      }
      final start = _pickSolvableStart(cols, rows, walls, rng);
      if (start != null) {
        return OneStrokePuzzle._(cols, rows, walls, start, [start]);
      }
    }
  }

  /// 用于测试：直接指定障碍与起点。
  factory OneStrokePuzzle.fromLayout({
    required int cols,
    required int rows,
    required Set<int> walls,
    required int start,
  }) => OneStrokePuzzle._(
    cols,
    rows,
    List.generate(cols * rows, walls.contains),
    start,
    [start],
  );

  /// 从 [toJson] 的结果恢复；数据不合法时抛出异常。
  factory OneStrokePuzzle.fromJson(Map<String, dynamic> json) {
    final cols = json['cols'] as int;
    final rows = json['rows'] as int;
    final n = cols * rows;
    final wallSet = List<int>.from(json['walls'] as List).toSet();
    final walls = List.generate(n, wallSet.contains);
    final start = json['start'] as int;
    final path = List<int>.from(json['path'] as List);
    if (start < 0 || start >= n || !_validPath(cols, walls, start, path)) {
      throw const FormatException('一笔画存档不合法');
    }
    final puzzle = OneStrokePuzzle._(cols, rows, walls, start, path);
    // 提示用的参考路线：必须是完整、合法的解，否则连同提示一起丢弃
    final solution = List<int>.from(json['solution'] as List? ?? const []);
    if (solution.length == puzzle.openCount &&
        _validPath(cols, walls, start, solution)) {
      puzzle._solution = solution;
      puzzle._hinted.addAll(
        List<int>.from(json['hinted'] as List? ?? const [])
            .where((i) => i >= 0 && i < n && !walls[i])
            .toSet()
            .take(maxHints),
      );
    }
    return puzzle;
  }

  /// [path] 是否从 [start] 出发、只走空格、不重复且每步相邻。
  static bool _validPath(
    int cols,
    List<bool> walls,
    int start,
    List<int> path,
  ) {
    final seen = <int>{};
    return path.isNotEmpty &&
        path.first == start &&
        path.every(
          (i) => i >= 0 && i < walls.length && !walls[i] && seen.add(i),
        ) &&
        [
          for (var k = 1; k < path.length; k++)
            _adjacent(cols, path[k - 1], path[k]),
        ].every((ok) => ok);
  }

  Map<String, dynamic> toJson() => {
    'cols': cols,
    'rows': rows,
    'walls': [
      for (var i = 0; i < walls.length; i++)
        if (walls[i]) i,
    ],
    'start': start,
    'path': _path,
    'solution': ?_solution,
    if (_hinted.isNotEmpty) 'hinted': _hinted,
  };

  /// 每局可用的提示次数。
  static const maxHints = 3;

  final int cols;
  final int rows;

  /// 每格是否为障碍。
  final List<bool> walls;
  final int start;

  /// 需要走遍的空格数。
  final int openCount;
  final List<int> _path;

  /// 提示用的参考路线：第一次用提示时选定，之后的提示都来自它，彼此不会矛盾。
  List<int>? _solution;
  final List<int> _hinted = [];

  List<int> get path => List.unmodifiable(_path);
  int get head => _path.last;
  bool get completed => _path.length == openCount;
  bool inPath(int i) => _path.contains(i);

  /// 手指移到第 [i] 格：与路径末端相邻的空格就前进一格；
  /// 是倒数第二格就退回一格。
  StrokeMove moveTo(int i) {
    if (completed) return StrokeMove.ignored;
    if (_path.length >= 2 && i == _path[_path.length - 2]) {
      _path.removeLast();
      return StrokeMove.retracted;
    }
    if (walls[i] || _path.contains(i) || !_adjacent(cols, head, i)) {
      return StrokeMove.ignored;
    }
    _path.add(i);
    return StrokeMove.extended;
  }

  /// 把路径截短到第 [i] 格（含），从那里重新画。[i] 不在路径上或已是末端时返回 false。
  bool truncateTo(int i) {
    if (completed) return false;
    final k = _path.indexOf(i);
    if (k < 0 || k == _path.length - 1) return false;
    _path.removeRange(k + 1, _path.length);
    return true;
  }

  int get hintsUsed => _hinted.length;
  int get hintsLeft => maxHints - _hinted.length;
  bool isHinted(int i) => _hinted.contains(i);

  /// 已提示的格子 → 参考路线在这格的走向：从哪一格来（起点为 null）、
  /// 往哪一格去（终点为 null）。
  Map<int, ({int? from, int? to})> get hints {
    final solution = _solution;
    if (solution == null) return const {};
    return {
      for (final i in _hinted)
        i: () {
          final k = solution.indexOf(i);
          return (
            from: k > 0 ? solution[k - 1] : null,
            to: k < solution.length - 1 ? solution[k + 1] : null,
          );
        }(),
    };
  }

  /// 用一次提示，显示第 [i] 格的走向。次数用完、是障碍、已提示过或已完成时返回 false。
  bool applyHint(int i) {
    if (completed || hintsLeft <= 0 || walls[i] || _hinted.contains(i)) {
      return false;
    }
    _solution ??= _referenceSolution();
    _hinted.add(i);
    return true;
  }

  /// 选参考路线：优先找一条接着玩家当前路线往下走的解，这样提示能直接用上；
  /// 当前路线已经走不通时，再从起点重新找。
  List<int> _referenceSolution() {
    if (_path.length > 1) {
      for (var attempt = 0; attempt < 30; attempt++) {
        final p = findPath(
          cols,
          rows,
          walls,
          start,
          random: SeededRandom(attempt),
          from: _path,
        );
        if (p != null) return p;
      }
    }
    return solve()!;
  }

  /// 从起点出发走遍所有空格的一条路径（用于测试）；找不到时返回 null。
  ///
  /// 固定顺序的搜索偶尔会陷进很大的死胡同，所以和生成时一样，
  /// 打乱同分选项、限定搜索量，多试几次。
  List<int>? solve() {
    for (var attempt = 0; attempt < 200; attempt++) {
      final path = findPath(
        cols,
        rows,
        walls,
        start,
        random: SeededRandom(attempt),
      );
      if (path != null) return path;
    }
    // 题目生成时已确认有解，这里不限搜索量兜底
    return findPath(cols, rows, walls, start, budget: 1 << 30);
  }

  // ---------------------------------------------------------------------------

  static bool _adjacent(int cols, int a, int b) {
    final ra = a ~/ cols, ca = a % cols, rb = b ~/ cols, cb = b % cols;
    return (ra - rb).abs() + (ca - cb).abs() == 1;
  }

  static final _adjacencyCache = <int, List<List<int>>>{};

  /// 每格上、右、下、左的相邻格（固定顺序，保证同一种子结果一致）。按棋盘大小缓存。
  static List<List<int>> _adjacency(int cols, int rows) =>
      _adjacencyCache.putIfAbsent(cols * 1000 + rows, () {
        return List.generate(cols * rows, (i) {
          final r = i ~/ cols, c = i % cols;
          return List<int>.unmodifiable([
            if (r > 0) i - cols,
            if (c < cols - 1) i + 1,
            if (r < rows - 1) i + cols,
            if (c > 0) i - 1,
          ]);
        });
      });

  /// 检查障碍布局，选一个能走通的起点；布局不行时返回 null。
  static int? _pickSolvableStart(
    int cols,
    int rows,
    List<bool> walls,
    Random rng,
  ) {
    final adj = _adjacency(cols, rows);
    final open = [
      for (var i = 0; i < walls.length; i++)
        if (!walls[i]) i,
    ];
    if (open.length < 2) return null;

    // 空格必须连成一片
    final seen = {open.first};
    final queue = [open.first];
    while (queue.isNotEmpty) {
      for (final j in adj[queue.removeLast()]) {
        if (!walls[j] && seen.add(j)) queue.add(j);
      }
    }
    if (seen.length != open.length) return null;

    // 只有一个出口的格子只能做起点或终点
    final deadEnds = [
      for (final i in open)
        if (adj[i].where((j) => !walls[j]).length == 1) i,
    ];
    if (deadEnds.length > 2) return null;

    // 棋盘黑白染色：路径上黑白交替，格子多的那种颜色必须做起点
    int color(int i) => (i ~/ cols + i % cols) % 2;
    final black = open.where((i) => color(i) == 0).length;
    final diff = black - (open.length - black);
    if (diff.abs() > 1) return null;

    final candidates = [
      for (final i in deadEnds.isNotEmpty ? deadEnds : open)
        if (diff == 0 || color(i) == (diff > 0 ? 0 : 1)) i,
    ];
    shuffleWith(candidates, rng);
    for (final s in candidates.take(2)) {
      if (findPath(cols, rows, walls, s, random: rng) != null) return s;
    }
    return null;
  }

  /// 深度优先搜索一条从 [start] 出发、走遍所有空格的路径。
  ///
  /// 先走“后续选择最少”的格子（Warnsdorff），并剪掉走不通的分支；
  /// 搜索的格子数超过 [budget] 时放弃并返回 null。能走通的布局通常
  /// 几十步内就找到了，搜不出来时换一个布局比硬搜划算。
  /// 传入 [from] 时，只找以这段路线开头的解。
  static List<int>? findPath(
    int cols,
    int rows,
    List<bool> walls,
    int start, {
    Random? random,
    int budget = 3000,
    List<int>? from,
  }) {
    final n = cols * rows;
    final adj = _adjacency(cols, rows);
    final total = walls.where((w) => !w).length;
    final visited = List<bool>.of(walls);
    final path = [...?from];
    if (path.isEmpty) path.add(start);
    for (final i in path) {
      visited[i] = true;
    }
    var nodes = 0;
    // 连通性检查复用的缓冲区：用递增的标记代替每次新建集合
    final mark = List<int>.filled(n, 0);
    final queue = List<int>.filled(n, 0);
    var stamp = 0;

    int onward(int c) {
      var k = 0;
      for (final j in adj[c]) {
        if (!visited[j]) k++;
      }
      return k;
    }

    // 剩下的空格都得能从 cur 走到；“只剩一个出口”的格子最多一个（只能是终点）
    bool feasible(int cur) {
      final remaining = total - path.length;
      if (remaining == 0) return true;
      var deadEnds = 0;
      for (var v = 0; v < n; v++) {
        if (visited[v]) continue;
        var exits = 0;
        for (final j in adj[v]) {
          if (!visited[j] || j == cur) exits++;
        }
        if (exits == 0) return false;
        if (exits == 1 && ++deadEnds > 1) return false;
      }
      stamp++;
      var head = 0, tail = 0;
      for (final j in adj[cur]) {
        if (!visited[j]) {
          mark[j] = stamp;
          queue[tail++] = j;
        }
      }
      while (head < tail) {
        for (final j in adj[queue[head++]]) {
          if (!visited[j] && mark[j] != stamp) {
            mark[j] = stamp;
            queue[tail++] = j;
          }
        }
      }
      return tail == remaining;
    }

    bool dfs(int cur) {
      if (path.length == total) return true;
      if (++nodes > budget) return false;
      final options = [
        for (final j in adj[cur])
          if (!visited[j]) j,
      ];
      if (random != null) shuffleWith(options, random);
      // 按后续选择数排序。手写插入排序：List.sort 不保证稳定，结果可能随 SDK 变化
      final degrees = [for (final j in options) onward(j)];
      for (var a = 1; a < options.length; a++) {
        final o = options[a], d = degrees[a];
        var b = a - 1;
        while (b >= 0 && degrees[b] > d) {
          options[b + 1] = options[b];
          degrees[b + 1] = degrees[b];
          b--;
        }
        options[b + 1] = o;
        degrees[b + 1] = d;
      }
      for (final j in options) {
        visited[j] = true;
        path.add(j);
        if (feasible(j) && dfs(j)) return true;
        visited[j] = false;
        path.removeLast();
        if (nodes > budget) return false;
      }
      return false;
    }

    if (!feasible(path.last)) return null;
    return dfs(path.last) ? path : null;
  }
}
