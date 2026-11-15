/// 一个游戏模式用哪种指标记录成绩。
enum ScoreKind {
  /// 用时（毫秒），越少越好。
  timeMs(lowerIsBetter: true, label: '用时'),

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
    ScoreKind.attempts => '$value 次',
    ScoreKind.moves => '$value 步',
    ScoreKind.points => '$value 分',
  };
}

String formatDuration(int ms) {
  final totalSeconds = ms ~/ 1000;
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
