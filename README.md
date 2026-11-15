# 拾趣 · 小游戏合集

基于 Flutter 的移动端小游戏合集，同时支持 iOS 与 Android（附带 Web 预览）。
目前收录 3 款游戏，数据保存在本地，并已为后续接入服务器预留接口。

| 游戏 | 类型 | 玩法 | 成绩指标 |
| --- | --- | --- | --- |
| 回路 | 益智 | 旋转导线，让电路全部通电（随机生成，必有解） | 用时 |
| 密码锁 | 解密 | 根据“位置对 / 数字对”线索推理密码 | 尝试次数 |
| 翻翻乐 | 休闲 | 记忆翻牌，找出所有配对 | 步数 |

每款游戏有 3 个难度，支持规则说明、计时、最佳纪录、新纪录提示与触感反馈。

## 运行

```bash
flutter pub get
flutter run                 # 连接手机或模拟器
flutter test                # 单元测试 + 组件测试
```

Web 预览（绑定 127.0.0.1）：

```bash
flutter build web --no-web-resources-cdn
python -m http.server 8600 --bind 127.0.0.1 --directory build/web
```

> 如果本机设置了 `HTTP_PROXY`，`flutter test` 可能因为本地回环请求被代理而失败，
> 运行前设置 `NO_PROXY=127.0.0.1,localhost` 即可。

## 更新到 Android 手机（保留存档）

用 `flutter run --release`，或把 `build/app/outputs/flutter-apk/app-release.apk` 发到手机上点开安装，都是覆盖更新、存档保留。
不要用 `flutter install`：它会先卸载旧版本，存档会被清空。

## 目录结构

```
lib/
├── main.dart / app.dart          启动、主题、依赖注入（AppScope）
├── core/
│   ├── app_services.dart         依赖容器：存储、仓库、同步、触感
│   ├── storage/                  KeyValueStore 抽象 + shared_preferences 实现 + 数据迁移
│   └── data/
│       ├── models/               PlayerProfile / GameResult / GameRecord / ScoreKind
│       ├── repositories/         记录、玩家、设置仓库（接口 + 本地实现）
│       └── sync/                 待同步队列(outbox)、RemoteGameApi 接口、SyncService
├── games/
│   ├── game_definition.dart      游戏元数据、模式、结算数据
│   ├── game_registry.dart        游戏注册表（首页按此展示）
│   ├── game_clock.dart           计时器（切后台自动暂停）
│   └── circuit/ codebreaker/ memory/   每个游戏：*_logic.dart（纯逻辑）+ *_page.dart（界面）
└── ui/                           首页、游戏外壳、结算页、设置页、主题与通用组件
```

## 新增一个小游戏

1. 在 `lib/games/<name>/` 下编写纯 Dart 逻辑（便于测试）和界面组件；
   界面在一局结束时调用 `session.onFinish(GameFinish(...))`。
2. 在 `lib/games/game_registry.dart` 中追加一个 `GameDefinition`（id、标题、分类、配色、模式、规则、封面）。

外壳会自动处理：难度切换、规则弹窗、重开、成绩记录、结算页和首页统计。

## 接入服务器（预留）

数据流：`游戏结束 → GameResult → 本地 GameRecord（标记 dirty）+ 写入 outbox → SyncService`

- 现在使用 `OfflineSyncService`（不发任何请求）。
- 接入后端时：
  1. 实现 `RemoteGameApi`（`lib/core/data/sync/remote_game_api.dart`，内附建议的 REST 接口）；
  2. 在 `AppServices.fromStore` 中把 `OfflineSyncService` 换成 `RemoteSyncService(api: ...)`。
- `RemoteSyncService` 已实现“先推后拉”：注册匿名玩家 → 上传 outbox（按 `GameResult.id` 幂等）
  → 上传脏记录 → 拉取并合并（计数取大、最佳取优），并有对应测试。
- 玩家首次启动即生成本地 `playerId`，可作为匿名账号，登录后通过 `remoteUserId` 绑定。
- 本地数据结构变更时，在 `StorageMigrator` 中递增版本并添加迁移函数。
