import 'dart:math';

import '../seed.dart';

/// 舒尔特方格的一种玩法。
class SchulteConfig {
  const SchulteConfig({
    required this.size,
    this.descending = false,
    this.reshuffle = false,
  });

  /// 边长，方格里是 1 … size² 的数字。
  final int size;

  /// 倒序：从最大的数字点到 1。
  final bool descending;

  /// 洗牌：每点对一个，整张表重新排列。
  final bool reshuffle;

  int get count => size * size;
}

enum SchulteTap {
  /// 点对了
  correct,

  /// 点错了（计一次失误）
  wrong,

  /// 无效点击（已完成，或点的是已经找过的数字）
  ignored,
}

/// 舒尔特方格：打乱排列的 1 … N²，按顺序依次点出。
class SchulteGame {
  SchulteGame(this.config, {Random? random})
    : _random = random ?? Random(),
      cells = List.generate(config.count, (i) => i + 1) {
    shuffleWith(cells, _random);
    _next = config.descending ? config.count : 1;
  }

  SchulteGame._restored(this.config, this.cells, this._random);

  /// 从 [toJson] 的结果恢复；数据不合法时抛出异常。
  factory SchulteGame.fromJson(
    SchulteConfig config,
    Map<String, dynamic> json,
  ) {
    final cells = List<int>.from(json['cells'] as List);
    final sorted = [...cells]..sort();
    final valid =
        cells.length == config.count &&
        [for (var i = 0; i < sorted.length; i++) sorted[i] == i + 1]
            .every((ok) => ok);
    if (!valid) throw const FormatException('舒尔特存档与当前模式不匹配');
    final next = json['next'] as int;
    if (next < 0 || next > config.count + 1) {
      throw const FormatException('舒尔特存档进度不合法');
    }
    final state = json['rng'] as int?;
    return SchulteGame._restored(
        config,
        cells,
        state == null ? Random() : SeededRandom(state),
      )
      .._next = next
      .._mistakes = json['mistakes'] as int? ?? 0;
  }

  Map<String, dynamic> toJson() => {
    'cells': cells,
    'next': _next,
    'mistakes': _mistakes,
    // 洗牌模式要接着生成同一串随机数，才能和同一种子的其他对局保持一致
    if (_random case final SeededRandom r) 'rng': r.state,
  };

  /// 点错一次的罚时。
  static const penaltyMs = 1000;

  final SchulteConfig config;

  /// 每个位置上的数字。
  final List<int> cells;
  final Random _random;
  late int _next;
  int _mistakes = 0;

  /// 下一个该点的数字。
  int get next => _next;
  int get mistakes => _mistakes;

  int get foundCount => config.descending ? config.count - _next : _next - 1;
  bool get completed => foundCount == config.count;

  /// 这个数字是否已经点过。
  bool isFound(int number) =>
      config.descending ? number > _next : number < _next;

  SchulteTap tap(int index) {
    if (completed) return SchulteTap.ignored;
    final number = cells[index];
    if (isFound(number)) return SchulteTap.ignored;
    if (number != _next) {
      _mistakes++;
      return SchulteTap.wrong;
    }
    _next += config.descending ? -1 : 1;
    if (config.reshuffle && !completed) shuffleWith(cells, _random);
    return SchulteTap.correct;
  }
}
