/// Seeded randomness and the fair piece spawner. No Flutter imports: everything here runs in
/// plain unit tests and produces the same sequence for the same seed on every device.
library;

import 'balance.dart';

/// Mulberry32. Hand-rolled (instead of dart:math Random) so the sequence is specified by this
/// file and can never change under us with an SDK upgrade - daily challenges depend on that.
class SeededRng {
  SeededRng(int seed) : _s = seed & 0xFFFFFFFF;

  int _s;

  int get state => _s;
  set state(int v) => _s = v & 0xFFFFFFFF;

  int nextU32() {
    _s = (_s + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _s;
    t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF;
    t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  /// Uniform in [0, 1).
  double nextDouble() => nextU32() / 4294967296.0;

  /// Uniform in [0, n).
  int nextInt(int n) => (nextDouble() * n).floor();
}

/// FNV-1a over a string, for turning "2026-10-04|v1" into a seed.
int hashSeed(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Hands out pieces. Weighted, but never cruel:
///  * the opening always contains a pair;
///  * no more than [Balance.maxSameInRow] identical pieces in a row;
///  * in danger (and only when [adaptive]) pieces that can merge with something on the board
///    become more likely.
class FairSpawner {
  FairSpawner({required this.balance, required int seed, this.adaptive = true}) : rng = SeededRng(seed) {
    current = _draw(const {}, false);
    next = _draw(const {}, false);
  }

  FairSpawner.restore({
    required this.balance,
    required this.adaptive,
    required int rngState,
    required this.current,
    required this.next,
    required int drawn,
    required int lastLevel,
    required int runLength,
    required bool openingPairDone,
  }) : rng = SeededRng(0) {
    rng.state = rngState;
    _drawn = drawn;
    _last = lastLevel;
    _run = runLength;
    _pairDone = openingPairDone;
  }

  final Balance balance;
  final SeededRng rng;

  /// Daily challenges switch this off: the same date must give everyone the same pieces.
  final bool adaptive;

  late int current;
  late int next;

  int _drawn = 0;
  int _last = 0;
  int _run = 0;
  bool _pairDone = false;
  final List<int> _opening = [];

  int get drawn => _drawn;
  int get lastLevel => _last;
  int get runLength => _run;
  bool get openingPairDone => _pairDone;

  /// Consumes the current piece and prepares the following one.
  /// [onBoard] = levels currently present, [danger] = the stack is close to the line.
  int take(Set<int> onBoard, bool danger) {
    final taken = current;
    current = next;
    next = _draw(onBoard, danger);
    return taken;
  }

  int _draw(Set<int> onBoard, bool danger) {
    final n = balance.spawnWeights.length;
    int level;

    // Early-game protection: if the opening is about to end without a pair, repeat a piece.
    final pairDeadline = balance.openingPairWithin - 1;
    if (!_pairDone && _drawn == pairDeadline && _opening.isNotEmpty) {
      level = _opening[rng.nextInt(_opening.length)];
    } else {
      var total = 0.0;
      final w = List<double>.filled(n, 0);
      for (var i = 0; i < n; i++) {
        final lv = i + 1;
        var wi = balance.spawnWeights[i].toDouble();
        if (lv == _last && _run >= balance.maxSameInRow) wi = 0;
        if (adaptive && danger && onBoard.contains(lv)) wi *= balance.recoveryBoost;
        w[i] = wi;
        total += wi;
      }
      var roll = rng.nextDouble() * total;
      level = n;
      for (var i = 0; i < n; i++) {
        roll -= w[i];
        if (roll < 0) {
          level = i + 1;
          break;
        }
      }
      // Guard against a zero-weight pick caused by floating point leftovers.
      if (w[level - 1] <= 0) {
        level = w.indexWhere((x) => x > 0) + 1;
      }
    }

    if (!_pairDone) {
      if (_opening.contains(level)) {
        _pairDone = true;
        _opening.clear();
      } else {
        _opening.add(level);
      }
    }
    if (level == _last) {
      _run++;
    } else {
      _last = level;
      _run = 1;
    }
    _drawn++;
    return level;
  }
}
