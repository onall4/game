/// 所有持久化键集中定义，方便做数据迁移和排查。
abstract final class StorageKeys {
  /// 本地数据结构版本，结构变化时递增并在 [StorageMigrator] 中处理。
  static const schemaVersion = 'schema_version';

  static const playerProfile = 'player_profile';
  static const gameRecords = 'game_records';
  static const settings = 'settings';

  /// 待上传到服务器的对局结果队列（outbox）。
  static const resultOutbox = 'sync.result_outbox';

  /// 上次与服务器同步成功的时间。
  static const lastSyncedAt = 'sync.last_synced_at';

  static String lastMode(String gameId) => 'last_mode.$gameId';
}
