import 'package:flutter/foundation.dart';

import '../repositories/game_record_repository.dart';
import '../repositories/player_repository.dart';
import 'remote_game_api.dart';
import 'result_outbox.dart';

class SyncReport {
  const SyncReport({
    required this.performed,
    this.pushedRecords = 0,
    this.pulledRecords = 0,
    this.submittedResults = 0,
    this.error,
  });

  const SyncReport.skipped() : this(performed: false);

  final bool performed;
  final int pushedRecords;
  final int pulledRecords;
  final int submittedResults;
  final Object? error;

  bool get ok => error == null;
}

/// 本地数据与服务器之间的同步策略。
abstract class SyncService {
  /// 是否已接入服务器。
  bool get isOnline;

  /// 执行一次同步。建议在应用启动、回到前台、一局结束后调用。
  Future<SyncReport> sync();
}

/// 当前阶段使用：纯本地，不做任何网络请求。
class OfflineSyncService implements SyncService {
  const OfflineSyncService();

  @override
  bool get isOnline => false;

  @override
  Future<SyncReport> sync() async => const SyncReport.skipped();
}

/// 接入服务器后使用的同步实现（先推后拉）：
/// 1. 若玩家尚未在服务器注册，先注册拿到 remoteUserId；
/// 2. 上传 outbox 中的对局结果（幂等）；
/// 3. 上传有本地修改的记录；
/// 4. 拉取服务器记录并合并（计数取大、最佳取优）。
class RemoteSyncService implements SyncService {
  RemoteSyncService({
    required this.api,
    required this.player,
    required this.records,
    required this.outbox,
  });

  final RemoteGameApi api;
  final PlayerRepository player;
  final GameRecordRepository records;
  final ResultOutbox outbox;

  bool _running = false;

  @override
  bool get isOnline => true;

  @override
  Future<SyncReport> sync() async {
    if (_running) return const SyncReport.skipped();
    _running = true;
    try {
      var profile = player.profile;
      if (!profile.isLinkedToServer) {
        profile = await api.registerPlayer(profile);
        await player.update(profile);
      }
      final id = profile.playerId;

      final pending = outbox.peekAll();
      var submitted = 0;
      if (pending.isNotEmpty) {
        final accepted = await api.submitResults(id, pending);
        await outbox.remove(accepted);
        submitted = accepted.length;
      }

      final dirty = records.dirtyRecords;
      if (dirty.isNotEmpty) {
        await api.pushRecords(id, dirty);
        await records.markSynced(dirty.map((r) => r.gameId));
      }

      final remote = await api.fetchRecords(id);
      await records.mergeRemote(remote);

      return SyncReport(
        performed: true,
        pushedRecords: dirty.length,
        pulledRecords: remote.length,
        submittedResults: submitted,
      );
    } catch (e, st) {
      debugPrint('同步失败: $e\n$st');
      return SyncReport(performed: true, error: e);
    } finally {
      _running = false;
    }
  }
}
