import 'dart:math';

import 'score_kind.dart';

/// 单局游戏结束后产生的结果。
///
/// 这是不可变的“事件”，既用于更新本地的 [GameRecord]，
/// 也会写入待同步队列，将来上传给服务器做排行榜 / 数据分析。
class GameResult {
  GameResult({
    required this.gameId,
    required this.modeId,
    required this.won,
    required this.score,
    required this.scoreKind,
    required this.durationMs,
    this.assisted = false,
    DateTime? playedAt,
    String? id,
  }) : playedAt = playedAt ?? DateTime.now(),
       id = id ?? _newId();

  factory GameResult.fromJson(Map<String, dynamic> json) => GameResult(
    id: json['id'] as String,
    gameId: json['gameId'] as String,
    modeId: json['modeId'] as String,
    won: json['won'] as bool,
    score: json['score'] as int,
    scoreKind: ScoreKind.values.byName(json['scoreKind'] as String),
    durationMs: json['durationMs'] as int,
    assisted: json['assisted'] as bool? ?? false,
    playedAt: DateTime.parse(json['playedAt'] as String),
  );

  /// 本地生成的唯一 ID，上传时作为幂等键，避免重复提交。
  final String id;
  final String gameId;
  final String modeId;
  final bool won;
  final int score;
  final ScoreKind scoreKind;
  final int durationMs;

  /// 是否借助了提示完成。借助提示的对局计入局数与胜场，但不刷新最佳纪录。
  final bool assisted;
  final DateTime playedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'gameId': gameId,
    'modeId': modeId,
    'won': won,
    'score': score,
    'scoreKind': scoreKind.name,
    'durationMs': durationMs,
    if (assisted) 'assisted': true,
    'playedAt': playedAt.toIso8601String(),
  };

  static final _rng = Random();
  static String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = _rng.nextInt(0x7fffffff).toRadixString(36);
    return '$t-$r';
  }
}
