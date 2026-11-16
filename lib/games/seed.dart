import 'dart:math';

/// 一局游戏的种子：同一游戏、同一难度下，种子相同则开局完全相同。
///
/// 格式为 Crockford Base32（0–9 与去掉 I、L、O、U 的字母），
/// 1 位版本号 + 6 位随机码，如 `1K7Q2XM`。
/// 版本号 1–31 占 1 位；以 `0` 开头时，后面两位才是版本号（32–1023），留作扩展。
///
/// 版本号是各游戏自己的「开局生成规则」版本（见 `GameDefinition.seedVersion`），
/// 与 app 版本无关。
class GameSeed {
  const GameSeed(this.version, this.value)
    : assert(version >= 1 && version < 1024),
      assert(value >= 0 && value < valueRange);

  final int version;

  /// 随机码，0 ≤ value < [valueRange]。
  final int value;

  /// 随机码共 30 位（6 个 Base32 字符），约 10.7 亿种。
  static const valueRange = 1 << 30;
  static const _valueChars = 6;
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// 随机抽一个种子，用于正常开新局。
  factory GameSeed.random(int version, [Random? random]) =>
      GameSeed(version, (random ?? Random()).nextInt(valueRange));

  String get code {
    final buf = StringBuffer();
    if (version < 32) {
      buf.write(_alphabet[version]);
    } else {
      buf
        ..write('0')
        ..write(_alphabet[version >> 5])
        ..write(_alphabet[version & 31]);
    }
    for (var i = _valueChars - 1; i >= 0; i--) {
      buf.write(_alphabet[(value >> (5 * i)) & 31]);
    }
    return buf.toString();
  }

  /// 解析种子码（玩家输入或存档）；格式不对时返回 null。
  ///
  /// 忽略大小写、空格、横线和开头的 `#`；按 Crockford 习惯把 O 当 0、I/L 当 1。
  static GameSeed? tryParse(String input) {
    final s = input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-_#]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    final digits = [for (final ch in s.split('')) _alphabet.indexOf(ch)];
    if (digits.isEmpty || digits.contains(-1)) return null;

    final int version;
    final int start;
    if (digits[0] == 0) {
      if (digits.length != 3 + _valueChars) return null;
      version = digits[1] * 32 + digits[2];
      if (version < 32) return null; // 1–31 只有一位写法
      start = 3;
    } else {
      if (digits.length != 1 + _valueChars) return null;
      version = digits[0];
      start = 1;
    }
    var value = 0;
    for (final d in digits.skip(start)) {
      value = value * 32 + d;
    }
    return GameSeed(version, value);
  }

  @override
  bool operator ==(Object other) =>
      other is GameSeed && other.version == version && other.value == value;

  @override
  int get hashCode => Object.hash(version, value);

  @override
  String toString() => code;
}

/// 跨平台、跨版本结果一致的伪随机数生成器（mulberry32）。
///
/// 不用 `dart:math` 的 `Random(seed)`：官方不保证它在不同 SDK 版本之间一致，
/// 也没有承诺原生与 Web 一致。这里只用 32 位整数运算（乘法拆成 16 位），
/// Android、iOS、Web 上同一个种子得到同一串数。
///
/// **改动这里的算法会改变所有种子对应的开局，必须同时提升各游戏的种子版本。**
class SeededRandom implements Random {
  SeededRandom(int state) : _state = state & _mask;

  /// 由种子和难度 ID 混合出初始状态，让同一种子在不同难度下的开局互不相关
  /// （否则密码锁「入门」的答案会正好是「简单」答案的前几位）。
  factory SeededRandom.forGame(GameSeed seed, String modeId) =>
      SeededRandom.fromString('$modeId/${seed.code}');

  /// 用 FNV-1a 把字符串散列成初始状态。
  factory SeededRandom.fromString(String key) {
    var h = 0x811C9DC5;
    for (final c in key.codeUnits) {
      h = _imul(h ^ c, 0x01000193);
    }
    return SeededRandom(h);
  }

  static const _mask = 0xFFFFFFFF;
  static const _two32 = 4294967296; // 2^32，不用 1 << 32（Web 上会溢出成 1）
  int _state;

  /// 下一个 32 位无符号整数。
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _mask;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t = (t ^ ((t + _imul(t ^ (t >>> 7), t | 61)) & _mask)) & _mask;
    return (t ^ (t >>> 14)) & _mask;
  }

  @override
  int nextInt(int max) {
    if (max <= 0 || max > _two32) {
      throw RangeError.range(max, 1, _two32, 'max');
    }
    // 拒绝采样：去掉取模带来的偏差
    final limit = (_two32 ~/ max) * max;
    while (true) {
      final v = nextUint32();
      if (v < limit) return v % max;
    }
  }

  @override
  double nextDouble() {
    final hi = nextUint32() >>> 11; // 21 位
    final lo = nextUint32(); // 32 位
    return (hi * _two32 + lo) / 9007199254740992; // 除以 2^53
  }

  @override
  bool nextBool() => nextUint32() >>> 31 == 1;

  /// 32 位整数乘法（取低 32 位）。拆成 16 位相乘，Web 上也不会丢精度。
  static int _imul(int a, int b) {
    final aHi = (a >>> 16) & 0xFFFF, aLo = a & 0xFFFF;
    final bHi = (b >>> 16) & 0xFFFF, bLo = b & 0xFFFF;
    final cross = ((aHi * bLo + aLo * bHi) & 0xFFFF) << 16;
    return (aLo * bLo + cross) & _mask;
  }
}

/// Fisher–Yates 洗牌。
///
/// 不用 `List.shuffle`：它的具体步骤属于 SDK 内部实现，不保证各版本一致。
void shuffleWith<T>(List<T> list, Random random) {
  for (var i = list.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
}
