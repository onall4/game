import '../models/game_record.dart';
import '../models/game_result.dart';
import '../models/player_profile.dart';

/// 服务器接口约定（尚未实现）。
///
/// 接入后端时新增一个实现类（例如基于 http / dio 的 `HttpGameApi`），
/// 然后在 `AppServices.create` 里把 [OfflineSyncService] 换成
/// `RemoteSyncService(api: HttpGameApi(...))` 即可，UI 层无需改动。
///
/// 建议的 REST 形态：
/// - `POST /players`                     注册 / 认领匿名玩家
/// - `GET  /players/{id}/records`        拉取全部游戏记录
/// - `PUT  /players/{id}/records`        批量上传记录（服务器按 max 规则合并）
/// - `POST /players/{id}/results`        批量提交对局结果（按 result.id 幂等）
/// - `GET  /leaderboards/{gameId}/{mode}` 排行榜
abstract class RemoteGameApi {
  Future<PlayerProfile> registerPlayer(PlayerProfile local);

  Future<List<GameRecord>> fetchRecords(String playerId);

  Future<void> pushRecords(String playerId, List<GameRecord> records);

  /// 返回服务器已确认接收的结果 ID。
  Future<Set<String>> submitResults(String playerId, List<GameResult> results);
}
