import 'dart:math';

/// 本地玩家档案。
///
/// [playerId] 在首次启动时本地生成。接入服务器后可用它做匿名账号，
/// 登录后再通过 [remoteUserId] 绑定正式账号，从而把本地数据迁移上去。
class PlayerProfile {
  const PlayerProfile({
    required this.playerId,
    required this.nickname,
    required this.createdAt,
    this.remoteUserId,
  });

  factory PlayerProfile.createLocal({Random? random}) {
    final rng = random ?? Random.secure();
    final id = List.generate(
      16,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return PlayerProfile(
      playerId: id,
      nickname: '玩家${id.substring(0, 4).toUpperCase()}',
      createdAt: DateTime.now(),
    );
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
    playerId: json['playerId'] as String,
    nickname: json['nickname'] as String? ?? '玩家',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    remoteUserId: json['remoteUserId'] as String?,
  );

  final String playerId;
  final String nickname;
  final DateTime createdAt;

  /// 服务器账号 ID，未登录时为 null。
  final String? remoteUserId;

  bool get isLinkedToServer => remoteUserId != null;

  PlayerProfile copyWith({String? nickname, String? remoteUserId}) =>
      PlayerProfile(
        playerId: playerId,
        nickname: nickname ?? this.nickname,
        createdAt: createdAt,
        remoteUserId: remoteUserId ?? this.remoteUserId,
      );

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'nickname': nickname,
    'createdAt': createdAt.toIso8601String(),
    if (remoteUserId != null) 'remoteUserId': remoteUserId,
  };
}
