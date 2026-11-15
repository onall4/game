import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../games/game_definition.dart';
import '../../games/game_registry.dart';
import '../game/game_page.dart';
import '../settings/settings_page.dart';
import '../theme/app_theme.dart';
import '../widgets/chunky.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GameCategory? _filter;

  void _open(GameDefinition game) {
    AppScope.of(context).haptics.tap();
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => GamePage(game: game)));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final games = _filter == null
        ? gameRegistry
        : gameRegistry.where((g) => g.category == _filter).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([services.records, services.player]),
          builder: (context, _) => CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverList.list(
                  children: [
                    _Header(nickname: services.player.profile.nickname),
                    const SizedBox(height: 20),
                    _StatsBanner(services: services),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Text('全部游戏', style: AppText.title),
                        const SizedBox(width: 8),
                        Text('${gameRegistry.length}', style: AppText.caption),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _CategoryFilter(
                      selected: _filter,
                      onSelect: (c) {
                        services.haptics.tap();
                        setState(() => _filter = c);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.separated(
                  itemCount: games.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) =>
                      _GameCard(game: games[i], onTap: () => _open(games[i])),
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 32),
                sliver: SliverToBoxAdapter(child: _ComingSoon()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.nickname});

  final String nickname;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: chunkyDecoration(color: AppColors.lemon, radius: 16),
          child: const Text(
            '拾',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('嗨，$nickname', style: AppText.caption),
              const SizedBox(height: 2),
              const Text('今天玩点什么？', style: AppText.display),
            ],
          ),
        ),
        ChunkyIconButton(
          icon: Icons.tune_rounded,
          tooltip: '设置',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
        ),
      ],
    );
  }
}

class _StatsBanner extends StatelessWidget {
  const _StatsBanner({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final records = services.records.all;
    final plays = records.fold(0, (s, r) => s + r.plays);
    final wins = records.fold(0, (s, r) => s + r.wins);
    final minutes = records.fold(0, (s, r) => s + r.totalDurationMs) ~/ 60000;

    return ChunkyBox(
      color: AppColors.ink,
      borderColor: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        children: [
          _stat('总对局', '$plays'),
          _divider(),
          _stat('胜利', '$wins'),
          _divider(),
          _stat('游戏时长', minutes < 1 ? '<1 分' : '$minutes 分'),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
    child: Column(
      children: [
        Text(value, style: AppText.number.copyWith(color: AppColors.lemon)),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppText.caption.copyWith(color: const Color(0xFFCFC8DE)),
        ),
      ],
    ),
  );

  Widget _divider() =>
      Container(width: 1.5, height: 30, color: const Color(0xFF4A4363));
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({required this.selected, required this.onSelect});

  final GameCategory? selected;
  final ValueChanged<GameCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = <(GameCategory?, String, Color)>[
      (null, '全部', AppColors.lemon),
      for (final c in GameCategory.values) (c, c.label, c.color),
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        clipBehavior: Clip.none,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (cat, label, color) = items[i];
          final active = cat == selected;
          return Pressable(
            onTap: () => onSelect(cat),
            color: active ? color : AppColors.paper,
            radius: 999,
            shadow: active ? 3 : 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            child: Text(
              label,
              style: AppText.subtitle.copyWith(
                fontSize: 14,
                color: active ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.onTap});

  final GameDefinition game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final record = services.records.recordOf(game.id, game.scoreKind);
    final mode = game.modeById(services.settings.lastMode(game.id));
    final best = record.mode(mode.id).best;

    return Pressable(
      onTap: onTap,
      semanticLabel: game.title,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.ink, width: AppDims.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13.5),
              child: game.coverBuilder(context),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TagChip(
                      label: game.category.label,
                      color: game.category.color,
                    ),
                    const Spacer(),
                    if (record.plays > 0)
                      Text('已玩 ${record.plays} 局', style: AppText.caption),
                  ],
                ),
                const SizedBox(height: 6),
                Text(game.title, style: AppText.title),
                const SizedBox(height: 2),
                Text(
                  game.tagline,
                  style: AppText.body.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_outlined,
                      size: 15,
                      color: AppColors.inkSoft,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        best == null
                            ? '${mode.label} · 还没有纪录'
                            : '${mode.label} · 最佳 ${game.scoreKind.format(best)}',
                        style: AppText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: game.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.ink, width: 2),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 18,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Column(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: AppColors.inkSoft),
            const SizedBox(height: 6),
            Text(
              '更多小游戏正在路上…',
              style: AppText.subtitle.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppDims.radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = AppColors.inkFaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 8), paint);
        d += 14;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
