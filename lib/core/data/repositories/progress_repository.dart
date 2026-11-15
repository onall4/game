import 'package:flutter/foundation.dart';

import '../../storage/key_value_store.dart';
import '../../storage/storage_keys.dart';

/// 未完成对局的进度存档：每个游戏的每个模式各一份，只保存在本机。
///
/// 进度内容由各游戏自行序列化（JSON），这里只负责存取。
/// 读取走内存缓存，保证“清除后立即读取”拿到的一定是最新结果。
class ProgressRepository extends ChangeNotifier {
  ProgressRepository(this._store);

  final KeyValueStore _store;
  final Map<String, Map<String, dynamic>?> _cache = {};

  Map<String, dynamic>? load(String gameId, String modeId) {
    final key = StorageKeys.progress(gameId, modeId);
    return _cache.putIfAbsent(key, () => _store.getJson(key));
  }

  bool has(String gameId, String modeId) => load(gameId, modeId) != null;

  void save(String gameId, String modeId, Map<String, dynamic> state) {
    final key = StorageKeys.progress(gameId, modeId);
    final existed = has(gameId, modeId);
    _cache[key] = state;
    _store.setJson(key, state);
    if (!existed) notifyListeners();
  }

  void clear(String gameId, String modeId) {
    final key = StorageKeys.progress(gameId, modeId);
    final existed = has(gameId, modeId);
    _cache[key] = null;
    _store.remove(key);
    if (existed) notifyListeners();
  }
}
