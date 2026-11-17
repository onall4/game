import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game/app.dart';
import 'package:game/core/app_services.dart';
import 'package:game/core/storage/key_value_store.dart';
import 'package:game/core/data/repositories/progress_repository.dart';
import 'package:game/games/circuit/circuit_logic.dart';
import 'package:game/games/seed.dart';
import 'package:game/games/game_registry.dart';
import 'package:game/ui/widgets/chunky.dart';

void main() {
  Future<AppServices> pumpApp(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final services = await AppServices.fromStore(MemoryStore());
    await tester.pumpWidget(ShiquApp(services: services));
    await tester.pumpAndSettle();
    return services;
  }

  /// 首页游戏变多后，靠下的卡片要先滚动到可见再点。
  Future<void> showOnHome(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: find.byType(Scrollable).first, // 首页主列表（另有横向分类列表）
    );
    await tester.pumpAndSettle();
  }

  testWidgets('首页展示全部游戏', (tester) async {
    await pumpApp(tester);
    expect(find.text('今天玩点什么？'), findsOneWidget);
    for (final g in gameRegistry) {
      await showOnHome(tester, g.title);
      expect(find.text(g.title), findsOneWidget);
    }
  });

  for (final game in gameRegistry) {
    testWidgets('能进入并切换「${game.title}」的所有难度', (tester) async {
      await pumpApp(tester);
      await showOnHome(tester, game.title);
      await tester.tap(find.text(game.title));
      await tester.pumpAndSettle();
      expect(find.text(game.modes.first.description), findsOneWidget);

      for (final m in game.modes) {
        await tester.ensureVisible(find.text(m.label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(m.label));
        await tester.pumpAndSettle();
        expect(find.text(m.description), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.byTooltip('玩法'));
      await tester.pumpAndSettle();
      expect(find.text('明白了'), findsOneWidget);
      await tester.tap(find.text('明白了'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('重新开始'), findsNothing, reason: '已回到首页');
      // 首页卡片跟随上次选择的难度
      expect(find.text('${game.modes.last.label} · 还没有纪录'), findsOneWidget);
    });

    testWidgets('「${game.title}」在窄屏 + 大字体下各难度都不溢出', (tester) async {
      await pumpApp(tester, size: const Size(360, 640), textScale: 1.3);
      // 小屏上卡片可能在首屏之外，先滚动到可见
      await tester.scrollUntilVisible(
        find.text(game.title),
        200,
        scrollable: find.byType(Scrollable).first, // 首页主列表（另有横向分类列表）
      );
      await tester.tap(find.text(game.title));
      await tester.pumpAndSettle();
      for (final m in game.modes) {
        await tester.ensureVisible(find.text(m.label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(m.label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // 左上角的难度说明放得下（必要时换行），不会被截成“…”
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(m.description),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: m.description);
      }
    });
  }

  testWidgets('设置页各难度纪录在窄屏 + 大字体下不溢出，可左右滑动', (tester) async {
    const width = 360.0;
    await pumpApp(tester, size: const Size(width, 640), textScale: 1.3);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    for (final game in gameRegistry) {
      await tester.scrollUntilVisible(
        find.text(game.title),
        200,
        scrollable: find.byType(Scrollable).first, // 设置页主列表
      );
      await tester.pumpAndSettle();
      final last = find.descendant(
        of: find.byKey(ValueKey('stats-${game.id}')),
        matching: find.text(game.modes.last.label),
      );
      final row = find.ancestor(of: last, matching: find.byType(Scrollable));
      expect(
        tester.getRect(last).right,
        greaterThan(tester.getRect(row.first).right),
        reason: '${game.title}：难度多时最后一个被遮住，需要滑动查看',
      );
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(last).right,
        lessThanOrEqualTo(tester.getRect(row.first).right + 0.5),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('密码锁：试开记录在窄屏 + 大字体下不溢出，且不限次数', (tester) async {
    await pumpApp(tester, size: const Size(360, 640), textScale: 1.3);
    await tester.tap(find.text('密码锁'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('普通'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通'));
    await tester.pumpAndSettle();

    const guesses = [
      [0, 1, 2, 3],
      [4, 5, 6, 7],
      [8, 9, 0, 1],
      [2, 4, 6, 8],
    ];
    var submitted = 0;
    for (var round = 0; round < 3; round++) {
      for (final guess in guesses) {
        for (final d in guess) {
          await tester.tap(find.widgetWithText(Pressable, '$d'));
          await tester.pump();
        }
        await tester.tap(find.text('试开'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (find.text('挑战成功！').evaluate().isNotEmpty) return; // 极小概率猜中
        submitted++;
      }
    }
    // 12 次仍可继续试开（旧版普通难度只有 10 次机会）
    expect(find.text('$submitted 次'), findsOneWidget);
    expect(find.text('试开'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\dA\dB')), findsNothing);
  });

  testWidgets('回路：输入种子得到由种子决定的开局，退出再进来仍是这局', (tester) async {
    final services = await pumpApp(tester);
    await tester.tap(find.text('回路'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining(RegExp(r'^#'))); // 点左上角的种子
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1K7Q2XM');
    await tester.tap(find.text('用这个种子开始'));
    await tester.pumpAndSettle();
    expect(find.text('#1K7Q2XM'), findsOneWidget);

    await tester.tap(find.byTooltip('返回')); // 离开时保存存档
    await tester.pumpAndSettle();
    final saved = services.progress.load('circuit', 'size4')!;
    expect(saved[ProgressRepository.seedKey], '1K7Q2XM');
    expect(saved[ProgressRepository.customSeedKey], isTrue);
    final expected = CircuitPuzzle.generate(
      4,
      random: SeededRandom.forGame(GameSeed.tryParse('1K7Q2XM')!, 'size4'),
    ).toJson();
    final puzzle = (saved['puzzle'] as Map).cast<String, dynamic>();
    expect(puzzle['tiles'], expected['tiles']);
    expect(puzzle['turns'], expected['turns']);

    await tester.tap(find.text('回路'));
    await tester.pumpAndSettle();
    expect(find.text('#1K7Q2XM'), findsOneWidget);
  });

  testWidgets('返回后再进入继续上一局；重新开始换成新的一局', (tester) async {
    final services = await pumpApp(tester);
    Finder rotations() => find.descendant(
      of: find.widgetWithText(StatPill, '旋转'),
      matching: find.byType(Text),
    );
    String rotationValue() => tester.widgetList<Text>(rotations()).last.data!;

    await tester.tap(find.text('回路'));
    await tester.pumpAndSettle();
    expect(rotationValue(), '0');

    // 转动左上角的格子（偶数边长时棋盘正中是格缝，点不到格子）
    await tester.tap(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(rotationValue(), '1');

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(services.progress.hasUnfinished('circuit', 'size4'), isTrue);
    expect(find.text('进行中'), findsOneWidget, reason: '首页卡片提示有未完成对局');

    await tester.tap(find.text('回路'));
    await tester.pumpAndSettle();
    expect(rotationValue(), '1', reason: '应继续上一局');

    // 未完成对局点重新开始需先确认；点取消保留原进度
    await tester.tap(find.byTooltip('重新开始'));
    await tester.pumpAndSettle();
    expect(find.text('重新开始？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(rotationValue(), '1');

    await tester.tap(find.byTooltip('重新开始'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChunkyButton, '重新开始'));
    await tester.pumpAndSettle();
    expect(rotationValue(), '0');

    // 离开时新的一局同样会被保存，再进来是这局新的，而不是旧局
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回路'));
    await tester.pumpAndSettle();
    expect(rotationValue(), '0', reason: '重新开始后不应再恢复旧局');
  });
}
