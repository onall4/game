import 'dart:math';

import '../seed.dart';

/// 棋盘上的一个轴对齐矩形（含端点，0 ≤ r1 ≤ r2，0 ≤ c1 ≤ c2）。
class ShikakuRect {
  const ShikakuRect(this.r1, this.c1, this.r2, this.c2)
    : assert(r1 <= r2 && c1 <= c2);

  factory ShikakuRect.fromCorners(int ra, int ca, int rb, int cb) =>
      ShikakuRect(min(ra, rb), min(ca, cb), max(ra, rb), max(ca, cb));

  factory ShikakuRect.fromJson(List<dynamic> json) => ShikakuRect(
    json[0] as int,
    json[1] as int,
    json[2] as int,
    json[3] as int,
  );

  final int r1;
  final int c1;
  final int r2;
  final int c2;

  int get width => c2 - c1 + 1;
  int get height => r2 - r1 + 1;
  int get area => width * height;

  bool contains(int r, int c) => r >= r1 && r <= r2 && c >= c1 && c <= c2;

  bool overlaps(ShikakuRect other) =>
      !(r2 < other.r1 || r1 > other.r2 || c2 < other.c1 || c1 > other.c2);

  List<int> toJson() => [r1, c1, r2, c2];

  @override
  bool operator ==(Object other) =>
      other is ShikakuRect &&
      other.r1 == r1 &&
      other.c1 == c1 &&
      other.r2 == r2 &&
      other.c2 == c2;

  @override
  int get hashCode => Object.hash(r1, c1, r2, c2);
}

/// “数方”（Shikaku / 矩形分割）：
/// 把整个棋盘分割成若干互不重叠的矩形，每个矩形内恰好包含一个数字，
/// 且矩形包含的格子数等于该数字。
class ShikakuPuzzle {
  ShikakuPuzzle._(this.size, this.clues, this._solution);

  /// 每局可用的提示次数。
  static const maxHints = 3;

  factory ShikakuPuzzle.generate(int size, {int? maxArea, Random? random}) {
    final rng = random ?? Random();
    final cap = maxArea ?? max(6, size + 3);
    while (true) {
      final tiling = _randomTiling(size, cap, rng);
      if (tiling == null) continue;
      for (var k = 0; k < 12; k++) {
        final clues = List<int>.filled(size * size, 0);
        for (final rect in tiling) {
          final r = rect.r1 + rng.nextInt(rect.height);
          final c = rect.c1 + rng.nextInt(rect.width);
          clues[r * size + c] = rect.area;
        }
        if (countShikakuSolutions(size, clues) == 1) {
          return ShikakuPuzzle._(size, clues, tiling);
        }
      }
    }
  }

  /// 用于测试或封面：直接指定线索与答案划分。
  factory ShikakuPuzzle.fromClues({
    required int size,
    required List<int> clues,
    required List<ShikakuRect> solution,
  }) => ShikakuPuzzle._(size, List.of(clues), List.of(solution));

  /// 从 [toJson] 恢复；数据不合法时抛出异常。
  factory ShikakuPuzzle.fromJson(Map<String, dynamic> json) {
    final size = json['size'] as int;
    final n = size * size;
    final clues = List<int>.from(json['clues'] as List);
    final solution = [
      for (final r in json['solution'] as List) ShikakuRect.fromJson(r as List),
    ];
    if (size < 3 ||
        clues.length != n ||
        !_validPartition(size, clues, solution)) {
      throw const FormatException('数方存档不合法');
    }
    final puzzle = ShikakuPuzzle._(size, clues, solution);
    final hinted = {
      for (final r in json['hinted'] as List? ?? const [])
        ShikakuRect.fromJson(r as List),
    };
    for (final r in hinted) {
      if (solution.contains(r) && puzzle._hinted.length < maxHints) {
        puzzle._hinted.add(r);
        puzzle._rects.add(r);
      }
    }
    for (final raw in json['rects'] as List? ?? const []) {
      final r = ShikakuRect.fromJson(raw as List);
      if (_inBounds(size, r) && !puzzle._rects.any((e) => e.overlaps(r))) {
        puzzle._rects.add(r);
      }
    }
    return puzzle;
  }

  Map<String, dynamic> toJson() => {
    'size': size,
    'clues': clues,
    'solution': [for (final r in _solution) r.toJson()],
    'rects': [
      for (final r in _rects)
        if (!_hinted.contains(r)) r.toJson(),
    ],
    if (_hinted.isNotEmpty) 'hinted': [for (final r in _hinted) r.toJson()],
  };

  final int size;

  /// 每格的数字线索，0 表示无数字。
  final List<int> clues;
  final List<ShikakuRect> _solution;

  final List<ShikakuRect> _rects = [];
  final Set<ShikakuRect> _hinted = {};

  int get cellCount => size * size;
  int get clueCount => _solution.length;
  List<ShikakuRect> get rects => List.unmodifiable(_rects);
  List<ShikakuRect> get solution => List.unmodifiable(_solution);

  int get hintsUsed => _hinted.length;
  int get hintsLeft => maxHints - _hinted.length;
  bool isHinted(ShikakuRect r) => _hinted.contains(r);

  /// 已正确划出的矩形数量。
  int get validRectCount => _rects.where(isRectValid).length;

  /// 已覆盖的格子总数。
  int get coveredCells => _rects.fold(0, (s, r) => s + r.area);

  bool get solved =>
      coveredCells == cellCount &&
      _rects.length == _solution.length &&
      _rects.every(isRectValid);

  /// 某个矩形是否满足“恰好含一个数字，且面积等于该数字”。
  bool isRectValid(ShikakuRect rect) {
    var found = 0;
    var clueValue = 0;
    for (var r = rect.r1; r <= rect.r2; r++) {
      for (var c = rect.c1; c <= rect.c2; c++) {
        final v = clues[r * size + c];
        if (v > 0) {
          if (++found > 1) return false;
          clueValue = v;
        }
      }
    }
    return found == 1 && clueValue == rect.area;
  }

  /// 查找当前覆盖 `(r, c)` 的矩形。
  ShikakuRect? rectAt(int r, int c) {
    for (final rect in _rects) {
      if (rect.contains(r, c)) return rect;
    }
    return null;
  }

  /// 放置一个新矩形：自动替换与之重叠的普通矩形；若与提示锁定的矩形重叠则忽略。
  bool place(ShikakuRect rect) {
    if (solved || !_inBounds(size, rect)) return false;
    if (_hinted.any((h) => h.overlaps(rect))) return false;
    // 完全相同的普通矩形再画一次视为保留（单击由 removeAt 负责移除）
    if (_rects.contains(rect)) return false;
    _rects
      ..removeWhere((e) => e.overlaps(rect))
      ..add(rect);
    return true;
  }

  /// 移除包含 `(r, c)` 的普通矩形（提示锁定的矩形不可移除）。
  bool removeAt(int r, int c) {
    if (solved) return false;
    final target = rectAt(r, c);
    if (target == null || _hinted.contains(target)) return false;
    _rects.remove(target);
    return true;
  }

  /// 使用一次提示：画出并锁定覆盖第 [cell] 格的正确矩形。
  bool applyHint(int cell) {
    if (solved || hintsLeft <= 0 || cell < 0 || cell >= cellCount) return false;
    final r = cell ~/ size, c = cell % size;
    final answer = _solution.firstWhere((rect) => rect.contains(r, c));
    if (_hinted.contains(answer)) return false;
    _rects
      ..removeWhere((e) => e.overlaps(answer))
      ..add(answer);
    _hinted.add(answer);
    return true;
  }

  static bool _inBounds(int size, ShikakuRect r) =>
      r.r1 >= 0 && r.c1 >= 0 && r.r2 < size && r.c2 < size;

  static bool _validPartition(
    int size,
    List<int> clues,
    List<ShikakuRect> rects,
  ) {
    final covered = List<bool>.filled(size * size, false);
    for (final rect in rects) {
      if (!_inBounds(size, rect)) return false;
      var clueSum = 0, clueCnt = 0;
      for (var r = rect.r1; r <= rect.r2; r++) {
        for (var c = rect.c1; c <= rect.c2; c++) {
          final idx = r * size + c;
          if (covered[idx]) return false;
          covered[idx] = true;
          if (clues[idx] > 0) {
            clueCnt++;
            clueSum = clues[idx];
          }
        }
      }
      if (clueCnt != 1 || clueSum != rect.area) return false;
    }
    return covered.every((v) => v);
  }

  static List<ShikakuRect>? _randomTiling(int size, int maxArea, Random rng) {
    final n = size * size;
    final covered = List<bool>.filled(n, false);
    final rects = <ShikakuRect>[];

    bool hasIsolatedSingleHole() {
      for (var i = 0; i < n; i++) {
        if (covered[i]) continue;
        final r = i ~/ size, c = i % size;
        final hasOpenNeighbor =
            (r > 0 && !covered[i - size]) ||
            (r < size - 1 && !covered[i + size]) ||
            (c > 0 && !covered[i - 1]) ||
            (c < size - 1 && !covered[i + 1]);
        if (!hasOpenNeighbor) return true;
      }
      return false;
    }

    for (var i = 0; i < n; i++) {
      if (covered[i]) continue;
      final r = i ~/ size, c = i % size;
      final candidates = <ShikakuRect>[];
      for (var h = 1; r + h <= size && h <= maxArea; h++) {
        for (var w = 1; c + w <= size && w * h <= maxArea; w++) {
          if (w * h < 2) continue;
          final rect = ShikakuRect(r, c, r + h - 1, c + w - 1);
          var clear = true;
          for (var rr = rect.r1; rr <= rect.r2 && clear; rr++) {
            for (var cc = rect.c1; cc <= rect.c2; cc++) {
              if (covered[rr * size + cc]) {
                clear = false;
                break;
              }
            }
          }
          if (clear) {
            candidates.add(rect);
            // 适度偏爱 ≥3 格的矩形，减少满盘 1×2 骨牌并提升因数推理趣味
            if (rect.area >= 3) candidates.add(rect);
          }
        }
      }
      if (candidates.isEmpty) return null;
      shuffleWith(candidates, rng);
      ShikakuRect? chosen;
      for (final cand in candidates) {
        for (var rr = cand.r1; rr <= cand.r2; rr++) {
          for (var cc = cand.c1; cc <= cand.c2; cc++) {
            covered[rr * size + cc] = true;
          }
        }
        if (!hasIsolatedSingleHole()) {
          chosen = cand;
          break;
        }
        for (var rr = cand.r1; rr <= cand.r2; rr++) {
          for (var cc = cand.c1; cc <= cand.c2; cc++) {
            covered[rr * size + cc] = false;
          }
        }
      }
      if (chosen == null) return null;
      rects.add(chosen);
    }
    return rects;
  }
}

/// 统计数方谜题的解数（最多数到 [limit] 种即停；超出 [budget] 返回 null）。
int? countShikakuSolutions(
  int size,
  List<int> clues, {
  int limit = 2,
  int budget = 20000,
}) {
  final n = size * size;
  final clueCells = <int>[
    for (var i = 0; i < n; i++)
      if (clues[i] > 0) i,
  ];
  final m = clueCells.length;
  var areaSum = 0;
  for (final i in clueCells) {
    areaSum += clues[i];
  }
  if (areaSum != n) return 0;

  // 为每个数字枚举所有合法候选矩形（面积匹配、包含自身、不含其他数字）
  final candidates = List<List<ShikakuRect>>.generate(m, (idx) {
    final cell = clueCells[idx];
    final cr = cell ~/ size, cc = cell % size;
    final target = clues[cell];
    final list = <ShikakuRect>[];
    for (var h = 1; h <= target && h <= size; h++) {
      if (target % h != 0) continue;
      final w = target ~/ h;
      if (w > size) continue;
      final rMin = max(0, cr - h + 1), rMax = min(cr, size - h);
      final cMin = max(0, cc - w + 1), cMax = min(cc, size - w);
      for (var r1 = rMin; r1 <= rMax; r1++) {
        for (var c1 = cMin; c1 <= cMax; c1++) {
          final rect = ShikakuRect(r1, c1, r1 + h - 1, c1 + w - 1);
          var otherClue = false;
          for (var r = rect.r1; r <= rect.r2 && !otherClue; r++) {
            for (var c = rect.c1; c <= rect.c2; c++) {
              final k = r * size + c;
              if (k != cell && clues[k] > 0) {
                otherClue = true;
                break;
              }
            }
          }
          if (!otherClue) list.add(rect);
        }
      }
    }
    return list;
  });

  var solutions = 0;
  var nodes = 0;
  var exhausted = false;

  void search(List<bool> covered, List<List<ShikakuRect>> avail) {
    if (solutions >= limit || exhausted) return;
    if (++nodes > budget) {
      exhausted = true;
      return;
    }

    final nextCovered = List<bool>.of(covered);
    final nextAvail = <List<ShikakuRect>>[
      for (final a in avail) List<ShikakuRect>.of(a),
    ];

    bool commit(int clueIdx, ShikakuRect rect) {
      for (var r = rect.r1; r <= rect.r2; r++) {
        for (var c = rect.c1; c <= rect.c2; c++) {
          final idx = r * size + c;
          if (nextCovered[idx]) return false;
          nextCovered[idx] = true;
        }
      }
      nextAvail[clueIdx] = const [];
      for (var j = 0; j < m; j++) {
        if (nextAvail[j].isEmpty) continue;
        nextAvail[j].removeWhere((cand) => cand.overlaps(rect));
        if (nextAvail[j].isEmpty) return false;
      }
      return true;
    }

    // 约束传播：单候选数字直接确定；只有一个候选能盖住的空格也直接确定
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < m; i++) {
        final list = nextAvail[i];
        if (list.length == 1) {
          if (!commit(i, list.first)) return;
          changed = true;
        }
      }
      for (var cell = 0; cell < n; cell++) {
        if (nextCovered[cell]) continue;
        final r = cell ~/ size, c = cell % size;
        var hitClue = -1;
        ShikakuRect? hitRect;
        var ways = 0;
        for (var i = 0; i < m && ways <= 1; i++) {
          for (final cand in nextAvail[i]) {
            if (cand.contains(r, c)) {
              hitClue = i;
              hitRect = cand;
              if (++ways > 1) break;
            }
          }
        }
        if (ways == 0) return;
        if (ways == 1) {
          if (!commit(hitClue, hitRect!)) return;
          changed = true;
        }
      }
    }

    var bestClue = -1;
    var bestLen = 999999;
    for (var i = 0; i < m; i++) {
      final len = nextAvail[i].length;
      if (len > 0 && len < bestLen) {
        bestClue = i;
        bestLen = len;
      }
    }
    if (bestClue == -1) {
      if (nextCovered.every((v) => v)) solutions++;
      return;
    }

    for (final cand in List<ShikakuRect>.of(nextAvail[bestClue])) {
      final branchCovered = List<bool>.of(nextCovered);
      final branchAvail = <List<ShikakuRect>>[
        for (var i = 0; i < m; i++)
          i == bestClue
              ? <ShikakuRect>[cand]
              : List<ShikakuRect>.of(nextAvail[i]),
      ];
      search(branchCovered, branchAvail);
      if (solutions >= limit || exhausted) return;
    }
  }

  if (candidates.any((c) => c.isEmpty)) return 0;
  search(List<bool>.filled(n, false), candidates);
  return exhausted ? null : solutions;
}
