import 'package:flutter/foundation.dart';

import '../../storage/key_value_store.dart';
import '../../storage/storage_keys.dart';

/// 设备级设置（触感反馈、上次选择的难度等），只保存在本地。
class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._store) {
    final json = _store.getJson(StorageKeys.settings) ?? {};
    _haptics = json['haptics'] as bool? ?? true;
  }

  final KeyValueStore _store;
  late bool _haptics;

  bool get haptics => _haptics;

  Future<void> setHaptics(bool value) async {
    _haptics = value;
    await _save();
    notifyListeners();
  }

  String? lastMode(String gameId) =>
      _store.getString(StorageKeys.lastMode(gameId));

  Future<void> setLastMode(String gameId, String modeId) async {
    await _store.setString(StorageKeys.lastMode(gameId), modeId);
    notifyListeners();
  }

  Future<void> _save() =>
      _store.setJson(StorageKeys.settings, {'haptics': _haptics});
}
