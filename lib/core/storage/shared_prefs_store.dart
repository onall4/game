import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

/// 基于 shared_preferences 的本地存储实现。
///
/// 所有键统一加 [prefix] 前缀，避免与其他插件写入的键冲突，
/// 也便于 [clear] 时只清理本应用的数据。
class SharedPrefsStore extends KeyValueStore {
  SharedPrefsStore._(this._prefs);

  static const prefix = 'shiqu.';

  final SharedPreferencesWithCache _prefs;

  static Future<SharedPrefsStore> open() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    return SharedPrefsStore._(prefs);
  }

  @override
  Iterable<String> get keys => _prefs.keys
      .where((k) => k.startsWith(prefix))
      .map((k) => k.substring(prefix.length))
      .toList(growable: false);

  @override
  String? getString(String key) => _prefs.getString('$prefix$key');

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString('$prefix$key', value);

  @override
  Future<void> remove(String key) => _prefs.remove('$prefix$key');

  @override
  Future<void> clear() async {
    final keys = _prefs.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }
}
