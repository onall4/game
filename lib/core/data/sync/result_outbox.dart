import '../../storage/key_value_store.dart';
import '../../storage/storage_keys.dart';
import '../models/game_result.dart';

/// 待上传的对局结果队列（outbox 模式）。
///
/// 每局结束时先落到本地队列，联网且接入服务器后由 SyncService
/// 按顺序批量上传；服务器以 [GameResult.id] 做幂等去重。
class ResultOutbox {
  ResultOutbox(this._store, {this.capacity = 500});

  final KeyValueStore _store;

  /// 离线过久时只保留最近的若干条，防止无限增长。
  final int capacity;

  List<GameResult> peekAll() {
    final list = _store.getJsonList(StorageKeys.resultOutbox) ?? const [];
    final results = <GameResult>[];
    for (final item in list) {
      try {
        results.add(GameResult.fromJson((item as Map).cast<String, dynamic>()));
      } catch (_) {
        // 忽略损坏条目
      }
    }
    return results;
  }

  int get length => peekAll().length;

  Future<void> enqueue(GameResult result) async {
    final all = [...peekAll(), result];
    final trimmed = all.length > capacity
        ? all.sublist(all.length - capacity)
        : all;
    await _save(trimmed);
  }

  /// 上传成功后，移除已确认的条目。
  Future<void> remove(Iterable<String> ids) async {
    final set = ids.toSet();
    await _save(peekAll().where((r) => !set.contains(r.id)).toList());
  }

  Future<void> clear() => _store.remove(StorageKeys.resultOutbox);

  Future<void> _save(List<GameResult> list) => _store.setJson(
    StorageKeys.resultOutbox,
    list.map((r) => r.toJson()).toList(),
  );
}
