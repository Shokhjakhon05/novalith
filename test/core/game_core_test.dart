import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/core/balance.dart';
import 'package:novalith/core/game_core.dart';

void run(GameCore c, double seconds) {
  final steps = (seconds / c.balance.stepDt).round();
  for (var i = 0; i < steps; i++) {
    c.step();
  }
}

void main() {
  const b = Balance.standard;
  final floor1 = b.floorY - b.radius(1);

  test('A + A -> B exactly once: one body, one score, one event', () {
    final c = GameCore(seed: 1);
    c.debugSpawn(1, 100, floor1);
    c.debugSpawn(1, 100 + b.radius(1) * 2 - 1, floor1);
    run(c, 1);
    expect(c.bodies.length, 1);
    expect(c.bodies.single.level, 2);
    expect(c.merges, 1);
    expect(c.score, b.mergeScore(2));
    expect(c.events.where((e) => e.type == EventType.merge).length, 1);
    expect(c.bodies.single.r, closeTo(b.radius(2), 1e-9));
  });

  test('three touching twins merge only one pair', () {
    final c = GameCore(seed: 1);
    final d = b.radius(1) * 2 - 1;
    c.debugSpawn(1, 100, floor1);
    c.debugSpawn(1, 100 + d, floor1);
    c.debugSpawn(1, 100 + 2 * d, floor1);
    run(c, 1.5);
    expect(c.merges, 1);
    expect(c.bodies.map((o) => o.level).toList()..sort(), [1, 2]);
    expect(c.score, b.mergeScore(2));
  });

  test('chain reaction multiplies the score', () {
    final c = GameCore(seed: 1);
    final r1 = b.radius(1);
    c.debugSpawn(1, 60, floor1);
    c.debugSpawn(1, 60 + r1 * 2 - 1, floor1);
    // A level-2 body falling onto the spot where the merged level-2 appears.
    c.debugSpawn(2, 60 + r1 - 0.5, floor1 - 75);
    run(c, 1);
    expect(c.merges, 2);
    expect(c.maxChain, 2);
    expect(c.bodies.single.level, 3);
    expect(c.score, b.mergeScore(2) * b.comboMultiplier(1) + b.mergeScore(3) * b.comboMultiplier(2));
  });

  test('chain expires after the combo window', () {
    final c = GameCore(seed: 1);
    c.debugSpawn(1, 100, floor1);
    c.debugSpawn(1, 100 + b.radius(1) * 2 - 1, floor1);
    run(c, 0.2);
    expect(c.chain, 1);
    run(c, b.comboWindow + 0.2);
    expect(c.chain, 0);
  });

  test('two top-level bodies cause the big bang and vanish', () {
    final c = GameCore(seed: 1);
    final top = b.maxLevel;
    final r = b.radius(top);
    c.debugSpawn(top, 110, b.floorY - r);
    c.debugSpawn(top, 230, b.floorY - r);
    c.debugSpawn(3, 170, 150);
    run(c, 0.1);
    expect(c.bigBangs, 1);
    expect(c.bodies.where((o) => o.level == top), isEmpty);
    expect(c.score, b.bigBangScore);
    expect(c.bonusCoins, b.bigBangCoins);
    expect(c.events.where((e) => e.type == EventType.bigBang).length, 1);
    run(c, 3);
    for (final o in c.bodies) {
      expect(o.x.isFinite && o.y.isFinite, isTrue);
      expect(o.x, inInclusiveRange(o.r - 0.01, b.worldW - o.r + 0.01));
    }
  });

  test('drop respects the cooldown and clamps the aim inside the walls', () {
    final c = GameCore(seed: 3);
    expect(c.drop(-500), isTrue);
    expect(c.bodies.single.x, c.bodies.single.r);
    expect(c.drop(100), isFalse, reason: 'cooldown');
    run(c, b.dropCooldown + 0.02);
    expect(c.drop(double.nan), isTrue);
    expect(c.bodies.last.x.isFinite, isTrue);
    run(c, b.dropCooldown + 0.02);
    expect(c.drop(1e9), isTrue);
    final last = c.bodies.reduce((a, o) => a.id > o.id ? a : o);
    expect(last.x, closeTo(b.worldW - last.r, 1e-9));
    expect(c.drops, 3);
  });

  test('dropped piece is the previewed piece and the preview advances', () {
    final c = GameCore(seed: 5);
    final cur = c.currentPiece;
    final nxt = c.nextPiece;
    c.drop(100);
    expect(c.bodies.single.level, cur);
    expect(c.currentPiece, nxt);
  });

  test('perfect drop: landing straight on a twin is rewarded', () {
    final c = GameCore(seed: 5);
    final lv = c.currentPiece;
    c.debugSpawn(lv, 170, b.floorY - b.radius(lv));
    c.drop(170);
    run(c, 2);
    expect(c.perfects, 1);
    final base = b.mergeScore(lv + 1);
    expect(c.score, base + (base * b.perfectBonusFactor).round());
  });

  test('safe spawn never creates a piece inside another one', () {
    final c = GameCore(seed: 5);
    c.debugSpawn(9, 170, b.spawnY);
    c.drop(170);
    final piece = c.bodies.last;
    final big = c.bodies.first;
    final dx = piece.x - big.x;
    final dy = piece.y - big.y;
    expect(dx * dx + dy * dy, greaterThanOrEqualTo((piece.r + big.r) * (piece.r + big.r) - 1e-6));
  });

  group('game over', () {
    // A shallow container: one resting piece already pokes above the line.
    const shallow = Balance(floorY: 100, dangerY: 84);

    test('resting above the line for overflowTime ends the run, not sooner', () {
      final c = GameCore(balance: shallow, seed: 1);
      c.debugSpawn(4, 170, 100 - shallow.radius(4));
      run(c, shallow.dropGrace + shallow.overflowTime - 0.2);
      expect(c.over, isFalse);
      expect(c.overflow, greaterThan(0.5));
      run(c, 0.4);
      expect(c.over, isTrue);
      expect(c.endReason, EndReason.overflow);
      expect(c.events.where((e) => e.type == EventType.gameOver).length, 1);
    });

    test('after game over nothing moves and drops are refused', () {
      final c = GameCore(balance: shallow, seed: 1);
      c.debugSpawn(4, 170, 100 - shallow.radius(4));
      run(c, 4);
      final t = c.time;
      final score = c.score;
      run(c, 2);
      expect(c.time, t);
      expect(c.drop(100), isFalse);
      expect(c.score, score);
    });

    test('continue works once, clears the danger zone and gives a grace window', () {
      final c = GameCore(balance: shallow, seed: 1);
      c.debugSpawn(4, 170, 100 - shallow.radius(4));
      c.debugSpawn(1, 40, 100 - shallow.radius(1));
      run(c, 4);
      expect(c.canContinue, isTrue);
      expect(c.continueRun(), isTrue);
      expect(c.over, isFalse);
      expect(c.bodies, isEmpty);
      expect(c.continueRun(), isFalse, reason: 'not over');
      c.forceGameOver();
      expect(c.canContinue, isFalse, reason: 'one continue per run');
      expect(c.continueRun(), isFalse);
    });

    test('a falling piece passing the line does not start the countdown', () {
      final c = GameCore(seed: 2);
      c.drop(170);
      run(c, 1.5);
      expect(c.over, isFalse);
      expect(c.overflow, 0);
    });
  });

  test('drop limit ends the run once the board settles', () {
    final c = GameCore(seed: 4, dropLimit: 3, adaptiveSpawns: false);
    var x = 40.0;
    for (var i = 0; i < 3000 && !c.over; i++) {
      if (c.canDrop) {
        c.drop(x);
        x += 120;
      }
      c.step();
    }
    expect(c.over, isTrue);
    expect(c.endReason, EndReason.dropsExhausted);
    expect(c.drops, 3);
    expect(c.canContinue, isFalse);
  });

  test('determinism: same seed and inputs give a bit-identical run', () {
    String play() {
      final c = GameCore(seed: 777);
      var i = 0;
      for (var s = 0; s < 6000 && !c.over; s++) {
        if (c.canDrop && s % 100 == 0) c.drop(30.0 + (i++ * 53) % 280);
        c.step();
      }
      return jsonEncode(c.toJson());
    }

    expect(play(), play());
  });

  test('snapshot round trip keeps the run', () {
    final c = GameCore(seed: 31);
    for (var s = 0; s < 2400; s++) {
      if (c.canDrop && s % 110 == 0) c.drop(40.0 + (s * 7) % 260);
      c.step();
    }
    final json = jsonDecode(jsonEncode(c.toJson()));
    final r = GameCore.fromJson(json)!;
    expect(r.score, c.score);
    expect(r.drops, c.drops);
    expect(r.bodies.length, c.bodies.length);
    expect(r.currentPiece, c.currentPiece);
    expect(r.nextPiece, c.nextPiece);
    // The restored spawner continues the very same sequence.
    run(c, 1);
    run(r, 1);
    c.drop(100);
    r.drop(100);
    expect(r.nextPiece, c.nextPiece);
    expect(r.currentPiece, c.currentPiece);
  });

  test('broken snapshots are rejected, never thrown on', () {
    final good = GameCore(seed: 1)..drop(100);
    final j = good.toJson();
    expect(GameCore.fromJson(null), isNull);
    expect(GameCore.fromJson('nope'), isNull);
    expect(GameCore.fromJson(<String, dynamic>{}), isNull);
    expect(GameCore.fromJson({...j, 'cur': 99}), isNull);
    expect(GameCore.fromJson({...j, 'score': -5}), isNull);
    expect(GameCore.fromJson({...j, 'bodies': 'x'}), isNull);
    expect(
        GameCore.fromJson({
          ...j,
          'bodies': [
            [1, 500, 1.0, 1.0, 1.0, 0.0]
          ]
        }),
        isNull);
    expect(GameCore.fromJson(jsonDecode(jsonEncode(j))), isNotNull);
  });

  test('advance() caps the work per frame and ignores bad frame times', () {
    final c = GameCore(seed: 1);
    c.advance(double.nan);
    c.advance(-1);
    expect(c.time, 0);
    c.advance(10);
    expect(c.time, closeTo(b.stepDt * b.maxStepsPerFrame, 1e-9));
  });

  test('score formula and combo table come from the balance', () {
    expect(b.mergeScore(2), 4);
    expect(b.mergeScore(12), 364);
    expect(b.comboMultiplier(0), 1);
    expect(b.comboMultiplier(1), 1);
    expect(b.comboMultiplier(4), 5);
    expect(b.comboMultiplier(99), b.comboMultipliers.last);
  });

  test('a 13th level only needs a new balance entry', () {
    final extended = Balance(levels: [
      ...Balance.defaultLevels,
      const EvoLevel(id: 13, key: 'universe', radius: 104, coins: 30, rarity: 3),
    ]);
    final c = GameCore(balance: extended, seed: 1);
    final r = extended.radius(12);
    c.debugSpawn(12, 110, extended.floorY - r);
    c.debugSpawn(12, 230, extended.floorY - r);
    run(c, 0.5);
    expect(c.bigBangs, 0);
    expect(c.bodies.single.level, 13);
  });
}
