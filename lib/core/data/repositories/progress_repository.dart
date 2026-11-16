import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../storage/key_value_store.dart';
import '../../storage/storage_keys.dart';

/// 对局状态存档：每个游戏的每个模式各一份，只保存在本机。
///
/// 未完成和已完成的对局都会保存；已完成的对局由游戏外壳额外写入 [resultKey]
/// （结算数据），玩家点「重新开始」时才会清除，开始新的一局。
/// 读取走内存缓存，保证“清除后立即读取”拿到的一定是最新结果。
class ProgressRepository extends ChangeNotifier {
  ProgressRepository(this._store);

  /// 已完成对局的结算数据所在的键（由游戏外壳写入，具体游戏无需关心）。
  static const resultKey = '_result';

  final KeyValueStore _store;
  final Map<String, Map<String, dynamic>?> _cache = {};

  Map<String, dynamic>? load(String gameId, String modeId) {
    final key = StorageKeys.progress(gameId, modeId);
    return _cache.putIfAbsent(key, () => _store.getJson(key));
  }

  bool has(String gameId, String modeId) => load(gameId, modeId) != null;

  /// 是否有一局还没完成（首页据此提示“继续上一局”）。
  bool hasUnfinished(String gameId, String modeId) {
    final state = load(gameId, modeId);
    return state != null && state[resultKey] == null;
  }

  void save(String gameId, String modeId, Map<String, dynamic> state) {
    _update(gameId, modeId, () {
      final key = StorageKeys.progress(gameId, modeId);
      _cache[key] = state;
      _store.setJson(key, state);
    });
  }

  void clear(String gameId, String modeId) {
    _update(gameId, modeId, () {
      final key = StorageKeys.progress(gameId, modeId);
      _cache[key] = null;
      _store.remove(key);
    });
  }

  /// 只在“有没有存档 / 是否已完成”发生变化时通知，避免每走一步都触发首页重建。
  void _update(String gameId, String modeId, VoidCallback change) {
    final before = (has(gameId, modeId), hasUnfinished(gameId, modeId));
    change();
    final after = (has(gameId, modeId), hasUnfinished(gameId, modeId));
    if (before != after) _notifySoon();
  }

  bool _notifyScheduled = false;

  /// 游戏页销毁（dispose）时也会保存，此时组件树处于锁定状态，
  /// 不能立刻让首页重建；推迟到当前任务结束后再通知（多次变化合并为一次）。
  void _notifySoon() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}
