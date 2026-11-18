import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:game/games/onestroke/onestroke_logic.dart';
import 'package:game/games/onestroke/onestroke_page.dart';
import 'package:game/games/schulte/schulte_logic.dart';
import 'package:game/games/seed.dart';
import 'package:game/games/twentyfour/twentyfour_logic.dart';

void main() {
  group('舒尔特方格', () {
    test('方格是 1…N² 的排列，按顺序点完即完成', () {
      const config = SchulteConfig(size: 4);
      final g = SchulteGame(config, random: SeededRandom(1));
      expect([...g.cells]..sort(), List.generate(16, (i) => i + 1));
      for (var n = 1; n <= 16; n++) {
        expect(g.completed, isFalse);
        expect(g.tap(g.cells.indexOf(n)), SchulteTap.correct);
      }
      expect(g.completed, isTrue);
      expect(g.mistakes, 0);
      expect(g.tap(0), SchulteTap.ignored, reason: '完成后点击无效');
    });

    test('点错计失误；已点过的数字不特殊豁免', () {
      final g = SchulteGame(const SchulteConfig(size: 3), random: Random(2));
      expect(g.tap(g.cells.indexOf(5)), SchulteTap.wrong);
      expect(g.mistakes, 1);
      expect(g.tap(g.cells.indexOf(1)), SchulteTap.correct);
      expect(g.tap(g.cells.indexOf(1)), SchulteTap.wrong);
      expect(g.mistakes, 2);
    });

    test('倒序从最大的数点到 1', () {
      final g = SchulteGame(
        const SchulteConfig(size: 3, descending: true),
        random: Random(3),
      );
      expect(g.next, 9);
      expect(g.tap(g.cells.indexOf(1)), SchulteTap.wrong);
      for (var n = 9; n >= 1; n--) {
        expect(g.tap(g.cells.indexOf(n)), SchulteTap.correct);
      }
      expect(g.completed, isTrue);
    });

    test('洗牌模式每点对一个就重新排列；存档恢复后接着生成同一串随机数', () {
      const config = SchulteConfig(size: 5, reshuffle: true);
      final a = SchulteGame(config, random: SeededRandom(4));
      final before = [...a.cells];
      a.tap(a.cells.indexOf(1));
      expect(a.cells, isNot(before));
      expect([...a.cells]..sort(), List.generate(25, (i) => i + 1));

      final b = SchulteGame.fromJson(config, a.toJson());
      for (var k = 0; k < 5; k++) {
        a.tap(a.cells.indexOf(a.next));
        b.tap(b.cells.indexOf(b.next));
        expect(b.cells, a.cells);
      }
    });

    test('存档不合法时抛出异常', () {
      const config = SchulteConfig(size: 3);
      expect(
        () => SchulteGame.fromJson(config, {
          'cells': [1, 2, 3],
          'next': 1,
        }),
        throwsFormatException,
      );
    });
  });

  group('一笔画', () {
    test('各难度生成的题：障碍数在范围内、一定有解、同一种子结果相同', () {
      for (final id in ['o4', 'o5', 'o6', 'o7', 'o8', 'o9']) {
        final c = OneStrokeGameView.configFor(id);
        for (var s = 0; s < 8; s++) {
          OneStrokePuzzle make() => OneStrokePuzzle.generate(
            cols: c.cols,
            rows: c.rows,
            minWalls: c.minWalls,
            maxWalls: c.maxWalls,
            random: SeededRandom(s),
          );
          final p = make();
          final walls = p.walls.where((w) => w).length;
          expect(walls, inInclusiveRange(c.minWalls, c.maxWalls), reason: id);
          expect(p.walls[p.start], isFalse);
          expect(make().toJson(), p.toJson(), reason: '$id 种子 $s');

          final path = p.solve();
          expect(path, isNotNull, reason: '$id 种子 $s 应有解');
          expect(path!.length, p.openCount);
          expect(path.toSet().length, path.length);
          expect(path.first, p.start);
        }
      }
    });

    test('沿解法走完即完成；往回走一格会退回', () {
      final p = OneStrokePuzzle.generate(
        cols: 5,
        rows: 5,
        minWalls: 2,
        maxWalls: 3,
        random: SeededRandom(9),
      );
      final path = p.solve()!;
      expect(p.moveTo(path[1]), StrokeMove.extended);
      expect(p.moveTo(path[0]), StrokeMove.retracted);
      expect(p.path, [p.start]);
      for (final i in path.skip(1)) {
        expect(p.completed, isFalse);
        expect(p.moveTo(i), StrokeMove.extended);
      }
      expect(p.completed, isTrue);
      expect(p.moveTo(path[path.length - 2]), StrokeMove.ignored);
    });

    test('不相邻、障碍、走过的格子都走不了；点路径上的格子可截断', () {
      // 3×3，中间是障碍，从左上角出发
      final p = OneStrokePuzzle.fromLayout(
        cols: 3,
        rows: 3,
        walls: {4},
        start: 0,
      );
      expect(p.openCount, 8);
      expect(p.moveTo(8), StrokeMove.ignored, reason: '不相邻');
      expect(p.moveTo(1), StrokeMove.extended);
      expect(p.moveTo(4), StrokeMove.ignored, reason: '障碍');
      expect(p.moveTo(2), StrokeMove.extended);
      expect(p.moveTo(5), StrokeMove.extended);
      expect(p.moveTo(2), StrokeMove.retracted);
      expect(p.moveTo(5), StrokeMove.extended);
      expect(p.truncateTo(1), isTrue);
      expect(p.path, [0, 1]);
      expect(p.truncateTo(1), isFalse, reason: '已经是末端');
      expect(p.truncateTo(7), isFalse, reason: '不在路径上');
    });

    test('提示：每局 3 次，走向来自同一条完整的解法', () {
      final p = OneStrokePuzzle.generate(
        cols: 6,
        rows: 6,
        minWalls: 3,
        maxWalls: 5,
        random: SeededRandom(5),
      );
      final wall = p.walls.indexOf(true);
      expect(p.applyHint(wall), isFalse, reason: '障碍不能提示');
      final open = [
        for (var i = 0; i < p.walls.length; i++)
          if (!p.walls[i]) i,
      ];
      for (final i in open.take(3)) {
        expect(p.applyHint(i), isTrue);
        expect(p.applyHint(i), isFalse, reason: '同一格不重复扣次数');
      }
      expect(p.hintsLeft, 0);
      expect(p.applyHint(open[3]), isFalse, reason: '次数用完');

      // 三个提示的走向能拼进同一条从起点出发、走遍所有空格的路线
      final hints = p.hints;
      expect(hints.length, 3);
      for (final MapEntry(key: i, value: (:from, :to)) in hints.entries) {
        expect(from == null, i == p.start, reason: '只有起点没有来向');
        for (final n in [from, to]) {
          if (n == null) continue;
          expect(p.walls[n], isFalse);
          final dr = (n ~/ p.cols - i ~/ p.cols).abs();
          final dc = (n % p.cols - i % p.cols).abs();
          expect(dr + dc, 1, reason: '走向指向相邻的格子');
        }
      }
    });

    test('提示优先接着玩家当前的路线（路线还走得通时）', () {
      final p = OneStrokePuzzle.generate(
        cols: 7,
        rows: 7,
        minWalls: 4,
        maxWalls: 6,
        random: SeededRandom(11),
      );
      final solution = p.solve()!;
      for (final i in solution.skip(1).take(4)) {
        p.moveTo(i);
      }
      // 提示路线上已经走过的一格：来向和去向应与玩家走的一致
      expect(p.applyHint(solution[2]), isTrue);
      expect(p.hints[solution[2]], (from: solution[1], to: solution[3]));
    });

    test('存档往返；不合法的路径会被拒绝', () {
      final p = OneStrokePuzzle.fromLayout(
        cols: 3,
        rows: 3,
        walls: {4},
        start: 0,
      )..moveTo(1);
      final restored = OneStrokePuzzle.fromJson(p.toJson());
      expect(restored.toJson(), p.toJson());

      // 提示与参考路线一起存档
      p.applyHint(8);
      final withHint = OneStrokePuzzle.fromJson(p.toJson());
      expect(withHint.hints, p.hints);
      expect(withHint.hintsLeft, OneStrokePuzzle.maxHints - 1);
      // 参考路线不合法时，提示一起丢弃
      final broken = p.toJson()..['solution'] = [0, 1];
      expect(OneStrokePuzzle.fromJson(broken).hintsUsed, 0);

      final bad = p.toJson()..['path'] = [0, 2];
      expect(() => OneStrokePuzzle.fromJson(bad), throwsFormatException);
    });
  });

  group('24点', () {
    test('分数运算约到最简', () {
      expect(Fraction(4, 6), Fraction(2, 3));
      expect(Fraction(3, -6).toString(), '-1/2');
      expect(Fraction(8) - Fraction(8, 3), Fraction(16, 3));
      expect((Fraction(8, 3) * Fraction(3)).toString(), '8');
      expect(Fraction(1).divide(Fraction(0)), isNull);
      expect(Fraction.parse('8/3'), Fraction(8, 3));
      expect(Fraction.parse('-5'), Fraction(-5));
    });

    test('经典难题的分析与答案', () {
      final a = analyze([3, 3, 8, 8]);
      expect(a.solvable, isTrue);
      expect(a.needsFraction, isTrue);
      expect(bestSolution([3, 3, 8, 8])!.expression, '8 ÷ (3 − 8 ÷ 3)');
      expect(analyze([1, 1, 1, 1]).solvable, isFalse);
      expect(analyze([6, 6, 6, 6]).needsDivision, isFalse);
      expect(analyze([4, 4, 10, 10]).needsDivision, isTrue);
      expect(bestSolution([1, 2, 3, 4])!.fractional, isFalse);
    });

    test('“必须经过分数”的组合表完整且准确', () {
      final computed = <String>[];
      for (var a = 1; a <= 13; a++) {
        for (var b = a; b <= 13; b++) {
          for (var c = b; c <= 13; c++) {
            for (var d = c; d <= 13; d++) {
              if (analyze([a, b, c, d]).needsFraction) {
                computed.add('$a,$b,$c,$d');
              }
            }
          }
        }
      }
      expect([for (final s in fractionOnlySets) s.join(',')], computed);
    });

    test('每个难度出的题都符合该难度，且同一局不重复', () {
      for (final level in TwentyFourLevel.values) {
        for (var s = 0; s < 5; s++) {
          final puzzles = generatePuzzles(level, SeededRandom(s));
          expect(puzzles.length, level.puzzles);
          final keys = {
            for (final p in puzzles) ([...p]..sort()).join(','),
          };
          expect(keys.length, puzzles.length, reason: '${level.name} 有重复');
          for (final p in puzzles) {
            expect(p.every((n) => n >= 1 && n <= level.maxNumber), isTrue);
            expect(level.accepts(analyze(p)), isTrue, reason: '$p');
          }
        }
      }
    });

    test('合牌与撤销：结果放在第二张牌的位置', () {
      final g = TwentyFourGame.withPuzzles(TwentyFourLevel.master, [
        [3, 3, 8, 8],
        [6, 6, 6, 6],
        [1, 2, 3, 4],
      ]);
      expect(g.combine(2, Op.div, 0), CombineResult.combined); // 8 ÷ 3
      expect(g.slots, [Fraction(8, 3), Fraction(3), null, Fraction(8)]);
      expect(g.combine(0, Op.add, 0), CombineResult.invalid, reason: '同一张');
      expect(g.combine(2, Op.add, 0), CombineResult.invalid, reason: '空牌位');
      expect(g.undo(), isTrue);
      expect(g.slots, [Fraction(3), Fraction(3), Fraction(8), Fraction(8)]);
      expect(g.undo(), isFalse);
    });

    test('算对一题后换下一题，算错时提示', () {
      final g = TwentyFourGame.withPuzzles(TwentyFourLevel.master, [
        [3, 3, 8, 8],
        [6, 6, 6, 6],
        [1, 2, 3, 4],
      ]);
      // 8 ÷ 3 = 8/3 → 位置 0；3 − 8/3 = 1/3 → 位置 0；8 ÷ 1/3 = 24 → 位置 0
      expect(g.combine(2, Op.div, 0), CombineResult.combined);
      expect(g.slots[0], Fraction(8, 3));
      // 想要 3 − 8/3，要把 3（位置 1）作为第一张：combine(1, sub, 0) 得 3 − 8/3
      expect(g.combine(1, Op.sub, 0), CombineResult.combined);
      expect(g.slots[0], Fraction(1, 3));
      expect(g.combine(3, Op.div, 0), CombineResult.solved);
      expect(g.index, 1);
      expect(g.slots, List.filled(4, Fraction(6)));
      expect(g.canUndo, isFalse);

      // 6 + 6 + 6 − 6 = 12，算错
      expect(g.combine(0, Op.add, 1), CombineResult.combined);
      expect(g.combine(1, Op.add, 2), CombineResult.combined);
      expect(g.combine(2, Op.sub, 3), CombineResult.wrong);
      expect(g.index, 1, reason: '算错不进入下一题');
      expect(g.reset(), isTrue);
      expect(g.slots, List.filled(4, Fraction(6)));
      expect(g.combine(0, Op.sub, 1), CombineResult.combined); // 0
      expect(g.combine(2, Op.div, 1), CombineResult.divideByZero);
    });

    test('看答案计数；存档往返（含分数与撤销记录）', () {
      final g = TwentyFourGame.withPuzzles(TwentyFourLevel.master, [
        [3, 3, 8, 8],
        [6, 6, 6, 6],
        [1, 2, 3, 4],
      ]);
      expect(g.revealAnswer(), '8 ÷ (3 − 8 ÷ 3)');
      expect(g.answersShown, 1);
      expect(g.answerShown, isTrue);
      g.combine(2, Op.div, 0);

      final r = TwentyFourGame.fromJson(TwentyFourLevel.master, g.toJson());
      expect(r.slots, g.slots);
      expect(r.answersShown, 1);
      expect(r.undo(), isTrue);
      expect(r.slots, [Fraction(3), Fraction(3), Fraction(8), Fraction(8)]);
      expect(
        () => TwentyFourGame.fromJson(TwentyFourLevel.easy, g.toJson()),
        throwsFormatException,
        reason: '题数与难度不符',
      );
    });
  });
}
