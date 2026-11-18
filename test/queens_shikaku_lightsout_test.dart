import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game/app.dart';
import 'package:game/core/app_services.dart';
import 'package:game/core/data/models/score_kind.dart';
import 'package:game/core/storage/key_value_store.dart';
import 'package:game/games/lightsout/lightsout_logic.dart';
import 'package:game/games/lightsout/lightsout_page.dart';
import 'package:game/games/queens/queens_logic.dart';
import 'package:game/games/queens/queens_page.dart';
import 'package:game/games/seed.dart';
import 'package:game/games/shikaku/shikaku_logic.dart';
import 'package:game/games/shikaku/shikaku_page.dart';

Future<AppServices> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final services = await AppServices.fromStore(MemoryStore());
  await tester.pumpWidget(ShiquApp(services: services));
  await tester.pumpAndSettle();
  return services;
}

Future<void> _enter(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('返回'));
  await tester.pumpAndSettle();
}

void main() {
  group('皇冠逻辑', () {
    test('各难度生成的题目：区域连通、只有唯一解且同种子确定', () {
      for (final modeId in ['q5', 'q6', 'q7', 'q8', 'q9']) {
        final size = QueensGameView.sizeFor(modeId);
        for (var s = 0; s < 6; s++) {
          QueensPuzzle make() =>
              QueensPuzzle.generate(size, random: SeededRandom(s));
          final p = make();
          expect(countQueensSolutions(size, p.regions), 1, reason: modeId);
          expect(make().toJson(), p.toJson());
          for (var r = 0; r < size; r++) {
            expect(p.placeCrown(r * size + p.solution[r]), isTrue);
          }
          expect(p.solved, isTrue);
          expect(p.conflicts, isEmpty);
        }
      }
    });

    test('单击切换 ×、双击放皇冠、冲突检测、提示锁定与存档往返', () {
      final p = QueensPuzzle.fromRegions(
        size: 4,
        regions: const [
          0, 0, 1, 1, //
          0, 2, 1, 1,
          2, 2, 3, 1,
          2, 3, 3, 3,
        ],
        solution: const [1, 3, 0, 2],
      );
      // 单击在空白与 × 之间切换
      expect(p.toggleCross(0), isTrue);
      expect(p.markAt(0), QueenMark.cross);
      expect(p.toggleCross(0), isTrue);
      expect(p.markAt(0), QueenMark.empty);

      // 斜角相邻冲突：(0,1) 与 (1,2)
      p.placeCrown(1);
      p.placeCrown(6);
      expect(p.conflicts, {1, 6});
      p.toggleCross(6); // 已有皇冠单击取下变回空白
      expect(p.markAt(6), QueenMark.empty);
      expect(p.conflicts, isEmpty);

      // 批量标 × 不会覆盖皇冠
      expect(p.setCross(1, cross: true), isFalse);
      expect(p.setCross(0, cross: true), isTrue);
      expect(p.markAt(0), QueenMark.cross);

      // 提示锁定后不可再修改
      expect(p.applyHint(7), isTrue);
      expect(p.markAt(7), QueenMark.crown);
      expect(p.toggleCross(7), isFalse);
      expect(p.placeCrown(7), isFalse);

      final restored = QueensPuzzle.fromJson(p.toJson());
      expect(restored.toJson(), p.toJson());
    });
  });

  group('数方逻辑', () {
    test('各难度生成的题目：面积总和等于格数、只有唯一解且同种子确定', () {
      for (final modeId in ['sk5', 'sk6', 'sk7', 'sk8', 'sk9', 'sk10']) {
        final cfg = ShikakuGameView.configFor(modeId);
        for (var s = 0; s < 5; s++) {
          ShikakuPuzzle make() => ShikakuPuzzle.generate(
            cfg.size,
            maxArea: cfg.maxArea,
            random: SeededRandom(s),
          );
          final p = make();
          expect(countShikakuSolutions(cfg.size, p.clues), 1, reason: modeId);
          expect(make().toJson(), p.toJson());
          for (final rect in p.solution) {
            expect(p.place(rect), isTrue);
          }
          expect(p.solved, isTrue);
        }
      }
    });

    test('新矩形不覆盖已有矩形，仅点击清除后才能重画；提示保护与存档往返', () {
      final p = ShikakuPuzzle.fromClues(
        size: 3,
        clues: const [
          0, 3, 0, //
          4, 0, 2,
          0, 0, 0,
        ],
        solution: const [
          ShikakuRect(0, 0, 0, 2),
          ShikakuRect(1, 0, 2, 1),
          ShikakuRect(1, 2, 2, 2),
        ],
      );
      expect(p.place(const ShikakuRect(0, 0, 1, 1)), isTrue);
      expect(p.isRectValid(p.rects.single), isFalse, reason: '含两个数字，不合法');

      // 与已有矩形重叠时拒绝放置，已有矩形保持原样
      expect(p.place(const ShikakuRect(0, 0, 0, 2)), isFalse);
      expect(p.rects, [const ShikakuRect(0, 0, 1, 1)]);

      // 点击清除旧矩形后才能放置新矩形
      expect(p.removeAt(0, 0), isTrue);
      expect(p.rects, isEmpty);
      expect(p.place(const ShikakuRect(0, 0, 0, 2)), isTrue);
      expect(p.isRectValid(p.rects.single), isTrue);

      // 提示锁定的矩形不能被删除或覆盖
      expect(p.applyHint(5), isTrue);
      expect(p.removeAt(1, 2), isFalse);
      expect(p.place(const ShikakuRect(0, 2, 2, 2)), isFalse);

      final restored = ShikakuPuzzle.fromJson(p.toJson());
      expect(restored.toJson(), p.toJson());
    });
  });

  group('电灯逻辑', () {
    test('GF(2) 求解器对各难度与任意随机按键组合都能找到全部点亮的最少步数解', () {
      for (final modeId in ['lo3', 'lo4e', 'lo4', 'lo5e', 'lo5', 'lo6']) {
        final cfg = LightsOutGameView.configFor(modeId);
        for (var s = 0; s < 5; s++) {
          final g = LightsOutGame.generate(cfg, random: SeededRandom(s));
          expect(g.optimalMoves, inInclusiveRange(cfg.minSteps, cfg.maxSteps));
          final sol = g.solveCurrent();
          expect(sol.length, g.optimalMoves);
          for (final cell in sol) {
            g.toggle(cell);
          }
          expect(g.solved, isTrue);
          expect(g.litCount, g.cellCount);
        }
      }
      final rng = Random(42);
      for (final size in [3, 4, 5, 6]) {
        final n = size * size;
        for (var trial = 0; trial < 20; trial++) {
          final g = LightsOutGame.generate(
            LightsOutConfig(size: size, minSteps: 2, maxSteps: min(10, n)),
            random: rng,
          );
          final sol = g.solveCurrent();
          expect(sol.length, g.optimalMoves);
          for (final cell in sol) {
            g.toggle(cell);
          }
          expect(g.solved, isTrue);
          expect(g.litCount, n);
        }
      }
    });

    test('提示与存档往返', () {
      final g = LightsOutGame.fromLitCells(
        size: 3,
        litCells: const [2, 4, 5, 6, 7, 8], // 仅 0,1,3 未亮，按左上角 0 即可全部点亮
      );
      expect(g.optimalMoves, 1);
      final hint = g.applyHint();
      expect(hint, 0);
      expect(g.hintsLeft, LightsOutGame.maxHints - 1);

      final restored = LightsOutGame.fromJson(3, g.toJson());
      expect(restored.activeHint, 0);
      restored.toggle(0);
      expect(restored.solved, isTrue);
      expect(restored.litCount, 9);
    });
  });

  group('三款新游戏界面通关流程', () {
    testWidgets('皇冠：单击切换 ×，双击放置皇冠，放满唯一解即通关', (tester) async {
      final services = await _pumpApp(tester);
      await _enter(tester, '皇冠');
      await _back(tester);
      final saved = services.progress.load('queens', 'q5')!;
      final puzzle = QueensPuzzle.fromJson(
        (saved['puzzle'] as Map).cast<String, dynamic>(),
      );
      await _enter(tester, '皇冠');

      final board = tester.getRect(find.byKey(const ValueKey('queens-board')));
      final cell = board.width / puzzle.size;
      Offset cellPos(int r, int c) =>
          board.topLeft + Offset((c + 0.5) * cell, (r + 0.5) * cell);

      // 单击非皇冠格：空白 → ×；间隔后再单击：× → 空白
      final emptyCol = (puzzle.solution[0] + 1) % puzzle.size;
      await tester.tapAt(cellPos(0, emptyCol));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.tapAt(cellPos(0, emptyCol));
      await tester.pump(const Duration(milliseconds: 450));

      // 双击各行正确位置放置皇冠
      for (var r = 0; r < puzzle.size; r++) {
        final pos = cellPos(r, puzzle.solution[r]);
        await tester.tapAt(pos);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(pos);
        await tester.pump(const Duration(milliseconds: 450));
      }
      await tester.pumpAndSettle();
      expect(find.text('挑战成功！'), findsOneWidget);
      expect(services.records.recordOf('queens', ScoreKind.timeMs).plays, 1);
    });

    testWidgets('数方：拖动不覆盖已有矩形，点击清除后框出全部矩形即通关', (tester) async {
      final services = await _pumpApp(tester);
      await _enter(tester, '数方');
      await _back(tester);
      final saved = services.progress.load('shikaku', 'sk5')!;
      final puzzle = ShikakuPuzzle.fromJson(
        (saved['puzzle'] as Map).cast<String, dynamic>(),
      );
      await _enter(tester, '数方');

      final board = tester.getRect(find.byKey(const ValueKey('shikaku-board')));
      final cell = board.width / puzzle.size;
      Offset center(int r, int c) =>
          board.topLeft + Offset((c + 0.5) * cell, (r + 0.5) * cell);

      // 先画第一个矩形，再尝试画一个与它重叠的框：不应覆盖已有矩形
      final first = puzzle.solution.first;
      var g = await tester.startGesture(center(first.r1, first.c1));
      await g.moveTo(center(first.r2, first.c2));
      await g.up();
      await tester.pump();
      expect(find.text('1/${puzzle.clueCount}'), findsOneWidget);

      // 点击该矩形将其清除，再按唯一解全部框出
      await tester.tapAt(center(first.r1, first.c1));
      await tester.pump();
      expect(find.text('0/${puzzle.clueCount}'), findsOneWidget);

      for (final rect in puzzle.solution) {
        g = await tester.startGesture(center(rect.r1, rect.c1));
        await g.moveTo(center(rect.r2, rect.c2));
        await g.up();
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('挑战成功！'), findsOneWidget);
      expect(services.records.recordOf('shikaku', ScoreKind.timeMs).plays, 1);
    });

    testWidgets('电灯：按最优解点击全部点亮即通关', (tester) async {
      final services = await _pumpApp(tester);
      await _enter(tester, '电灯');
      await _back(tester);
      final saved = services.progress.load('lightsout', 'lo3')!;
      final game = LightsOutGame.fromJson(
        3,
        (saved['game'] as Map).cast<String, dynamic>(),
      );
      await _enter(tester, '电灯');

      for (final cell in game.solveCurrent()) {
        await tester.tap(find.byKey(ValueKey('lamp-$cell')));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('挑战成功！'), findsOneWidget);
      expect(services.records.recordOf('lightsout', ScoreKind.moves).plays, 1);
    });
  });
}
