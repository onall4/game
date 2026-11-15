import 'key_value_store.dart';
import 'storage_keys.dart';

/// 本地数据结构迁移。
///
/// 每次修改持久化数据的结构时：
/// 1. 递增 [currentVersion]；
/// 2. 在 [_migrations] 中追加一个从上一版本升级的函数。
class StorageMigrator {
  StorageMigrator(this.store);

  static const currentVersion = 1;

  final KeyValueStore store;

  /// key = 目标版本号，value = 升级到该版本要执行的操作。
  late final Map<int, Future<void> Function()> _migrations = {
    // 2: () async { ... },
  };

  Future<void> run() async {
    final stored = int.tryParse(
      store.getString(StorageKeys.schemaVersion) ?? '',
    );
    var version = stored ?? 0;
    if (version == 0) {
      // 全新安装，无需迁移。
      version = currentVersion;
    }
    while (version < currentVersion) {
      version++;
      await _migrations[version]?.call();
    }
    await store.setString(StorageKeys.schemaVersion, '$currentVersion');
  }
}
