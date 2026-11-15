import 'package:flutter_test/flutter_test.dart';
import 'package:game/core/app_services.dart';
import 'package:game/core/data/models/game_record.dart';
import 'package:game/core/data/models/game_result.dart';
import 'package:game/core/data/models/player_profile.dart';
import 'package:game/core/data/models/score_kind.dart';
import 'package:game/core/data/sync/remote_game_api.dart';
import 'package:game/core/data/sync/sync_service.dart';
import 'package:game/core/storage/key_value_store.dart';

GameResult _result({
  String game = 'circuit',
  String mode = 'easy',
  bool won = true,
  int score = 1000,
  ScoreKind kind = ScoreKind.timeMs,
}) => GameResult(
  gameId: game,
  modeId: mode,
  won: won,
  score: score,
  scoreKind: kind,
  durationMs: 5000,
);

void main() {
  group('本地记录仓库', () {
    test('记录成绩、判断新纪录并持久化', () async {
      final store = MemoryStore();
      final s = await AppServices.fromStore(store);

      var out = await s.records.recordResult(_result(score: 3000));
      expect(out.isNewBest, isTrue);
      out = await s.records.recordResult(_result(score: 4000));
      expect(out.isNewBest, isFalse);
      out = await s.records.recordResult(_result(score: 2000));
      expect(out.isNewBest, isTrue);
      expect(out.previousBest, 3000);
      out = await s.records.recordResult(_result(won: false, score: 1));
      expect(out.isNewBest, isFalse, reason: '失败的对局不计最佳');

      final r = s.records.recordOf('circuit', ScoreKind.timeMs);
      expect(r.plays, 4);
      expect(r.wins, 3);
      expect(r.mode('easy').best, 2000);
      expect(r.dirty, isTrue);
      expect(s.outbox.length, 4);

      // 重新打开同一个存储，数据仍在
      final s2 = await AppServices.fromStore(store);
      expect(
        s2.records.recordOf('circuit', ScoreKind.timeMs).mode('easy').best,
        2000,
      );
      expect(s2.player.profile.playerId, s.player.profile.playerId);
    });

    test('越高越好的指标', () async {
      final s = await AppServices.fromStore(MemoryStore());
      await s.records.recordResult(_result(kind: ScoreKind.points, score: 10));
      final out = await s.records.recordResult(
        _result(kind: ScoreKind.points, score: 20),
      );
      expect(out.isNewBest, isTrue);
    });

    test('清空纪录', () async {
      final s = await AppServices.fromStore(MemoryStore());
      await s.records.recordResult(_result());
      await s.resetProgress();
      expect(s.records.all, isEmpty);
      expect(s.outbox.length, 0);
    });

    test('损坏的 JSON 不会导致崩溃', () async {
      final store = MemoryStore({
        'game_records': '{not json',
        'player_profile': '[]',
      });
      final s = await AppServices.fromStore(store);
      expect(s.records.all, isEmpty);
      expect(s.player.profile.playerId, isNotEmpty);
    });
  });

  group('GameRecord 合并', () {
    test('计数取大，最佳取优', () {
      final a = GameRecord(
        gameId: 'g',
        scoreKind: ScoreKind.moves,
        modes: const {'easy': ModeStats(plays: 5, wins: 3, best: 20)},
        updatedAt: DateTime(2026, 1, 1),
        dirty: true,
      );
      final b = GameRecord(
        gameId: 'g',
        scoreKind: ScoreKind.moves,
        modes: const {
          'easy': ModeStats(plays: 3, wins: 3, best: 15),
          'hard': ModeStats(plays: 1, wins: 0),
        },
        updatedAt: DateTime(2026, 2, 1),
      );
      final m = a.merge(b);
      expect(m.mode('easy').plays, 5);
      expect(m.mode('easy').best, 15);
      expect(m.mode('hard').plays, 1);
      expect(m.updatedAt, DateTime(2026, 2, 1));
      expect(m.dirty, isFalse);
    });
  });

  group('服务器同步（预留）', () {
    test('离线模式什么也不做', () async {
      final report = await const OfflineSyncService().sync();
      expect(report.performed, isFalse);
    });

    test('RemoteSyncService：注册、上传队列、推送并合并记录', () async {
      final s = await AppServices.fromStore(MemoryStore());
      await s.records.recordResult(_result(score: 3000));
      await s.records.recordResult(
        _result(game: 'memory', kind: ScoreKind.moves, score: 30),
      );

      final api = _FakeApi();
      final sync = RemoteSyncService(
        api: api,
        player: s.player,
        records: s.records,
        outbox: s.outbox,
      );
      final report = await sync.sync();

      expect(report.ok, isTrue);
      expect(report.submittedResults, 2);
      expect(report.pushedRecords, 2);
      expect(s.player.profile.isLinkedToServer, isTrue);
      expect(s.outbox.length, 0);
      expect(s.records.dirtyRecords, isEmpty);
      // 服务器上有更好的成绩，合并后本地应更新
      expect(
        s.records.recordOf('circuit', ScoreKind.timeMs).mode('easy').best,
        1500,
      );
    });

    test('同步失败时保留本地队列', () async {
      final s = await AppServices.fromStore(MemoryStore());
      await s.records.recordResult(_result());
      final sync = RemoteSyncService(
        api: _FakeApi(fail: true),
        player: s.player,
        records: s.records,
        outbox: s.outbox,
      );
      final report = await sync.sync();
      expect(report.ok, isFalse);
      expect(s.outbox.length, 1);
      expect(s.records.dirtyRecords, hasLength(1));
    });
  });
}

class _FakeApi implements RemoteGameApi {
  _FakeApi({this.fail = false});

  final bool fail;

  @override
  Future<PlayerProfile> registerPlayer(PlayerProfile local) async {
    if (fail) throw Exception('network down');
    return local.copyWith(remoteUserId: 'u-1');
  }

  @override
  Future<Set<String>> submitResults(
    String playerId,
    List<GameResult> results,
  ) async => results.map((r) => r.id).toSet();

  @override
  Future<void> pushRecords(String playerId, List<GameRecord> records) async {}

  @override
  Future<List<GameRecord>> fetchRecords(String playerId) async => [
    GameRecord(
      gameId: 'circuit',
      scoreKind: ScoreKind.timeMs,
      modes: const {'easy': ModeStats(plays: 1, wins: 1, best: 1500)},
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];
}
