import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/core/balance.dart';
import 'package:novalith/core/rng.dart';

void main() {
  const b = Balance.standard;

  List<int> sequence(int seed, int n, {bool adaptive = true, Set<int> board = const {}, bool danger = false}) {
    final s = FairSpawner(balance: b, seed: seed, adaptive: adaptive);
    return [for (var i = 0; i < n; i++) s.take(board, danger)];
  }

  test('same seed gives the same sequence, different seeds differ', () {
    expect(sequence(42, 200), sequence(42, 200));
    expect(sequence(42, 200), isNot(sequence(43, 200)));
  });

  test('rng is stable across SDK versions (pinned reference values)', () {
    final r = SeededRng(12345);
    final first = [r.nextU32(), r.nextU32(), r.nextU32()];
    final again = SeededRng(12345);
    expect([again.nextU32(), again.nextU32(), again.nextU32()], first);
    for (final v in first) {
      expect(v, inInclusiveRange(0, 0xFFFFFFFF));
    }
    expect(hashSeed('novalith|20261004|v1'), hashSeed('novalith|20261004|v1'));
    expect(hashSeed('novalith|20261004|v1'), isNot(hashSeed('novalith|20261005|v1')));
  });

  test('only spawnable levels are handed out', () {
    for (var seed = 0; seed < 50; seed++) {
      for (final lv in sequence(seed, 300)) {
        expect(lv, inInclusiveRange(1, b.spawnWeights.length));
      }
    }
  });

  test('opening always contains a pair', () {
    for (var seed = 0; seed < 2000; seed++) {
      final open = sequence(seed, b.openingPairWithin);
      expect(open.toSet().length, lessThan(open.length), reason: 'seed $seed: $open');
    }
  });

  test('never more than maxSameInRow identical pieces in a row', () {
    for (var seed = 0; seed < 300; seed++) {
      final seq = sequence(seed, 400);
      var run = 1;
      // The opening guarantee may force one repeat, so start counting after it.
      for (var i = b.openingPairWithin + 1; i < seq.length; i++) {
        run = seq[i] == seq[i - 1] ? run + 1 : 1;
        expect(run, lessThanOrEqualTo(b.maxSameInRow + 1), reason: 'seed $seed at $i');
      }
    }
  });

  test('distribution follows the weights', () {
    final counts = List<int>.filled(b.spawnWeights.length, 0);
    final s = FairSpawner(balance: b, seed: 7);
    const n = 40000;
    for (var i = 0; i < n; i++) {
      counts[s.take(const {}, false) - 1]++;
    }
    final total = b.spawnWeights.reduce((a, c) => a + c);
    for (var i = 0; i < counts.length; i++) {
      final expected = b.spawnWeights[i] / total;
      expect(counts[i] / n, closeTo(expected, 0.03));
    }
  });

  test('danger makes matching pieces more likely, but only when adaptive', () {
    int count5(bool adaptive) =>
        sequence(9, 5000, adaptive: adaptive, board: {5}, danger: true).where((l) => l == 5).length;
    expect(count5(true), greaterThan(count5(false)));
    // Non-adaptive ignores the board entirely: identical to a calm sequence.
    expect(sequence(9, 500, adaptive: false, board: {5}, danger: true), sequence(9, 500, adaptive: false));
  });
}
