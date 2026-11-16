import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game/core/app_services.dart';
import 'package:game/core/data/models/score_kind.dart';
import 'package:game/core/storage/key_value_store.dart';
import 'package:game/games/game_definition.dart';
import 'package:game/ui/game/game_page.dart';
import 'package:game/ui/theme/app_theme.dart';

/// 用于测试外壳的假游戏：点「完成」立即通关；能从存档恢复出“已完成”状态。
class _FakeBoard extends StatefulWidget {
  const _FakeBoard({required this.session});

  final GameSession session;

  @override
  State<_FakeBoard> createState() => _FakeBoardState();
}

class _FakeBoardState extends State<_FakeBoard> {
  late bool done = widget.session.savedState?['done'] == true;

  void _finish() {
    setState(() => done = true);
    // 与真实游戏一致：先保存最终状态，再上报完成
    widget.session.saveProgress({'done': true});
    widget.session.onFinish(
      const GameFinish(won: true, score: 7, durationMs: 1000),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(done ? '已完成' : '进行中'),
      if (!done) TextButton(onPressed: _finish, child: const Text('完成')),
    ],
  );
}

final _fakeGame = GameDefinition(
  id: 'fake',
  title: '测试游戏',
  tagline: '',
  category: GameCategory.casual,
  color: AppColors.pink,
  scoreKind: ScoreKind.moves,
  modes: const [GameMode(id: 'only', label: '唯一', description: '测试模式')],
  rules: const ['无'],
  builder: (context, session) => _FakeBoard(session: session),
  coverBuilder: (_) => const SizedBox(),
);

void main() {
  late AppServices services;

  Future<void> enterGame(WidgetTester tester) async {
    // 先卸载再挂载，模拟“退出游戏页、再次进入”
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(home: GamePage(game: _fakeGame)),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async => services = await AppServices.fromStore(MemoryStore()));

  testWidgets('结算页无按钮，可收起回看；奖杯可再次打开', (tester) async {
    await enterGame(tester);
    expect(find.byTooltip('查看成绩'), findsNothing);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('挑战成功！'), findsOneWidget, reason: '通关后自动弹出结算页');
    expect(find.byType(ButtonStyleButton), findsNothing, reason: '结算页不含按钮');
    expect(find.text('再来一局'), findsNothing);

    // 点空白处收起，留在已完成的画面上
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('挑战成功！'), findsNothing);
    expect(find.text('已完成'), findsOneWidget);

    // 奖杯再次打开；下滑也能收起
    await tester.tap(find.byTooltip('查看成绩'));
    await tester.pumpAndSettle();
    expect(find.text('挑战成功！'), findsOneWidget);
    await tester.drag(find.text('挑战成功！'), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('挑战成功！'), findsNothing);
  });

  testWidgets('已完成的对局退出后再进入仍是完成画面；重新开始才开新局', (tester) async {
    await enterGame(tester);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await enterGame(tester);
    expect(find.text('已完成'), findsOneWidget, reason: '应恢复已完成的对局');
    expect(find.text('挑战成功！'), findsNothing, reason: '再次进入时不自动弹结算');
    expect(find.byTooltip('查看成绩'), findsOneWidget);
    expect(services.progress.hasUnfinished('fake', 'only'), isFalse);

    // 奖杯里仍能看到这局的成绩
    await tester.tap(find.byTooltip('查看成绩'));
    await tester.pumpAndSettle();
    expect(find.text('挑战成功！'), findsOneWidget);
    expect(find.text('7 步'), findsWidgets);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // 不会重复记一局
    expect(services.records.recordOf('fake', ScoreKind.moves).plays, 1);

    await tester.tap(find.byTooltip('重新开始'));
    await tester.pumpAndSettle();
    expect(find.text('进行中'), findsOneWidget);
    expect(find.byTooltip('查看成绩'), findsNothing);

    await enterGame(tester);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.byTooltip('查看成绩'), findsNothing);
  });

  final seedText = find.textContaining(RegExp(r'^#[0-9A-Z]{7}$'));

  Future<void> startWithSeed(WidgetTester tester, String input) async {
    await tester.tap(seedText);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), input);
    await tester.tap(find.text('用这个种子开始'));
    await tester.pumpAndSettle();
  }

  testWidgets('左上角显示种子和难度说明（不显示游戏名），点种子可复制', (tester) async {
    await enterGame(tester);
    expect(seedText, findsOneWidget);
    expect(find.text('测试模式'), findsOneWidget);
    expect(find.text(_fakeGame.title), findsNothing);
    final code = tester.widget<Text>(seedText).data!;

    await tester.tap(seedText);
    await tester.pumpAndSettle();
    expect(find.text('用这个种子开始'), findsOneWidget);
    expect(find.text(code), findsNWidgets(2), reason: '标题下和面板里各一处');
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(find.text('已复制'), findsOneWidget);
  });

  testWidgets('指定种子的对局不计入纪录；点刷新换回随机种子后正常计入', (tester) async {
    await enterGame(tester);
    await startWithSeed(tester, ' 1k7q-2xm ');
    expect(find.text('#1K7Q2XM'), findsOneWidget, reason: '输入会被规范化');

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('挑战成功！'), findsOneWidget);
    expect(find.text('指定种子，不计入纪录'), findsOneWidget);
    expect(find.text('★ 新纪录'), findsNothing);
    final record = services.records.recordOf('fake', ScoreKind.moves);
    expect(record.plays, 0);
    expect(record.mode('only').best, isNull);
    expect(services.outbox.length, 0, reason: '也不进入待同步队列');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // 退出再进来：仍是这局，奖杯里同样标明不计入
    await enterGame(tester);
    expect(find.text('#1K7Q2XM'), findsOneWidget);
    await tester.tap(find.byTooltip('查看成绩'));
    await tester.pumpAndSettle();
    expect(find.text('指定种子，不计入纪录'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重新开始'));
    await tester.pumpAndSettle();
    expect(find.text('#1K7Q2XM'), findsNothing, reason: '刷新后换成随机种子');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('指定种子，不计入纪录'), findsNothing);
    expect(services.records.recordOf('fake', ScoreKind.moves).plays, 1);
  });

  testWidgets('种子格式不对或版本不符时提示，不开新局', (tester) async {
    await enterGame(tester);
    await startWithSeed(tester, 'abc');
    expect(find.text('种子格式不对'), findsOneWidget);
    expect(find.text('用这个种子开始'), findsOneWidget, reason: '面板不关闭');

    await tester.enterText(find.byType(TextField), '2K7Q2XM');
    await tester.tap(find.text('用这个种子开始'));
    await tester.pumpAndSettle();
    expect(find.text('这个种子来自更新的版本，请先更新 app'), findsOneWidget);
  });
}
