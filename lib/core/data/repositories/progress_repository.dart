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

  /// 本局种子码所在的键（由游戏外壳写入）。旧版存档没有这个键。
  static const seedKey = '_seed';

  /// 为 true 表示本局由玩家输入的指定种子开始，不计入纪录（由游戏外壳写入）。
  static const customSeedKey = '_customSeed';

  final KeyValueStore _store;
  final Map<String, Map<String, dynamic>?> _cache = {};
  final Map<String, Map<String, dynamic>> _pendingWrites = {};
  bool _flushScheduled = false;

  Map<String, dynamic>? load(String gameId, String modeId) {
    final key = StorageKeys.progress(gameId, modeId);
    return _cache.putIfAbsent(key, () => _store.getJson(key));
  }

  bool has(String gameId, String modeId) => load(gameId, modeId) != null;

  /// 是否有一局还没完成。
  bool hasUnfinished(String gameId, String modeId) {
    final state = load(gameId, modeId);
    return state != null && state[resultKey] == null;
  }

  void save(String gameId, String modeId, Map<String, dynamic> state) {
    _update(gameId, modeId, () {
      final key = StorageKeys.progress(gameId, modeId);
      _cache[key] = state;
      _pendingWrites[key] = state;
      _scheduleFlush();
    });
  }

  void clear(String gameId, String modeId) {
    _update(gameId, modeId, () {
      final key = StorageKeys.progress(gameId, modeId);
      _cache[key] = null;
      _pendingWrites.remove(key);
      _store.remove(key);
    });
  }

  /// 清空所有游戏、所有难度的对局存档。
  Future<void> clearAll() async {
    final hadAny =
        _cache.values.any((v) => v != null) ||
        _store.keys.any((k) => k.startsWith(StorageKeys.progressPrefix));
    _pendingWrites.clear();
    _cache.clear();
    final keys = _store.keys
        .where((k) => k.startsWith(StorageKeys.progressPrefix))
        .toList();
    for (final k in keys) {
      await _store.remove(k);
    }
    if (hadAny) _notifySoon();
  }

  /// 立即把尚未落盘的存档写入底层存储（如切到后台或销毁页面时）。
  Future<void> flush() async {
    if (_pendingWrites.isEmpty) return;
    final entries = _pendingWrites.entries.toList();
    _pendingWrites.clear();
    for (final e in entries) {
      await _store.setJson(e.key, e.value);
    }
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      flush();
    });
  }

  /// 只在“有没有存档 / 是否已完成”发生变化时通知，避免每走一步都通知监听者。
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
