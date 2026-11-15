import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game/app.dart';
import 'package:game/core/app_services.dart';
import 'package:game/core/storage/key_value_store.dart';
import 'package:game/games/game_registry.dart';

void main() {
  Future<AppServices> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
  }
}
