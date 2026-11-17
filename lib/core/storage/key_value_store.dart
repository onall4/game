import 'dart:convert';

/// 最底层的键值存储抽象。
///
/// 当前用 [SharedPrefsStore]（本地），测试用 [MemoryStore]。
/// 上层（Repository）只依赖这个接口，不直接接触任何具体存储插件，
/// 以后要换成 SQLite / Hive / 加密存储时只需新增一个实现。
abstract class KeyValueStore {
  Iterable<String> get keys;

  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);

  /// 清除本应用写入的全部数据。
  Future<void> clear();

  Map<String, dynamic>? getJson(String key) {
    final raw = getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  List<dynamic>? getJsonList(String key) {
    final raw = getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> setJson(String key, Object value) =>
      setString(key, jsonEncode(value));
}

/// 纯内存实现，用于单元测试或临时会话。
class MemoryStore extends KeyValueStore {
  MemoryStore([Map<String, String>? initial]) : _data = {...?initial};

  final Map<String, String> _data;

  @override
  Iterable<String> get keys => List.unmodifiable(_data.keys);

  @override
  String? getString(String key) => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();
}
