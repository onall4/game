import 'game_result.dart';
import 'score_kind.dart';

/// 某个游戏在某个模式（难度）下的累计统计。
class ModeStats {
  const ModeStats({
    this.plays = 0,
    this.wins = 0,
    this.best,
    this.totalDurationMs = 0,
  });

  factory ModeStats.fromJson(Map<String, dynamic> json) => ModeStats(
    plays: json['plays'] as int? ?? 0,
    wins: json['wins'] as int? ?? 0,
    best: json['best'] as int?,
    totalDurationMs: json['totalDurationMs'] as int? ?? 0,
  );

  final int plays;
  final int wins;

  /// 最佳成绩（仅统计获胜的对局），含义由 [ScoreKind] 决定。
  final int? best;
  final int totalDurationMs;

  ModeStats apply(GameResult r) => ModeStats(
    plays: plays + 1,
    wins: wins + (r.won ? 1 : 0),
    best: r.won && !r.assisted && r.scoreKind.isBetter(r.score, best)
        ? r.score
        : best,
    totalDurationMs: totalDurationMs + r.durationMs,
  );

  /// 与服务器数据合并：计数取较大值，最佳成绩取更优者。
  ModeStats merge(ModeStats other, ScoreKind kind) {
    int? mergedBest = best;
    if (other.best != null && kind.isBetter(other.best!, best)) {
      mergedBest = other.best;
    }
    return ModeStats(
      plays: plays > other.plays ? plays : other.plays,
      wins: wins > other.wins ? wins : other.wins,
      best: mergedBest,
      totalDurationMs: totalDurationMs > other.totalDurationMs
          ? totalDurationMs
          : other.totalDurationMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'plays': plays,
    'wins': wins,
    if (best != null) 'best': best,
    'totalDurationMs': totalDurationMs,
  };
}

/// 单个游戏的全部本地记录。
class GameRecord {
  const GameRecord({
    required this.gameId,
    required this.scoreKind,
    this.modes = const {},
    this.lastPlayedAt,
    required this.updatedAt,
    this.dirty = false,
  });

  factory GameRecord.empty(String gameId, ScoreKind kind) => GameRecord(
    gameId: gameId,
    scoreKind: kind,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  factory GameRecord.fromJson(Map<String, dynamic> json) {
    final modesJson = (json['modes'] as Map?)?.cast<String, dynamic>() ?? {};
    return GameRecord(
      gameId: json['gameId'] as String,
      scoreKind: ScoreKind.values.byName(json['scoreKind'] as String),
      modes: modesJson.map(
        (k, v) => MapEntry(k, ModeStats.fromJson((v as Map).cast())),
      ),
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dirty: json['dirty'] as bool? ?? false,
    );
  }

  final String gameId;
  final ScoreKind scoreKind;
  final Map<String, ModeStats> modes;
  final DateTime? lastPlayedAt;

  /// 最后一次修改时间，用于与服务器做冲突判断。
  final DateTime updatedAt;

  /// 是否有尚未同步到服务器的本地修改。
  final bool dirty;

  int get plays => modes.values.fold(0, (s, m) => s + m.plays);
  int get wins => modes.values.fold(0, (s, m) => s + m.wins);
  int get totalDurationMs =>
      modes.values.fold(0, (s, m) => s + m.totalDurationMs);

  ModeStats mode(String modeId) => modes[modeId] ?? const ModeStats();

  GameRecord apply(GameResult r) {
    final now = DateTime.now();
    return GameRecord(
      gameId: gameId,
      scoreKind: scoreKind,
      modes: {...modes, r.modeId: mode(r.modeId).apply(r)},
      lastPlayedAt: r.playedAt,
      updatedAt: now,
      dirty: true,
    );
  }

  GameRecord merge(GameRecord remote) {
    final keys = {...modes.keys, ...remote.modes.keys};
    return GameRecord(
      gameId: gameId,
      scoreKind: scoreKind,
      modes: {
        for (final k in keys) k: mode(k).merge(remote.mode(k), scoreKind),
      },
      lastPlayedAt: _later(lastPlayedAt, remote.lastPlayedAt),
      updatedAt: _later(updatedAt, remote.updatedAt)!,
      dirty: false,
    );
  }

  GameRecord copyWith({bool? dirty}) => GameRecord(
    gameId: gameId,
    scoreKind: scoreKind,
    modes: modes,
    lastPlayedAt: lastPlayedAt,
    updatedAt: updatedAt,
    dirty: dirty ?? this.dirty,
  );

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'scoreKind': scoreKind.name,
    'modes': modes.map((k, v) => MapEntry(k, v.toJson())),
    if (lastPlayedAt != null) 'lastPlayedAt': lastPlayedAt!.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'dirty': dirty,
  };

  static DateTime? _later(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}
