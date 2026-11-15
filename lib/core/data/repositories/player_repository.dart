import 'package:flutter/foundation.dart';

import '../../storage/key_value_store.dart';
import '../../storage/storage_keys.dart';
import '../models/player_profile.dart';

/// 玩家档案仓库接口。
abstract class PlayerRepository extends ChangeNotifier {
  PlayerProfile get profile;

  Future<void> update(PlayerProfile profile);
}

class LocalPlayerRepository extends PlayerRepository {
  LocalPlayerRepository(this._store) {
    final json = _store.getJson(StorageKeys.playerProfile);
    if (json != null) {
      try {
        _profile = PlayerProfile.fromJson(json);
        return;
      } catch (_) {
        // 数据损坏时重新生成
      }
    }
    _profile = PlayerProfile.createLocal();
    _store.setJson(StorageKeys.playerProfile, _profile.toJson());
  }

  final KeyValueStore _store;
  late PlayerProfile _profile;

  @override
  PlayerProfile get profile => _profile;

  @override
  Future<void> update(PlayerProfile profile) async {
    _profile = profile;
    await _store.setJson(StorageKeys.playerProfile, profile.toJson());
    notifyListeners();
  }
}
