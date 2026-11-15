import 'package:flutter/foundation.dart';

import '../../storage/key_value_store.dart';
import '../../storage/storage_keys.dart';
import '../models/game_record.dart';
import '../models/game_result.dart';
import '../models/score_kind.dart';
import '../sync/result_outbox.dart';

/// 一次记录成绩后的反馈，供结算界面显示“新纪录”等信息。
class RecordOutcome {
  const RecordOutcome({
    required this.record,
    required this.isNewBest,
    this.previousBest,
  });

  final GameRecord record;
  final bool isNewBest;
  final int? previousBest;
}

/// 游戏记录仓库接口。UI 只依赖这个抽象类。
///
/// 读取是同步的（实现方需在初始化时把数据载入内存），
/// 写入是异步的。数据变化时会 [notifyListeners]，首页据此刷新。
abstract class GameRecordRepository extends ChangeNotifier {
  GameRecord recordOf(String gameId, ScoreKind kind);

  Iterable<GameRecord> get all;

  Future<RecordOutcome> recordResult(GameResult result);

  /// 尚未同步到服务器的记录。
  List<GameRecord> get dirtyRecords;

  /// 同步成功后清除脏标记。
  Future<void> markSynced(Iterable<String> gameIds);

  /// 把服务器拉回的记录合并进本地。
  Future<void> mergeRemote(Iterable<GameRecord> remote);

  Future<void> clear();
}

/// 本地实现：整张记录表以 JSON 存在一个键里，数据量很小，读写都很快。
class LocalGameRecordRepository extends GameRecordRepository {
  LocalGameRecordRepository(this._store, this._outbox) {
    final json = _store.getJson(StorageKeys.gameRecords) ?? {};
    for (final entry in json.entries) {
      try {
        _records[entry.key] = GameRecord.fromJson(
          (entry.value as Map).cast<String, dynamic>(),
        );
      } catch (e) {
        debugPrint('跳过损坏的记录 ${entry.key}: $e');
      }
    }
  }

  final KeyValueStore _store;
  final ResultOutbox _outbox;
  final Map<String, GameRecord> _records = {};

  @override
  GameRecord recordOf(String gameId, ScoreKind kind) =>
      _records[gameId] ?? GameRecord.empty(gameId, kind);

  @override
  Iterable<GameRecord> get all => _records.values;

  @override
  Future<RecordOutcome> recordResult(GameResult result) async {
    final before = recordOf(result.gameId, result.scoreKind);
    final previousBest = before.mode(result.modeId).best;
    final after = before.apply(result);
    _records[result.gameId] = after;
    await _persist();
    await _outbox.enqueue(result);
    notifyListeners();
    return RecordOutcome(
      record: after,
      previousBest: previousBest,
      isNewBest:
          result.won && result.scoreKind.isBetter(result.score, previousBest),
    );
  }

  @override
  List<GameRecord> get dirtyRecords =>
      _records.values.where((r) => r.dirty).toList();

  @override
  Future<void> markSynced(Iterable<String> gameIds) async {
    for (final id in gameIds) {
      final r = _records[id];
      if (r != null) _records[id] = r.copyWith(dirty: false);
    }
    await _persist();
  }

  @override
  Future<void> mergeRemote(Iterable<GameRecord> remote) async {
    for (final r in remote) {
      final local = _records[r.gameId];
      _records[r.gameId] = local == null
          ? r.copyWith(dirty: false)
          : local.merge(r);
    }
    await _persist();
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    _records.clear();
    await _store.remove(StorageKeys.gameRecords);
    notifyListeners();
  }

  Future<void> _persist() => _store.setJson(
    StorageKeys.gameRecords,
    _records.map((k, v) => MapEntry(k, v.toJson())),
  );
}
