import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:game/games/circuit/circuit_logic.dart';
import 'package:game/games/codebreaker/codebreaker_logic.dart';
import 'package:game/games/memory/memory_logic.dart';

void main() {
  group('回路', () {
    test('rotateMask 顺时针旋转', () {
      expect(rotateMask(Dir.up, 1), Dir.right);
      expect(rotateMask(Dir.left, 1), Dir.up);
      expect(rotateMask(Dir.up | Dir.right, 1), Dir.right | Dir.down);
      expect(rotateMask(Dir.up | Dir.down, 2), Dir.up | Dir.down);
      expect(rotateMask(0xF, 3), 0xF);
    });

    test('生成的谜题是一棵生成树，初始未解且可解', () {
      for (final size in [5, 6, 7]) {
        for (var seed = 0; seed < 30; seed++) {
          final p = CircuitPuzzle.generate(size, random: Random(seed));
          expect(p.solved, isFalse);
          // 生成树：半边总数 = 2 * (n - 1)
          var halfEdges = 0;
          for (var i = 0; i < p.cellCount; i++) {
            final m = p.baseMask(i);
            expect(m, isNot(0), reason: '每格至少有一个接口');
            halfEdges += bitCount(m);
          }
          expect(halfEdges, 2 * (p.cellCount - 1));

          // 按原始朝向复原后应全部通电
          final solved = CircuitPuzzle.fromTiles(
            size: size,
            source: p.source,
            tiles: [for (var i = 0; i < p.cellCount; i++) p.baseMask(i)],
          );
          expect(solved.solved, isTrue);
        }
      }
    });

    test('旋转与锁定', () {
      // 2x1：左格向右，右格向左，右格初始被转了一次
      final p = CircuitPuzzle.fromTiles(
        size: 2,
        source: 0,
        tiles: [Dir.right | Dir.down, Dir.left | Dir.down, Dir.up, Dir.up],
        turns: [0, 0, 0, 1],
      );
      expect(p.solved, isFalse);
      p.toggleLock(3);
      expect(p.rotate(3), isFalse);
      p.toggleLock(3);
      for (var i = 0; i < 3; i++) {
        p.rotate(3);
      }
      expect(p.solved, isTrue);
      expect(p.moves, 3);
      expect(p.rotate(0), isFalse, reason: '已解开后不再响应');
    });
  });

  group('密码锁', () {
    test('evaluate 反馈', () {
      expect(evaluate([1, 2, 3, 4], [1, 2, 3, 4]), const CodeFeedback(4, 0));
      expect(evaluate([1, 2, 3, 4], [4, 3, 2, 1]), const CodeFeedback(0, 4));
      expect(evaluate([1, 2, 3, 4], [1, 3, 5, 6]), const CodeFeedback(1, 1));
      expect(evaluate([5, 6, 7, 8], [1, 2, 3, 4]), const CodeFeedback(0, 0));
    });

    test('evaluate 处理重复数字', () {
      expect(evaluate([1, 1, 2, 2], [1, 2, 1, 2]), const CodeFeedback(2, 2));
      expect(evaluate([1, 2, 3, 4], [1, 1, 1, 1]), const CodeFeedback(1, 0));
      expect(evaluate([1, 1, 2, 3], [3, 1, 1, 1]), const CodeFeedback(1, 2));
    });

    test('生成的密码满足配置', () {
      const cfg = CodeConfig(length: 4, symbols: 10, allowRepeat: false);
      for (var seed = 0; seed < 50; seed++) {
        final g = CodeBreakerGame(cfg, random: Random(seed));
        expect(g.secret.length, 4);
        expect(g.secret.toSet().length, 4);
        expect(g.secret.every((d) => d >= 0 && d <= 9), isTrue);
      }
    });

    const easy = CodeConfig(
      length: 3,
      symbols: 6,
      firstSymbol: 1,
      allowRepeat: false,
    );

    test('不限次数，猜中才结束', () {
      final g = CodeBreakerGame(easy, secret: [1, 2, 3]);
      expect(g.validate([1, 2]), GuessError.incomplete);
      expect(g.validate([1, 1, 2]), GuessError.repeated);
      for (var i = 0; i < 20; i++) {
        g.submit([4, 5, 6]);
      }
      expect(g.won, isFalse, reason: '20 次没猜中也不会判负');
      g.submit([1, 2, 3]);
      expect(g.won, isTrue);
      expect(g.attemptsUsed, 21);
      expect(() => g.submit([1, 2, 3]), throwsStateError);
    });

    test('存档往返：重放历史，反馈一致', () {
      final g = CodeBreakerGame(easy, secret: [2, 4, 6]);
      g.submit([1, 2, 3]);
      g.submit([6, 4, 2]);
      final restored = CodeBreakerGame.fromJson(
        easy,
        jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>,
      );
      expect(restored.secret, [2, 4, 6]);
      expect(restored.attemptsUsed, 2);
      expect(restored.history.last.feedback, const CodeFeedback(1, 2));
    });

    test('存档与模式不匹配时拒绝恢复', () {
      const normal = CodeConfig(length: 4, symbols: 10, allowRepeat: false);
      final g = CodeBreakerGame(normal, secret: [0, 7, 8, 9]);
      expect(
        () => CodeBreakerGame.fromJson(easy, g.toJson()),
        throwsFormatException,
      );
    });
  });

  group('翻翻乐', () {
    test('发牌：每种图案恰好两张', () {
      final g = MemoryGame(pairs: 8, random: Random(1));
      expect(g.cards.length, 16);
      final counts = <int, int>{};
      for (final c in g.cards) {
        counts.update(c.symbol, (v) => v + 1, ifAbsent: () => 1);
      }
      expect(counts.length, 8);
      expect(counts.values.every((v) => v == 2), isTrue);
      expect(MemoryGame.symbolPool, greaterThanOrEqualTo(15));
    });

    test('配对、错配、连击与完成', () {
      // 未洗牌：[0,0,1,1]
      final g = MemoryGame(pairs: 2, symbols: [0, 1]);
      expect(g.flip(0), FlipOutcome.first);
      expect(g.flip(0), FlipOutcome.ignored);
      expect(g.flip(2), FlipOutcome.mismatch);
      expect(g.waiting, isTrue);
      expect(g.flip(3), FlipOutcome.ignored, reason: '等待翻回期间忽略点击');
      g.hideMismatch();
      expect(g.cards[0].faceUp, isFalse);

      expect(g.flip(0), FlipOutcome.first);
      expect(g.flip(1), FlipOutcome.match);
      expect(g.flip(2), FlipOutcome.first);
      expect(g.flip(3), FlipOutcome.match);
      expect(g.completed, isTrue);
      expect(g.moves, 3);
      expect(g.bestCombo, 2);
    });

    test('存档往返：保留已配对、单张翻开与步数，错牌按盖回保存', () {
      // 未洗牌：[0,0,1,1,2,2]
      final g = MemoryGame(pairs: 3, symbols: [0, 1, 2]);
      g.flip(0);
      g.flip(1); // 配对
      g.flip(2);
      g.flip(4); // 错配，等待翻回
      final saved = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      final r = MemoryGame.fromJson(saved);
      expect(r.matchedPairs, 1);
      expect(r.moves, 2);
      expect(r.waiting, isFalse);
      expect(r.cards[2].faceUp, isFalse);
      expect(r.cards[4].faceUp, isFalse);

      r.flip(3); // 单张翻开后再存
      final r2 = MemoryGame.fromJson(r.toJson());
      expect(r2.cards[3].faceUp, isTrue);
      expect(r2.flip(2), FlipOutcome.match, reason: '恢复后能接着配对');
    });
  });

  group('回路存档', () {
    test('往返后格子、旋转、锁定与步数一致', () {
      final p = CircuitPuzzle.generate(5, random: Random(3));
      p.rotate(0);
      p.rotate(0);
      p.toggleLock(7);
      final r = CircuitPuzzle.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      );
      expect(r.moves, 2);
      expect(r.isLocked(7), isTrue);
      expect(r.poweredCount, p.poweredCount);
      for (var i = 0; i < p.cellCount; i++) {
        expect(r.maskAt(i), p.maskAt(i));
      }
    });
  });
}
