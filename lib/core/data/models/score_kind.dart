/// 一个游戏模式用哪种指标记录成绩。
enum ScoreKind {
  /// 用时（毫秒），越少越好。显示到秒。
  timeMs(lowerIsBetter: true, label: '用时'),

  /// 用时（毫秒），越少越好。显示到 0.01 秒，用于几秒内就能完成的游戏。
  preciseTimeMs(lowerIsBetter: true, label: '用时'),

  /// 尝试次数，越少越好。
  attempts(lowerIsBetter: true, label: '次数'),

  /// 步数，越少越好。
  moves(lowerIsBetter: true, label: '步数'),

  /// 得分，越高越好。
  points(lowerIsBetter: false, label: '得分');

  const ScoreKind({required this.lowerIsBetter, required this.label});

  final bool lowerIsBetter;
  final String label;

  bool isBetter(int candidate, int? current) {
    if (current == null) return true;
    return lowerIsBetter ? candidate < current : candidate > current;
  }

  String format(int value) => switch (this) {
    ScoreKind.timeMs => formatDuration(value),
    ScoreKind.preciseTimeMs => formatPreciseDuration(value),
    ScoreKind.attempts => '$value 次',
    ScoreKind.moves => '$value 步',
    ScoreKind.points => '$value 分',
  };
}

/// 精确到 0.01 秒：一分钟内显示「12.34 秒」，否则「1:05.20」。
String formatPreciseDuration(int ms) {
  final centis = ms ~/ 10;
  final seconds = centis ~/ 100;
  final cc = (centis % 100).toString().padLeft(2, '0');
  if (seconds < 60) return '$seconds.$cc 秒';
  final ss = (seconds % 60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}:$ss.$cc';
}

String formatDuration(int ms) {
  final totalSeconds = ms ~/ 1000;
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
