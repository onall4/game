import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:game/games/circuit/circuit_logic.dart';
import 'package:game/games/circuit/circuit_page.dart';
import 'package:game/games/codebreaker/codebreaker_logic.dart';
import 'package:game/games/codebreaker/codebreaker_page.dart';
import 'package:game/games/game_registry.dart';
import 'package:game/games/memory/memory_logic.dart';
import 'package:game/games/memory/memory_page.dart';
import 'package:game/games/onestroke/onestroke_logic.dart';
import 'package:game/games/onestroke/onestroke_page.dart';
import 'package:game/games/schulte/schulte_logic.dart';
import 'package:game/games/schulte/schulte_page.dart';
import 'package:game/games/seed.dart';
import 'package:game/games/twentyfour/twentyfour_logic.dart';
import 'package:game/games/twentyfour/twentyfour_page.dart';

/// 每个游戏某难度下开局的“指纹”：开局完全相同时指纹相同。
String _fingerprint(String gameId, String modeId, GameSeed seed) {
  final random = SeededRandom.forGame(seed, modeId);
  switch (gameId) {
    case 'circuit':
      final p = CircuitPuzzle.generate(
        CircuitGame.sizeFor(modeId),
        random: random,
      ).toJson();
      final tiles = [
        for (final t in p['tiles'] as List) (t as int).toRadixString(16),
      ].join();
      return '$tiles/${(p['turns'] as List).join()}';
    case 'codebreaker':
      final config = CodeBreakerGameView.configFor(modeId);
      return CodeBreakerGame(config, random: random).secret.join();
    case 'memory':
      final (rows, cols) = MemoryGameView.gridFor(modeId);
      final game = MemoryGame(pairs: rows * cols ~/ 2, random: random);
      return [for (final c in game.cards) c.symbol.toRadixString(36)].join();
    case 'schulte':
      final config = SchulteGameView.configFor(modeId);
      final game = SchulteGame(config, random: random);
      final start = game.cells.join(',');
      if (!config.reshuffle) return start;
      // 洗牌模式：点对两个之后的排列也由种子决定
      for (var k = 0; k < 2; k++) {
        game.tap(game.cells.indexOf(game.next));
      }
      return '$start/${game.cells.join(',')}';
    case 'onestroke':
      final c = OneStrokeGameView.configFor(modeId);
      final p = OneStrokePuzzle.generate(
        cols: c.cols,
        rows: c.rows,
        minWalls: c.minWalls,
        maxWalls: c.maxWalls,
        random: random,
      );
      return '${(p.toJson()['walls'] as List).join(',')}/${p.start}';
    case 'twentyfour':
      final level = TwentyFourGameView.levelFor(modeId);
      final game = TwentyFourGame(level, random: random);
      return [for (final p in game.puzzles) p.join(',')].join(' ');
  }
  throw ArgumentError(gameId);
}

void main() {
  group('种子码', () {
    test('随机种子编码后能原样解析回来', () {
      final rng = Random(7);
      for (var i = 0; i < 500; i++) {
        final seed = GameSeed.random(1 + rng.nextInt(1023), rng);
        final code = seed.code;
        expect(code.length, seed.version < 32 ? 7 : 9);
        expect(GameSeed.tryParse(code), seed);
      }
    });

    test('版本 1–31 占 1 位；32 起以 0 开头扩展为 3 位', () {
      expect(const GameSeed(1, 0).code, '1000000');
      expect(const GameSeed(31, GameSeed.valueRange - 1).code, 'ZZZZZZZ');
      expect(const GameSeed(32, 0).code, '010000000');
      expect(const GameSeed(1023, 0).code, '0ZZ000000');
    });

    test('输入宽松：大小写、空格、横线、#，O→0、I/L→1', () {
      final seed = GameSeed.tryParse('1K7Q2XM')!;
      expect(seed.version, 1);
      expect(GameSeed.tryParse(' #1k7-q2 xm '), seed);
      expect(GameSeed.tryParse('IO00000'), GameSeed.tryParse('1000000'));
      expect(GameSeed.tryParse('L000000'), GameSeed.tryParse('1000000'));
    });

    test('格式不对返回 null', () {
      for (final bad in [
        '',
        '1K7Q2X', // 太短
        '1K7Q2XMM', // 太长
        '1K7Q2XU', // U 不在字母表里
        '1K7Q2X!',
        '0000000', // 版本 0 不存在
        '001000000', // 1–31 不能用扩展写法
      ]) {
        expect(GameSeed.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('SeededRandom', () {
    test('与标准 mulberry32（JS Math.imul 实现）结果一致', () {
      // 参考值由 Node.js 运行标准 mulberry32 得到
      final r0 = SeededRandom(0);
      expect(
        [for (var i = 0; i < 5; i++) r0.nextUint32()],
        [1144304738, 1416247, 958946056, 627933444, 2007157716],
      );
      final r1 = SeededRandom(0xDEADBEEF);
      expect(
        [for (var i = 0; i < 5; i++) r1.nextUint32()],
        [4043151706, 1147597007, 3315858022, 1538288752, 2042435954],
      );
    });

    test('字符串散列（FNV-1a）与参考实现一致', () {
      final r = SeededRandom.fromString('size4/1K7Q2XM');
      expect(
        [for (var i = 0; i < 5; i++) r.nextUint32()],
        [2956012057, 2740585148, 3014209893, 4012679600, 645989751],
      );
      // 空串即 FNV 初始值；中文按 UTF-16 码元散列
      expect(
        SeededRandom.fromString('').nextUint32(),
        SeededRandom(2166136261).nextUint32(),
      );
      expect(
        SeededRandom.fromString('中文/AB').nextUint32(),
        SeededRandom(3056766885).nextUint32(),
      );
    });

    test('nextInt / nextDouble 的取值范围与固定结果', () {
      final r = SeededRandom(0);
      expect(
        [for (var i = 0; i < 5; i++) r.nextInt(100)],
        [38, 47, 56, 44, 16],
      );
      expect(r.nextDouble(), 0.5450490070588038);

      final rng = SeededRandom(42);
      final counts = List.filled(6, 0);
      for (var i = 0; i < 6000; i++) {
        final v = rng.nextInt(6);
        counts[v]++;
        final d = rng.nextDouble();
        expect(d >= 0 && d < 1, isTrue);
      }
      for (final c in counts) {
        expect(c, inInclusiveRange(850, 1150), reason: '分布应大致均匀');
      }
      expect(rng.nextInt(1), 0);
      expect(rng.nextInt(4294967296), lessThan(4294967296));
      expect(() => rng.nextInt(0), throwsRangeError);
    });

    test('shuffleWith 是确定的排列', () {
      final a = List.generate(20, (i) => i);
      final b = List.generate(20, (i) => i);
      shuffleWith(a, SeededRandom(9));
      shuffleWith(b, SeededRandom(9));
      expect(a, b);
      expect(a.toSet().length, 20);
      expect(a, isNot(List.generate(20, (i) => i)));
    });
  });

  group('种子 → 开局', () {
    final seed = GameSeed.tryParse('1K7Q2XM')!;

    test('同一种子、同一难度，每次生成的开局都相同', () {
      for (final game in gameRegistry) {
        for (final mode in game.modes) {
          expect(
            _fingerprint(game.id, mode.id, seed),
            _fingerprint(game.id, mode.id, seed),
            reason: '${game.title} ${mode.label}',
          );
        }
      }
    });

    test('不同种子开局不同', () {
      final other = GameSeed.tryParse('1K7Q2XN')!;
      for (final game in gameRegistry) {
        final mode = game.modes.last;
        expect(
          _fingerprint(game.id, mode.id, seed),
          isNot(_fingerprint(game.id, mode.id, other)),
          reason: game.title,
        );
      }
    });

    test('同一种子在不同难度下互不相关', () {
      // 不混入难度时，入门的答案会正好是简单答案的前 3 位
      final easy = _fingerprint('codebreaker', 'easy', seed);
      final lv2 = _fingerprint('codebreaker', 'lv2', seed);
      expect(lv2.startsWith(easy), isFalse);
    });

    // 固定开局：同一个种子永远对应这些开局。
    // 这里失败说明改动了生成规则（算法、SeededRandom、图案数量等），
    // 已经发出去的种子会对应到别的开局——请把对应游戏的 seedVersion +1，
    // 再更新这里的期望值。
    test('固定开局（v1）', () {
      const expected = {
        'circuit': {
          'size4': '42ec54153fad2b81/2101320200110013',
          'normal':
              '2c42c42bbad568447d7ad3d1547ebc139129/'
              '222011022303211212100111323110130320',
          'size10':
              '2aac42aac4444792aad5793f82eab93c2bea944443c43aeb957abbaed6e954'
              '2ee9551417a916bbe9456ac7a8143912bbaaa9/'
              '30121021003031210330321120101031111102333021300312130221033221'
              '01332102103213121221202121300013212332',
        },
        'codebreaker': {
          'easy': '354',
          'lv2': '4532',
          'lv3': '1265',
          'normal': '8365',
          'lv5': '02384',
          'lv6': '489352',
          'hard6': '851422',
        },
        'memory': {
          'easy': 'b73b8e793e89',
          'm36': '84dcaf1fe7840gb3ae66955h9bd07h3g21c2',
        },
        'schulte': {
          's3': '8,5,4,9,3,2,7,1,6',
          's5': '17,3,11,5,16,1,20,6,25,23,14,13,2,9,21,7,12,15,18,8,10,24,22,19,4',
          'rev': '14,3,22,8,16,2,25,15,21,20,10,6,4,11,13,1,17,12,23,9,19,18,5,7,24',
          'shuf':
              '4,14,25,7,20,8,13,24,16,23,18,10,21,6,22,19,17,1,9,12,5,3,2,15,11/'
              '24,14,12,10,3,6,17,22,4,8,23,7,11,15,25,16,2,20,5,21,1,19,13,18,9',
        },
        'onestroke': {
          'o4': '1,7/3',
          'o5': '18,21/20',
          'o6': '7,30,31/6',
          'o7': '5,10,18,37,39,40/6',
          'o8': '3,29,35,50,53/54',
          'o9': '24,30,43,57,58,70,79/80',
        },
        'twentyfour': {
          't1': '8,2,2,8 9,8,3,9 8,4,4,8',
          't2': '7,4,2,1 5,8,8,9 3,5,9,8 3,1,2,8 3,7,7,2',
          't3': '3,11,6,9 9,6,5,1 5,6,7,9 1,9,8,11 6,6,8,10',
          't4': '8,12,6,7 10,6,7,3 13,3,4,9 8,13,8,12 3,9,11,3',
          't5': '10,4,10,2 7,7,3,3 2,10,7,7',
        },
      };
      for (final MapEntry(key: gameId, value: modes) in expected.entries) {
        final game = gameRegistry.firstWhere((g) => g.id == gameId);
        expect(game.seedVersion, 1, reason: '版本变了就要更新这里的期望值');
        for (final MapEntry(key: modeId, value: fp) in modes.entries) {
          expect(
            _fingerprint(gameId, modeId, seed),
            fp,
            reason: '$gameId $modeId',
          );
        }
      }
    });
  });
}
