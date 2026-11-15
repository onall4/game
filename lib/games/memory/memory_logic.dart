import 'dart:math';

class MemoryCard {
  MemoryCard(this.symbol);

  final int symbol;
  bool faceUp = false;
  bool matched = false;
}

enum FlipOutcome {
  /// 无效点击（已翻开 / 已配对 / 正在等待翻回）
  ignored,

  /// 翻开了本回合第一张
  first,

  /// 第二张与第一张配对成功
  match,

  /// 第二张不匹配，需要调用 [MemoryGame.hideMismatch] 翻回
  mismatch,
}

/// “翻翻乐”：记忆配对。
class MemoryGame {
  MemoryGame({required this.pairs, Random? random, List<int>? symbols})
    : cards = _deal(pairs, random ?? Random(), symbols);

  final int pairs;
  final List<MemoryCard> cards;

  int _moves = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int? _first;
  (int, int)? _pendingMismatch;

  /// 每翻两张计为一步
  int get moves => _moves;
  int get combo => _combo;
  int get bestCombo => _bestCombo;
  int get matchedPairs => cards.where((c) => c.matched).length ~/ 2;
  bool get completed => matchedPairs == pairs;
  bool get waiting => _pendingMismatch != null;

  FlipOutcome flip(int index) {
    final card = cards[index];
    if (waiting || card.faceUp || card.matched) return FlipOutcome.ignored;
    card.faceUp = true;

    final first = _first;
    if (first == null) {
      _first = index;
      return FlipOutcome.first;
    }

    _first = null;
    _moves++;
    final other = cards[first];
    if (other.symbol == card.symbol) {
      other.matched = card.matched = true;
      _combo++;
      _bestCombo = max(_bestCombo, _combo);
      return FlipOutcome.match;
    }
    _combo = 0;
    _pendingMismatch = (first, index);
    return FlipOutcome.mismatch;
  }

  void hideMismatch() {
    final pending = _pendingMismatch;
    if (pending == null) return;
    cards[pending.$1].faceUp = false;
    cards[pending.$2].faceUp = false;
    _pendingMismatch = null;
  }

  /// 星级：以“完美步数”（= 对数）为基准。
  int get stars {
    if (_moves <= (pairs * 1.6).ceil()) return 3;
    if (_moves <= pairs * 2.4) return 2;
    return 1;
  }

  static List<MemoryCard> _deal(int pairs, Random rng, List<int>? symbols) {
    final chosen =
        symbols ??
        (List.generate(
          _symbolPool,
          (i) => i,
        )..shuffle(rng)).take(pairs).toList();
    final deck = [
      for (final s in chosen) ...[MemoryCard(s), MemoryCard(s)],
    ];
    if (symbols == null) deck.shuffle(rng);
    return deck;
  }

  /// 可用图案数量，需与界面中的图标表保持一致。
  static const _symbolPool = 18;
  static int get symbolPool => _symbolPool;
}
