import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game/app.dart';
import 'package:game/core/app_services.dart';
import 'package:game/core/storage/key_value_store.dart';
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

  testWidgets('首页展示全部游戏', (tester) async {
    await pumpApp(tester);
    expect(find.text('今天玩点什么？'), findsOneWidget);
    for (final g in gameRegistry) {
      expect(find.text(g.title), findsOneWidget);
    }
  });

  for (final game in gameRegistry) {
    testWidgets('能进入并切换「${game.title}」的所有难度', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text(game.title));
      await tester.pumpAndSettle();
      expect(find.text(game.modes.first.description), findsOneWidget);

      for (final m in game.modes) {
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
      expect(find.text('今天玩点什么？'), findsOneWidget);
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
        await tester.tap(find.text(m.label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('密码锁：试开记录在窄屏 + 大字体下不溢出，且不限次数', (tester) async {
    await pumpApp(tester, size: const Size(360, 640), textScale: 1.3);
    await tester.tap(find.text('密码锁'));
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

  testWidgets('返回后再进入继续上一局；重新开始会清掉进度', (tester) async {
    final services = await pumpApp(tester);
    Finder rotations() => find.descendant(
      of: find.widgetWithText(StatPill, '旋转'),
      matching: find.byType(Text),
    );
    String rotationValue() => tester.widgetList<Text>(rotations()).last.data!;

    await tester.tap(find.text('回路'));
    await tester.pumpAndSettle();
    expect(rotationValue(), '0');

    // 转动棋盘中央的格子（电源）
    await tester.tap(find.byType(GridView));
    await tester.pumpAndSettle();
    expect(rotationValue(), '1');

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.textContaining('继续上一局'), findsOneWidget);
    expect(services.progress.has('circuit', 'easy'), isTrue);

    await tester.tap(find.text('回路'));
    await tester.pumpAndSettle();
    expect(rotationValue(), '1', reason: '应继续上一局');

    await tester.tap(find.byTooltip('重新开始'));
    await tester.pumpAndSettle();
    expect(rotationValue(), '0');

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.textContaining('继续上一局'), findsNothing);
    expect(services.progress.has('circuit', 'easy'), isFalse);

    await tester.tap(find.text('回路'));
    await tester.pumpAndSettle();
    expect(rotationValue(), '0', reason: '重新开始后不应再恢复旧局');
  });
}
