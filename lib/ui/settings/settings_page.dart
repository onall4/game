import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../games/game_registry.dart';
import '../theme/app_theme.dart';
import '../widgets/chunky.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            services.settings,
            services.player,
            services.records,
          ]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(
                children: [
                  ChunkyIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: '返回',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 14),
                  const Text('设置', style: AppText.title),
                ],
              ),
              const SizedBox(height: 22),
              _ProfileCard(services: services),
              const SizedBox(height: 22),
              const _SectionTitle('偏好'),
              ChunkyBox(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.vibration_rounded, color: AppColors.ink),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('触感反馈', style: AppText.subtitle),
                    ),
                    Switch(
                      value: services.settings.haptics,
                      onChanged: services.settings.setHaptics,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle('我的纪录'),
              ChunkyBox(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < gameRegistry.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          color: AppColors.creamDeep,
                          thickness: 1.5,
                        ),
                      _GameStatsTile(gameIndex: i, services: services),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle('数据'),
              ChunkyBox(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          color: AppColors.ink,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            services.sync.isOnline ? '已连接服务器' : '本地存储模式',
                            style: AppText.subtitle,
                          ),
                        ),
                        TagChip(
                          label: '待同步 ${services.outbox.length}',
                          color: AppColors.creamDeep,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '目前所有数据都保存在本机。上线云端账号后，'
                      '本地纪录会自动同步，换手机也不会丢。',
                      style: AppText.body,
                    ),
                    const SizedBox(height: 14),
                    ChunkyButton(
                      label: '清空游戏纪录',
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.coral,
                      expand: true,
                      onTap: () => _confirmReset(context, services),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Center(child: Text('拾趣 · v0.1.0', style: AppText.caption)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, AppServices services) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ChunkyBox(
          color: AppColors.cream,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('确定清空？', style: AppText.title),
              const SizedBox(height: 8),
              const Text(
                '所有游戏的对局数与最佳纪录将被删除，且无法恢复。',
                style: AppText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ChunkyButton(
                      label: '取消',
                      color: AppColors.paper,
                      expand: true,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChunkyButton(
                      label: '清空',
                      color: AppColors.coral,
                      expand: true,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await services.resetProgress();
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      text,
      style: AppText.subtitle.copyWith(color: AppColors.inkSoft),
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final profile = services.player.profile;
    return Pressable(
      color: AppColors.lemon,
      padding: const EdgeInsets.all(16),
      onTap: () => _rename(context),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: chunkyDecoration(
              color: AppColors.paper,
              radius: 26,
              shadow: 0,
            ),
            child: const Icon(
              Icons.face_rounded,
              size: 30,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.nickname, style: AppText.title),
                const SizedBox(height: 2),
                Text(
                  'ID ${profile.playerId.substring(0, 8)} · 点击修改昵称',
                  style: AppText.caption.copyWith(color: AppColors.ink),
                ),
              ],
            ),
          ),
          const Icon(Icons.edit_rounded, color: AppColors.ink),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(
      text: services.player.profile.nickname,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ChunkyBox(
          color: AppColors.cream,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('修改昵称', style: AppText.title),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 12,
                style: AppText.subtitle,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.paper,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.ink,
                      width: 2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.ink,
                      width: 2.5,
                    ),
                  ),
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
              const SizedBox(height: 16),
              ChunkyButton(
                label: '保存',
                expand: true,
                onTap: () => Navigator.of(context).pop(controller.text),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      await services.player.update(
        services.player.profile.copyWith(nickname: trimmed),
      );
    }
  }
}

class _GameStatsTile extends StatelessWidget {
  const _GameStatsTile({required this.gameIndex, required this.services});

  final int gameIndex;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final game = gameRegistry[gameIndex];
    final record = services.records.recordOf(game.id, game.scoreKind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: game.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.ink, width: 1.8),
                ),
              ),
              const SizedBox(width: 8),
              Text(game.title, style: AppText.subtitle),
              const Spacer(),
              Text(
                '${record.plays} 局 · 胜 ${record.wins}',
                style: AppText.caption,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final m in game.modes)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.label,
                        style: AppText.caption.copyWith(fontSize: 11),
                      ),
                      Text(
                        record.mode(m.id).best == null
                            ? '—'
                            : game.scoreKind.format(record.mode(m.id).best!),
                        style: AppText.number.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
