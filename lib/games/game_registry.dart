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
      // 模式 ID 会作为存储键：5×5/6×6/7×7 沿用最早的 ID，保留历史纪录
      GameMode(id: 'size4', label: '4×4', description: '入门'),
      GameMode(id: 'easy', label: '5×5', description: '简单'),
      GameMode(id: 'normal', label: '6×6', description: '进阶'),
      GameMode(id: 'hard', label: '7×7', description: '困难'),
      GameMode(id: 'size8', label: '8×8', description: '烧脑'),
      GameMode(id: 'size9', label: '9×9', description: '专家'),
      GameMode(id: 'size10', label: '10×10', description: '大师'),
    ],
    rules: const [
      '中央的闪电是电源，每个格子里都是一段导线。',
      '点击格子可将导线顺时针旋转 90°。',
      '让所有导线首尾相接、全部通电（变成黄色）即可过关。',
      '每局电路随机生成，并且只有唯一一种正确接法，可以完全靠推理解开。',
      '卡住时可以用「提示」：每局 3 次，点选一块格子，它会被转到正确方向并锁定。',
      '用时越短成绩越好；使用过提示的对局不计入最佳纪录。',
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
      // 每档大约难 3~7 倍（按可能的密码组合数计）；easy/normal/hard6 沿用旧 ID
      GameMode(id: 'easy', label: '入门', description: '3 位 · 数字 1–6 · 不重复'),
      GameMode(id: 'lv2', label: '简单', description: '4 位 · 数字 1–6 · 不重复'),
      GameMode(id: 'lv3', label: '进阶', description: '4 位 · 数字 1–8 · 不重复'),
      GameMode(id: 'normal', label: '普通', description: '4 位 · 数字 0–9 · 不重复'),
      GameMode(id: 'lv5', label: '困难', description: '5 位 · 数字 0–9 · 不重复'),
      GameMode(id: 'lv6', label: '专家', description: '6 位 · 数字 0–9 · 不重复'),
      GameMode(id: 'hard6', label: '大师', description: '6 位 · 数字 0–9 · 可重复'),
    ],
    rules: const [
      '保险箱有一个隐藏的数字密码，猜中它就能开锁，不限次数。',
      '点选下方的格子决定填哪一位，输入一组数字后点击「试开」，右侧会出现两个圆点和数字：',
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
      GameMode(id: 'm20', label: '20 张', description: '进阶 · 10 对卡牌'),
      GameMode(id: 'm24', label: '24 张', description: '困难 · 12 对卡牌'),
      GameMode(id: 'hard', label: '30 张', description: '挑战 · 15 对卡牌'),
      GameMode(id: 'm36', label: '36 张', description: '大师 · 18 对卡牌'),
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
