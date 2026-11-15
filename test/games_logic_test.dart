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
      const cfg = CodeConfig(
        length: 4,
        symbols: 10,
        maxAttempts: 10,
        allowRepeat: false,
      );
      for (var seed = 0; seed < 50; seed++) {
        final g = CodeBreakerGame(cfg, random: Random(seed));
        expect(g.secret.length, 4);
        expect(g.secret.toSet().length, 4);
        expect(g.secret.every((d) => d >= 0 && d <= 9), isTrue);
      }
    });

    test('胜负判定与校验', () {
      const cfg = CodeConfig(
        length: 3,
        symbols: 6,
        firstSymbol: 1,
        maxAttempts: 2,
        allowRepeat: false,
      );
      final g = CodeBreakerGame(cfg, secret: [1, 2, 3]);
      expect(g.validate([1, 2]), GuessError.incomplete);
      expect(g.validate([1, 1, 2]), GuessError.repeated);
      g.submit([3, 2, 1]);
      expect(g.over, isFalse);
      g.submit([1, 2, 3]);
      expect(g.won, isTrue);
      expect(g.attemptsUsed, 2);

      final g2 = CodeBreakerGame(cfg, secret: [1, 2, 3]);
      g2.submit([4, 5, 6]);
      g2.submit([6, 5, 4]);
      expect(g2.lost, isTrue);
      expect(() => g2.submit([1, 2, 3]), throwsStateError);
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
  });
}
