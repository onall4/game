import 'package:flutter/widgets.dart';

import '../core/data/models/score_kind.dart';
import '../ui/theme/app_theme.dart';

enum GameCategory {
  puzzle('益智', AppColors.mint),
  decode('解密', AppColors.lavender),
  casual('休闲', AppColors.pink);

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
  });

  final bool won;
  final int score;
  final int durationMs;

  /// 结算页额外展示的数据，如 ("步数", "32")。
  final List<(String, String)> details;

  /// 结算页副标题，如失败时揭晓答案。
  final String? message;
}

/// 外壳传给具体游戏的上下文。
class GameSession {
  const GameSession({required this.mode, required this.onFinish});

  final GameMode mode;
  final void Function(GameFinish finish) onFinish;
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

  GameMode modeById(String? id) =>
      modes.firstWhere((m) => m.id == id, orElse: () => modes.first);
}
