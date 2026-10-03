// Stress and property tests: many automated games with invariants checked on every step.
// NOVALITH_GAMES controls the volume (CI runs 1000; the default keeps local runs quick).
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/core/balance.dart';
import 'package:novalith/core/bots.dart';
import 'package:novalith/core/game_core.dart';
import 'package:novalith/core/rng.dart';

final int games = int.tryParse(Platform.environment['NOVALITH_GAMES'] ?? '') ?? 40;

void checkInvariants(GameCore c, int lastScore, String where) {
  final b = c.balance;
  if (c.bodies.length > 150) fail('$where: runaway entity count ${c.bodies.length}');
  if (c.score < lastScore) fail('$where: score went down');
  if (!c.overflow.isFinite || !c.danger.isFinite) fail('$where: non-finite meters');
  for (final o in c.bodies) {
    if (!o.x.isFinite || !o.y.isFinite || !o.r.isFinite) fail('$where: NaN/inf body');
    if (o.x < o.r - 0.5 || o.x > b.worldW - o.r + 0.5) fail('$where: body escaped a wall (x=${o.x})');
    if (o.y > b.floorY - o.r + 0.5) fail('$where: body below the floor');
    if (o.level < 1 || o.level > b.maxLevel) fail('$where: impossible level ${o.level}');
    if (o.dead) fail('$where: dead body left on the board');
  }
}

void main() {
  const b = Balance.standard;

  test('$games random games: no hang, no NaN, no escape, rewards counted once', () {
    var totalDrops = 0;
    for (var seed = 1; seed <= games; seed++) {
      final c = GameCore(seed: seed);
      final rng = SeededRng(seed * 31);
      var next = 0.0;
      var steps = 0;
      var lastScore = 0;
      var mergeEvents = 0;
      var gameOvers = 0;
      while (!c.over) {
        if (c.canDrop && c.time >= next) {
          c.drop(rng.nextDouble() * b.worldW);
          next = c.time + 0.5 + rng.nextDouble() * 0.6;
        }
        c.step();
        steps++;
        for (final e in c.events) {
          if (e.type == EventType.merge || e.type == EventType.bigBang) mergeEvents++;
          if (e.type == EventType.gameOver) gameOvers++;
          if (e.points < 0) fail('negative points');
        }
        c.events.clear();
        checkInvariants(c, lastScore, 'seed $seed step $steps');
        lastScore = c.score;
        if (steps > 2000000) fail('seed $seed: game never ended');
      }
      expect(mergeEvents, c.merges, reason: 'every merge reported exactly once (seed $seed)');
      expect(gameOvers, 1);
      expect(c.drops, greaterThanOrEqualTo(15), reason: 'seed $seed ended absurdly early');
      totalDrops += c.drops;
    }
    printOnFailure('total drops $totalDrops');
  }, timeout: const Timeout(Duration(minutes: 40)));

  test('input spam: dropping on every step with hostile coordinates', () {
    final hostile = [double.nan, double.infinity, double.negativeInfinity, -1e12, 1e12, 0.0, 170.0];
    for (var seed = 1; seed <= 12; seed++) {
      final c = GameCore(seed: seed);
      final rng = Random(seed);
      var accepted = 0;
      var steps = 0;
      var last = 0;
      while (!c.over && steps < 400000) {
        if (c.drop(hostile[rng.nextInt(hostile.length)])) accepted++;
        c.step();
        steps++;
        c.events.clear();
        checkInvariants(c, last, 'spam seed $seed step $steps');
        last = c.score;
      }
      expect(c.over, isTrue);
      // The cooldown is the only thing pacing the drops.
      expect(accepted, lessThanOrEqualTo((c.time / b.dropCooldown).ceil() + 1));
    }
  });

  test('extreme chain: a board stuffed with overlapping twins settles', () {
    for (var seed = 1; seed <= 6; seed++) {
      final c = GameCore(seed: seed);
      final rng = Random(seed);
      for (var i = 0; i < 140; i++) {
        c.debugSpawn(1 + rng.nextInt(2), 20 + rng.nextDouble() * 300, 120 + rng.nextDouble() * 340);
      }
      var last = 0;
      for (var s = 0; s < 1500 && !c.over; s++) {
        c.step();
        c.events.clear();
        checkInvariants(c, last, 'chain seed $seed step $s');
        last = c.score;
      }
      expect(c.merges, greaterThan(40));
      expect(c.bodies.length, lessThan(140));
      expect(c.maxChain, greaterThan(5));
    }
  });

  test('thousands of merges: maximum evolution and repeated big bangs stay consistent', () {
    final c = GameCore(seed: 1);
    final top = b.maxLevel;
    var last = 0;
    for (var round = 0; round < 1500; round++) {
      final lv = 1 + round % top;
      final r = b.radius(lv);
      c.debugSpawn(lv, 120, b.floorY - r);
      c.debugSpawn(lv, 120 + r, b.floorY - r);
      for (var s = 0; s < 4; s++) {
        c.step();
      }
      c.events.clear();
      checkInvariants(c, last, 'round $round');
      last = c.score;
      if (round % 12 == 11) c.debugClear();
    }
    expect(c.merges, greaterThanOrEqualTo(1500));
    expect(c.bigBangs, greaterThan(100));
    expect(c.score, greaterThan(0));
  });

  test('randomised board states: any legal pile can be simulated', () {
    final rng = Random(99);
    for (var n = 0; n < 60; n++) {
      final c = GameCore(seed: n);
      final count = 5 + rng.nextInt(40);
      for (var i = 0; i < count; i++) {
        c.debugSpawn(1 + rng.nextInt(b.maxLevel), rng.nextDouble() * b.worldW, rng.nextDouble() * b.floorY);
      }
      var last = 0;
      for (var s = 0; s < 360 && !c.over; s++) {
        c.step();
        c.events.clear();
        // Bodies were thrown in at random, so allow them the first moments to be pushed inside.
        if (s > 30) checkInvariants(c, last, 'board $n step $s');
        last = c.score;
      }
    }
  });

  test('continue never leaves an impossible state', () {
    var continued = 0;
    for (var seed = 1; seed <= 25; seed++) {
      final c = GameCore(seed: seed);
      final rng = SeededRng(seed);
      var next = 0.0;
      var steps = 0;
      while (steps++ < 600000) {
        if (c.over) {
          if (!c.canContinue) break;
          expect(c.continueRun(), isTrue);
          continued++;
          for (final o in c.bodies) {
            expect(o.y - o.r, greaterThanOrEqualTo(b.dangerY + 69.9));
          }
          expect(c.canDrop || c.cooldown > 0, isTrue);
        }
        if (c.canDrop && c.time >= next) {
          c.drop(rng.nextDouble() * b.worldW);
          next = c.time + 0.7;
        }
        c.step();
        c.events.clear();
      }
      expect(c.over, isTrue);
      expect(c.continuesUsed, 1);
    }
    expect(continued, 25);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('bot results are identical on a re-run (whole-game determinism)', () {
    final a = simulate(greedyBot, 4242);
    final c = simulate(greedyBot, 4242);
    expect([a.score, a.drops, a.merges, a.steps], [c.score, c.drops, c.merges, c.steps]);
  });
}
