import 'dart:math';

import 'package:flutter/widgets.dart';

import '../core/data/models/score_kind.dart';
import '../ui/theme/app_theme.dart';
import 'seed.dart';

enum GameCategory {
  puzzle('益智', AppColors.mint),
  decode('解密', AppColors.lavender),
  casual('休闲', AppColors.pink),
  focus('专注', AppColors.sky),
  math('计算', AppColors.coral);

  const GameCategory(this.label, this.color);

  final String label;
  final Color color;
}

/// 游戏的一个模式/难度。
class GameMode {
  const GameMode({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

/// 一局结束时由具体游戏上报给外壳的数据。
class GameFinish {
  const GameFinish({
    required this.won,
    required this.score,
    required this.durationMs,
    this.details = const [],
    this.message,
    this.assisted = false,
  });

  factory GameFinish.fromJson(Map<String, dynamic> json) => GameFinish(
    won: json['won'] as bool,
    score: json['score'] as int,
    durationMs: json['durationMs'] as int,
    details: [
      for (final d in json['details'] as List? ?? const [])
        ((d as List)[0] as String, d[1] as String),
    ],
    message: json['message'] as String?,
    assisted: json['assisted'] as bool? ?? false,
  );

  final bool won;
  final int score;
  final int durationMs;

  /// 结算页额外展示的数据，如 ("步数", "32")。
  final List<(String, String)> details;

  /// 结算页副标题，如失败时揭晓答案。
  final String? message;

  /// 是否借助提示完成（不刷新最佳纪录）。
  final bool assisted;

  Map<String, dynamic> toJson() => {
    'won': won,
    'score': score,
    'durationMs': durationMs,
    'details': [
      for (final (label, value) in details) [label, value],
    ],
    if (message != null) 'message': message,
    if (assisted) 'assisted': true,
  };
}

/// 外壳传给具体游戏的上下文。
class GameSession {
  const GameSession({
    required this.mode,
    required this.onFinish,
    required this.saveProgress,
    this.savedState,
    this.seed,
  });

  final GameMode mode;

  /// 本局的种子。恢复旧版（还没有种子的）存档时为 null。
  final GameSeed? seed;

  /// 开新局时用来生成开局的随机数：同一种子、同一难度得到同一串数。
  Random createRandom() {
    final s = seed;
    return s == null ? Random() : SeededRandom.forGame(s, mode.id);
  }

  final void Function(GameFinish finish) onFinish;

  /// 上次的对局状态（由 [saveProgress] 保存，可能是已完成的对局）；
  /// 为 null 时开始新游戏。内容格式由各游戏自行定义，解析失败时应直接开始新游戏。
  /// 恢复出已完成的对局时，游戏应保持完成画面且不要再调用 [onFinish]。
  final Map<String, dynamic>? savedState;

  /// 保存当前对局状态。游戏应在每步操作后（包括完成的那一步，且要在
  /// [onFinish] 之前）以及离开页面（dispose）时调用。
  final void Function(Map<String, dynamic> state) saveProgress;
}

/// 在首页注册一个小游戏所需的全部信息。新增游戏只需：
/// 1. 在 `lib/games/<name>/` 下实现逻辑与页面；
/// 2. 在 `game_registry.dart` 中追加一个 [GameDefinition]。
class GameDefinition {
  const GameDefinition({
    required this.id,
    required this.title,
    required this.tagline,
    required this.category,
    required this.color,
    required this.scoreKind,
    required this.modes,
    required this.rules,
    required this.builder,
    required this.coverBuilder,
    this.seedVersion = 1,
  });

  /// 稳定的唯一 ID，会作为存储键和服务器字段，发布后不要修改。
  final String id;
  final String title;
  final String tagline;
  final GameCategory category;
  final Color color;
  final ScoreKind scoreKind;
  final List<GameMode> modes;
  final List<String> rules;
  final Widget Function(BuildContext context, GameSession session) builder;
  final WidgetBuilder coverBuilder;

  /// 开局生成规则的版本，写在种子的第一位。
  ///
  /// 只要改动会让同一个种子生成出不同的开局（生成算法、[SeededRandom]、
  /// 翻翻乐的图案数量等），就必须 +1；`test/seed_test.dart` 里的
  /// 固定开局测试会在这种改动时失败，提醒这一点。
  final int seedVersion;

  GameMode modeById(String? id) =>
      modes.firstWhere((m) => m.id == id, orElse: () => modes.first);
}
