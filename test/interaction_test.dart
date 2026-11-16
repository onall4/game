import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game/app.dart';
import 'package:game/core/app_services.dart';
import 'package:game/core/storage/key_value_store.dart';
import 'package:game/ui/widgets/chunky.dart';

Future<void> _openGame(WidgetTester tester, String title) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final services = await AppServices.fromStore(MemoryStore());
  await tester.pumpWidget(ShiquApp(services: services));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Finder _tiles() => find.descendant(
  of: find.byType(GridView),
  matching: find.byType(GestureDetector),
);

void main() {
  testWidgets('难度条可以滑动，选中屏幕外的 10×10', (tester) async {
    await _openGame(tester, '回路');
    expect(find.text('入门'), findsOneWidget);

    await tester.ensureVisible(find.text('10×10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10×10'));
    await tester.pumpAndSettle();
    expect(find.text('大师'), findsOneWidget);
    expect(_tiles(), findsNWidgets(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('回路提示：选一块格子，转正并锁定；每局 3 次', (tester) async {
    await _openGame(tester, '回路');
    expect(find.text('提示 3'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);

    for (var used = 1; used <= 3; used++) {
      await tester.tap(find.text('提示 ${4 - used}'));
      await tester.pumpAndSettle();
      expect(find.text('点一块格子，它会被转到正确方向并锁定'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(_tiles().at(used - 1));
      await tester.pumpAndSettle();
      if (find.text('挑战成功！').evaluate().isNotEmpty) return; // 极小概率提示后正好通关
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(used));
    }
    expect(find.text('提示 0'), findsOneWidget);
    expect(find.text('点击格子旋转导线'), findsOneWidget);

    // 被提示锁定的格子不能再转：旋转次数不变
    Finder rotations() => find.descendant(
      of: find.widgetWithText(StatPill, '旋转'),
      matching: find.byType(Text),
    );
    final before = tester.widgetList<Text>(rotations()).last.data;
    await tester.tap(_tiles().first);
    await tester.pumpAndSettle();
    expect(tester.widgetList<Text>(rotations()).last.data, before);
  });

  testWidgets('密码锁：点选格子决定填哪一位', (tester) async {
    await _openGame(tester, '密码锁'); // 默认入门：3 位、1–6、不重复
    Finder slotHas(int i, String d) => find.descendant(
      of: find.byKey(ValueKey('code-slot-$i')),
      matching: find.text(d),
    );
    Future<void> press(String d) async {
      await tester.tap(find.widgetWithText(Pressable, d));
      await tester.pumpAndSettle();
    }

    Future<void> select(int i) async {
      await tester.tap(find.byKey(ValueKey('code-slot-$i')));
      await tester.pumpAndSettle();
    }

    // 先填第 3 位，光标自动跳到第一个空位（第 1 位）
    await select(2);
    await press('5');
    expect(slotHas(2, '5'), findsOneWidget);
    await press('3');
    expect(slotHas(0, '3'), findsOneWidget);

    // 改第 3 位：直接替换
    await select(2);
    await press('4');
    expect(slotHas(2, '4'), findsOneWidget);
    expect(slotHas(2, '5'), findsNothing);

    // 光标现在在第 2 位；3 已用在第 1 位，不重复模式下按不进去
    await press('3');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('code-slot-1')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );

    // 删除：当前位为空时，删掉左边最近的数字
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pumpAndSettle();
    expect(slotHas(0, '3'), findsNothing);
    expect(slotHas(2, '4'), findsOneWidget);
  });
}
