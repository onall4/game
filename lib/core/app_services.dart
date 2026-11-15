import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data/repositories/game_record_repository.dart';
import 'data/repositories/player_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/sync/result_outbox.dart';
import 'data/sync/sync_service.dart';
import 'storage/key_value_store.dart';
import 'storage/shared_prefs_store.dart';
import 'storage/storage_migrator.dart';

/// 应用级依赖容器：所有页面通过 [AppScope.of] 拿到这里的服务。
class AppServices {
  AppServices({
    required this.store,
    required this.player,
    required this.records,
    required this.settings,
    required this.outbox,
    required this.sync,
  }) : haptics = Haptics(settings);

  /// 生产环境：本地 shared_preferences + 离线同步。
  ///
  /// 接入服务器时，把下面的 [OfflineSyncService] 换成 [RemoteSyncService]。
  static Future<AppServices> create() async {
    final store = await SharedPrefsStore.open();
    return fromStore(store);
  }

  static Future<AppServices> fromStore(KeyValueStore store) async {
    await StorageMigrator(store).run();
    final outbox = ResultOutbox(store);
    final player = LocalPlayerRepository(store);
    final records = LocalGameRecordRepository(store, outbox);
    final settings = SettingsRepository(store);
    return AppServices(
      store: store,
      player: player,
      records: records,
      settings: settings,
      outbox: outbox,
      sync: const OfflineSyncService(),
    );
  }

  final KeyValueStore store;
  final PlayerRepository player;
  final GameRecordRepository records;
  final SettingsRepository settings;
  final ResultOutbox outbox;
  final SyncService sync;
  final Haptics haptics;

  /// 清空全部游戏记录（保留玩家 ID 与设置）。
  Future<void> resetProgress() async {
    await records.clear();
    await outbox.clear();
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未找到');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

/// 统一的触感反馈入口，受设置开关控制。
class Haptics {
  Haptics(this._settings);

  final SettingsRepository _settings;

  void tap() {
    if (_settings.haptics) HapticFeedback.selectionClick();
  }

  void light() {
    if (_settings.haptics) HapticFeedback.lightImpact();
  }

  void success() {
    if (_settings.haptics) HapticFeedback.mediumImpact();
  }

  void error() {
    if (_settings.haptics) HapticFeedback.heavyImpact();
  }
}
