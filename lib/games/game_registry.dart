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
      GameMode(id: 'easy', label: '简单', description: '3 位 · 数字 1–6 · 不重复'),
      GameMode(id: 'normal', label: '普通', description: '4 位 · 数字 0–9 · 不重复'),
      GameMode(id: 'hard', label: '困难', description: '4 位 · 数字 0–9 · 可重复'),
    ],
    rules: const [
      '保险箱有一个隐藏的数字密码，猜中它就能开锁，不限次数。',
      '输入一组数字并点击「试开」，右侧会出现两个圆点和数字：',
      '绿点「位置对」：有几个数字猜对了，而且位置也对。',
      '黄点「数字对」：有几个数字在密码里，但位置不对。',
      '例如密码是 1 2 3，你猜 1 3 5：1 的位置对，3 在密码里但位置不对，'
          '5 不在密码里，所以显示绿点 1、黄点 1。',
      '提示只告诉你数量，不告诉你是哪一位，需要结合多次结果推理。',
      '长按数字键可以把它标记为“已排除”，帮你整理思路。',
      '试开次数越少，成绩越好。',
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
