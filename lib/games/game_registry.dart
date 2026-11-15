import '../core/data/models/score_kind.dart';
import '../ui/theme/app_theme.dart';
import 'circuit/circuit_page.dart';
import 'codebreaker/codebreaker_page.dart';
import 'game_definition.dart';
import 'memory/memory_page.dart';

/// 所有已上架的小游戏。首页按此顺序展示。
final List<GameDefinition> gameRegistry = [
  GameDefinition(
    id: 'circuit',
    title: '回路',
    tagline: '旋转导线，点亮每一盏灯',
    category: GameCategory.puzzle,
    color: AppColors.mint,
    scoreKind: ScoreKind.timeMs,
    modes: const [
      GameMode(id: 'easy', label: '5×5', description: '入门 · 5×5 电路板'),
      GameMode(id: 'normal', label: '6×6', description: '进阶 · 6×6 电路板'),
      GameMode(id: 'hard', label: '7×7', description: '烧脑 · 7×7 电路板'),
    ],
    rules: const [
      '中央的闪电是电源，每个格子里都是一段导线。',
      '点击格子可将导线顺时针旋转 90°。',
      '让所有导线首尾相接、全部通电（变成黄色）即可过关。',
      '长按格子可以锁定它，防止误触；再次长按解锁。',
      '每局电路随机生成，用时越短成绩越好。',
    ],
    builder: (context, session) => CircuitGame(session: session),
    coverBuilder: (context) => const CircuitCover(),
  ),
  GameDefinition(
    id: 'codebreaker',
    title: '密码锁',
    tagline: '根据线索，推理出保险箱密码',
    category: GameCategory.decode,
    color: AppColors.lavender,
    scoreKind: ScoreKind.attempts,
    modes: const [
      GameMode(id: 'easy', label: '简单', description: '3 位 · 数字 1–6 · 8 次机会'),
      GameMode(id: 'normal', label: '普通', description: '4 位不重复 · 0–9 · 10 次机会'),
      GameMode(id: 'hard', label: '困难', description: '4 位可重复 · 0–9 · 8 次机会'),
    ],
    rules: const [
      '保险箱有一个隐藏的数字密码。',
      '输入一组猜测并点击「试开」，会得到两种提示：',
      '绿色圆点（A）：有一个数字猜对了，且位置也正确。',
      '黄色圆点（B）：有一个数字存在于密码中，但位置不对。',
      '提示圆点不对应具体位置，需要你综合多次线索推理。',
      '长按数字键可标记为“已排除”，帮助你整理思路。',
      '用尽机会前猜中即可开锁，次数越少成绩越好。',
    ],
    builder: (context, session) => CodeBreakerGameView(session: session),
    coverBuilder: (context) => const CodeBreakerCover(),
  ),
  GameDefinition(
    id: 'memory',
    title: '翻翻乐',
    tagline: '翻开卡牌，找出所有相同的一对',
    category: GameCategory.casual,
    color: AppColors.pink,
    scoreKind: ScoreKind.moves,
    modes: const [
      GameMode(id: 'easy', label: '12 张', description: '轻松 · 6 对卡牌'),
      GameMode(id: 'normal', label: '16 张', description: '标准 · 8 对卡牌'),
      GameMode(id: 'hard', label: '30 张', description: '挑战 · 15 对卡牌'),
    ],
    rules: const [
      '每次翻开两张卡牌。',
      '图案相同则配对成功并保持翻开，不同则会自动盖回。',
      '连续配对成功可以触发连击。',
      '找出全部配对即可过关，翻牌步数越少成绩越好。',
    ],
    builder: (context, session) => MemoryGameView(session: session),
    coverBuilder: (context) => const MemoryCover(),
  ),
];
