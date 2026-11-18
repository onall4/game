import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game/app.dart';
import 'package:game/core/app_services.dart';
import 'package:game/core/data/models/score_kind.dart';
import 'package:game/core/storage/key_value_store.dart';
import 'package:game/games/onestroke/onestroke_logic.dart';
import 'package:game/games/twentyfour/twentyfour_logic.dart';
import 'package:game/ui/theme/app_theme.dart';

Future<AppServices> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final services = await AppServices.fromStore(MemoryStore());
  await tester.pumpWidget(ShiquApp(services: services));
  await tester.pumpAndSettle();
  return services;
}

/// 从首页进入游戏（靠下的卡片先滚动到可见）。
Future<void> _enter(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('返回'));
  await tester.pumpAndSettle();
}

String _statValue(WidgetTester tester, String label) {
  final texts = find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byType(Text),
  );
  return tester.widgetList<Text>(texts).last.data!;
}

void main() {
  testWidgets('舒尔特 3×3：点错计失误加罚时，按顺序点完即通关', (tester) async {
    final services = await _pumpApp(tester);
    await _enter(tester, '舒尔特方格');
    Finder number(int n) => find.descendant(
      of: find.byKey(const ValueKey('schulte-board')),
      matching: find.text('$n'),
    );

    Color tileColor(int n) {
      final c = tester.widget<AnimatedContainer>(
        find.ancestor(of: number(n), matching: find.byType(AnimatedContainer)),
      );
      return (c.decoration! as BoxDecoration).color!;
    }

    await tester.tap(number(9));
    await tester.pump();
    expect(tileColor(9), AppColors.coral, reason: '点错短暂闪红');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tileColor(9), AppColors.paper);
    expect(_statValue(tester, '失误'), '1');

    for (var n = 1; n <= 9; n++) {
      expect(_statValue(tester, '下一个'), '$n');
      await tester.tap(number(n));
      await tester.pump();
      if (n == 1) {
        expect(tileColor(1), AppColors.mint, reason: '点对短暂闪绿反馈');
        await tester.pump(const Duration(milliseconds: 300));
        expect(tileColor(1), AppColors.paper, reason: '闪过之后恢复统一外观，不留标记');
      }
    }
    await tester.pumpAndSettle();
    expect(find.text('挑战成功！'), findsOneWidget);
    expect(find.text('1 次 · +1 秒'), findsOneWidget);
    final best = services.records
        .recordOf('schulte', ScoreKind.preciseTimeMs)
        .mode('s3')
        .best;
    expect(best, greaterThanOrEqualTo(1000), reason: '成绩含 1 秒罚时');
  });

  testWidgets('一笔画：沿解法拖动一笔画完即通关，往回拖会退回', (tester) async {
    final services = await _pumpApp(tester);
    await _enter(tester, '一笔画');
    // 先退出一次把题目存下来，算出解法后再进来
    await _back(tester);
    final saved = services.progress.load('onestroke', 'o4')!;
    final puzzle = OneStrokePuzzle.fromJson(
      (saved['puzzle'] as Map).cast<String, dynamic>(),
    );
    final path = puzzle.solve()!;
    await _enter(tester, '一笔画');

    final board = tester.getRect(find.byKey(const ValueKey('onestroke-board')));
    final cell = board.width / puzzle.cols;
    Offset center(int i) =>
        board.topLeft +
        Offset((i % puzzle.cols + 0.5) * cell, (i ~/ puzzle.cols + 0.5) * cell);

    final gesture = await tester.startGesture(center(path[0]));
    for (final i in path.skip(1).take(2)) {
      await gesture.moveTo(center(i));
      await tester.pump();
    }
    expect(_statValue(tester, '进度'), '3/${puzzle.openCount}');
    await gesture.moveTo(center(path[1])); // 往回拖一格
    await tester.pump();
    expect(_statValue(tester, '进度'), '2/${puzzle.openCount}');
    for (final i in path.skip(2)) {
      await gesture.moveTo(center(i));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('挑战成功！'), findsOneWidget);
    expect(services.records.recordOf('onestroke', ScoreKind.timeMs).plays, 1);
  });

  testWidgets('一笔画：点提示再选格子显示走向；用过提示的对局不计最佳', (tester) async {
    final services = await _pumpApp(tester);
    await _enter(tester, '一笔画');
    await _back(tester);
    final saved = services.progress.load('onestroke', 'o4')!;
    final puzzle = OneStrokePuzzle.fromJson(
      (saved['puzzle'] as Map).cast<String, dynamic>(),
    );
    final path = puzzle.solve()!;
    await _enter(tester, '一笔画');

    final board = tester.getRect(find.byKey(const ValueKey('onestroke-board')));
    final cell = board.width / puzzle.cols;
    Offset center(int i) =>
        board.topLeft +
        Offset((i % puzzle.cols + 0.5) * cell, (i ~/ puzzle.cols + 0.5) * cell);

    await tester.tap(find.text('提示 3'));
    await tester.pump();
    expect(find.text('答案可能不止一种，提示按同一种固定走法给出。点一个格子看它的走向'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    await tester.tapAt(center(path[1]));
    await tester.pump();
    expect(find.text('提示 2'), findsOneWidget);
    expect(
      _statValue(tester, '进度'),
      '1/${puzzle.openCount}',
      reason: '选提示格子不会画线',
    );

    // 点格子逐步画完
    for (final i in path.skip(1)) {
      await tester.tapAt(center(i));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('挑战成功！'), findsOneWidget);
    expect(find.text('本局使用了提示，不计入最佳纪录'), findsOneWidget);
    final record = services.records.recordOf('onestroke', ScoreKind.timeMs);
    expect(record.plays, 1);
    expect(record.mode('o4').best, isNull);
  });

  /// 找出把这几张牌算成 24 的步骤：(第一张, 运算符, 第二张)。
  List<(int, Op, int)>? findSteps(List<Fraction?> slots) {
    final live = [
      for (var i = 0; i < slots.length; i++)
        if (slots[i] != null) i,
    ];
    if (live.length == 1) {
      return slots[live.single]!.equalsInt(goal) ? [] : null;
    }
    for (final a in live) {
      for (final b in live) {
        if (a == b) continue;
        for (final op in Op.values) {
          final v = op.apply(slots[a]!, slots[b]!);
          if (v == null) continue;
          final next = [...slots]
            ..[b] = v
            ..[a] = null;
          final rest = findSteps(next);
          if (rest != null) return [(a, op, b), ...rest];
        }
      }
    }
    return null;
  }

  testWidgets('24点：点牌、运算符、牌依次算出每道题即通关', (tester) async {
    final services = await _pumpApp(tester);
    await _enter(tester, '24点');
    await _back(tester);
    final saved = services.progress.load('twentyfour', 't1')!;
    final game = TwentyFourGame.fromJson(
      TwentyFourLevel.beginner,
      (saved['game'] as Map).cast<String, dynamic>(),
    );
    await _enter(tester, '24点');

    for (final (i, puzzle) in game.puzzles.indexed) {
      expect(_statValue(tester, '题目'), '${i + 1}/${game.total}');
      int? selected;
      for (final (a, op, b) in findSteps([
        for (final n in puzzle) Fraction(n),
      ])!) {
        // 上一步的结果会自动选中，再点一次反而会取消
        if (selected != a) {
          await tester.tap(find.byKey(ValueKey('card$a')));
          await tester.pump();
        }
        await tester.tap(find.text(op.symbol));
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('card$b')));
        await tester.pumpAndSettle();
        selected = b;
      }
    }
    expect(find.text('挑战成功！'), findsOneWidget);
    expect(services.records.recordOf('twentyfour', ScoreKind.timeMs).plays, 1);
  });

  testWidgets('24点：看答案前先确认，确认后显示答案', (tester) async {
    await _pumpApp(tester);
    await _enter(tester, '24点');
    await tester.tap(find.text('答案'));
    await tester.pumpAndSettle();
    expect(find.text('看答案？'), findsOneWidget);
    await tester.tap(find.text('再想想'));
    await tester.pumpAndSettle();
    expect(find.textContaining('答案：'), findsNothing);

    await tester.tap(find.text('答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('看答案'));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^答案：.+ = 24$')), findsOneWidget);
  });
}
