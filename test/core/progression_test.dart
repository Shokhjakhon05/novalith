import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/core/ad_policy.dart';
import 'package:novalith/core/balance.dart';
import 'package:novalith/core/bots.dart';
import 'package:novalith/core/daily.dart';
import 'package:novalith/core/game_core.dart';
import 'package:novalith/core/profile.dart';
import 'package:novalith/core/progression.dart';
import 'package:novalith/core/rng.dart';

GameCore finishedRun({int score = 1000, int merges = 20, int maxLevel = 5, int chain = 2}) {
  final c = GameCore(seed: 1)
    ..score = score
    ..merges = merges
    ..maxLevel = maxLevel
    ..maxChain = chain;
  for (var l = 2; l <= maxLevel; l++) {
    c.createdLevels.add(l);
  }
  c.forceGameOver();
  return c;
}

void main() {
  const b = Balance.standard;

  group('run rewards', () {
    test('coins, xp and stats are applied', () {
      final p = Profile();
      final out = applyRun(p, finishedRun(score: 1000, merges: 20), runId: 'a')!;
      expect(out.coins, 1000 ~/ b.pointsPerCoin);
      expect(out.record, isTrue);
      expect(p.bestScore, 1000);
      expect(p.runs, 1);
      expect(p.totalMerges, 20);
      expect(out.xp, 20 * b.xpPerMerge + (1000 * b.xpPerScore).floor() + b.xpPerRun);
      expect(p.coins, out.totalCoins);
      expect(out.discoveries, [2, 3, 4, 5]);
    });

    test('rewards are granted exactly once per run id', () {
      final p = Profile();
      final run = finishedRun();
      expect(applyRun(p, run, runId: 'a'), isNotNull);
      final coins = p.coins;
      final runs = p.runs;
      for (var i = 0; i < 5; i++) {
        expect(applyRun(p, run, runId: 'a'), isNull);
      }
      expect(p.coins, coins);
      expect(p.runs, runs);
      expect(applyRun(p, run, runId: ''), isNull);
    });

    test('2x coins doubles only the run coins and only once', () {
      final p = Profile();
      final out = applyRun(p, finishedRun(score: 4000), runId: 'a')!;
      final before = p.coins;
      expect(doubleRunCoins(p, 'a'), out.coins);
      expect(p.coins, before + out.coins);
      for (var i = 0; i < 5; i++) {
        expect(doubleRunCoins(p, 'a'), 0);
      }
      expect(doubleRunCoins(p, 'other'), 0);
      expect(p.coins, before + out.coins);
    });

    test('record bonus is paid for beating a previous best, not on the first run', () {
      final p = Profile();
      final first = applyRun(p, finishedRun(score: 1000), runId: 'a')!;
      expect(first.coins, 1000 ~/ b.pointsPerCoin);
      final second = applyRun(p, finishedRun(score: 2000), runId: 'b')!;
      expect(second.record, isTrue);
      expect(second.coins, 2000 ~/ b.pointsPerCoin + b.recordBonusCoins);
      final third = applyRun(p, finishedRun(score: 500), runId: 'c')!;
      expect(third.record, isFalse);
      expect(p.bestScore, 2000);
    });

    test('achievements unlock once and pay once', () {
      final p = Profile();
      final out = applyRun(p, finishedRun(merges: 12, maxLevel: 6, chain: 2), runId: 'a')!;
      final ids = out.newAchievements.map((a) => a.id).toSet();
      expect(ids, containsAll(['first_merge', 'merges_10', 'first_chain', 'evo_6']));
      final again = applyRun(p, finishedRun(merges: 1), runId: 'b')!;
      expect(again.newAchievements.where((a) => ids.contains(a.id)), isEmpty);
    });

    test('achievement ids are unique and every stat is reachable', () {
      expect(achievements.map((a) => a.id).toSet().length, achievements.length);
      for (final a in achievements) {
        expect(a.target, greaterThan(0));
        expect(a.coins, greaterThan(0));
      }
    });

    test('xp levels up, pays level coins and unlocks level items', () {
      final p = Profile();
      final out = applyRun(p, finishedRun(score: 60000, merges: 400), runId: 'a')!;
      expect(out.levelsGained, greaterThan(2));
      expect(p.level, 1 + out.levelsGained);
      expect(out.levelCoins, out.levelsGained * b.levelUpCoins);
      expect(p.xp, lessThan(b.xpForLevel(p.level)));
      expect(p.owned, contains('bg_dawn'));
      expect(out.unlockedItems.map((i) => i.id), contains('bg_dawn'));
    });

    test('huge scores do not overflow or go negative', () {
      final p = Profile();
      final out = applyRun(p, finishedRun(score: 3000000000000), runId: 'a')!;
      expect(out.coins, greaterThan(0));
      expect(p.coins, greaterThan(0));
      expect(p.level, greaterThan(1));
    });
  });

  group('shop', () {
    test('buy needs coins, charges once, then the item can be equipped', () {
      final p = Profile()..coins = 399;
      expect(buyItem(p, 'theme_neon'), BuyResult.notEnoughCoins);
      expect(equipItem(p, 'theme_neon'), isFalse);
      p.coins = 450;
      expect(buyItem(p, 'theme_neon'), BuyResult.ok);
      expect(p.coins, 50);
      expect(buyItem(p, 'theme_neon'), BuyResult.alreadyOwned);
      expect(p.coins, 50);
      expect(equipItem(p, 'theme_neon'), isTrue);
      expect(p.theme, 'theme_neon');
      expect(p.background, 'bg_deep');
    });

    test('level-gated items cannot be bought, unknown ids are refused', () {
      final p = Profile()..coins = 999999;
      expect(buyItem(p, 'theme_crystal'), BuyResult.locked);
      expect(buyItem(p, 'nope'), BuyResult.unknown);
      expect(equipItem(p, 'nope'), isFalse);
      p.level = 6;
      expect(grantLevelItems(p).map((i) => i.id), containsAll(['theme_crystal', 'bg_dawn']));
      expect(grantLevelItems(p), isEmpty);
    });

    test('catalogue is sane: unique ids, defaults are free, prices positive', () {
      expect(shopItems.map((i) => i.id).toSet().length, shopItems.length);
      for (final i in shopItems) {
        if (i.id == 'theme_cosmos' || i.id == 'bg_deep' || i.reqLevel > 0) {
          expect(i.price, 0);
        } else {
          expect(i.price, greaterThan(0));
        }
      }
    });
  });

  group('daily challenge', () {
    test('same date gives the same challenge and the same pieces', () {
      final a = DailyChallenge.forDate(20261004);
      final c = DailyChallenge.forDate(20261004);
      expect([a.type, a.target, a.dropLimit, a.seed], [c.type, c.target, c.dropLimit, c.seed]);
      final ra = a.createRun();
      final rc = c.createRun();
      for (var i = 0; i < 10; i++) {
        expect(ra.currentPiece, rc.currentPiece);
        ra.drop(40.0 + i * 28);
        rc.drop(300.0 - i * 28);
        for (var s = 0; s < 70; s++) {
          ra.step();
          rc.step();
        }
      }
    });

    test('pieces do not depend on how the player plays (no adaptive weighting)', () {
      final d = DailyChallenge.forDate(20261101);
      final piecesA = <int>[];
      final piecesB = <int>[];
      final ra = d.createRun();
      final rb = d.createRun();
      for (var i = 0; i < d.dropLimit && !ra.over && !rb.over; i++) {
        piecesA.add(ra.currentPiece);
        piecesB.add(rb.currentPiece);
        ra.drop(170); // piles up in the middle -> danger
        rb.drop(30.0 + (i * 71) % 280);
        for (var s = 0; s < 60; s++) {
          ra.step();
          rb.step();
        }
      }
      final n = piecesA.length < piecesB.length ? piecesA.length : piecesB.length;
      expect(piecesA.take(n), piecesB.take(n));
    });

    test('a year of days: valid, varied, all three types appear', () {
      final types = <DailyType>{};
      final seeds = <int>{};
      for (var day = 0; day < 365; day++) {
        final date = DateTime(2026, 1, 1).add(Duration(days: day));
        final d = DailyChallenge.forDate(dateKeyOf(date));
        types.add(d.type);
        seeds.add(d.seed);
        expect(d.dropLimit, inInclusiveRange(40, 70));
        expect(d.target, greaterThan(0));
      }
      expect(types.length, 3);
      expect(seeds.length, greaterThan(360));
    });

    test('completion pays once per day; personal best is kept', () {
      final p = Profile();
      final d = DailyChallenge.forDate(20261004);
      final win = d.createRun()
        ..score = 999999
        ..maxLevel = 12
        ..maxChain = 9
        ..forceGameOver();
      final out = applyRun(p, win, runId: 'd1', daily: d)!;
      expect(out.dailyCompletedNow, isTrue);
      expect(out.dailyCoins, b.dailyCompleteCoins);
      expect(p.dailyDone, isTrue);
      expect(p.dailyBest, 999999);
      expect(p.bestScore, 0, reason: 'daily results never touch the classic record');
      final again = applyRun(p, win, runId: 'd2', daily: d)!;
      expect(again.dailyCompletedNow, isFalse);
      expect(again.dailyCoins, 0);
      expect(p.dailyCompleted, 1);
      // Next day starts clean.
      final d2 = DailyChallenge.forDate(20261005);
      final lose = d2.createRun()..forceGameOver();
      applyRun(p, lose, runId: 'd3', daily: d2);
      expect(p.dailyDone, isFalse);
      expect(p.dailyBest, 0);
    });

    test('targets are reachable: the greedy bot completes a fair share of days', () {
      var done = 0;
      const days = 40;
      for (var day = 0; day < days; day++) {
        final d = DailyChallenge.forDate(dateKeyOf(DateTime(2026, 3, 1).add(Duration(days: day))));
        final core = d.createRun();
        final rng = SeededRng(day);
        var next = 0.0;
        var steps = 0;
        while (!core.over && steps++ < 200000) {
          if (core.canDrop && core.time >= next) {
            core.drop(greedyBot(core, rng));
            next = core.time + 0.9;
          }
          core.step();
          core.events.clear();
        }
        if (d.completed(core)) done++;
      }
      // Not trivial, not impossible.
      expect(done, inInclusiveRange(days ~/ 8, days - 1), reason: 'completed $done of $days');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('daily reward', () {
    DateTime utc(int d, int h) => DateTime.utc(2026, 10, d, h);

    test('seven day cycle pays the table in order', () {
      final p = Profile();
      final paid = <int>[];
      for (var d = 1; d <= 8; d++) {
        paid.add(claimDailyReward(p, DateTime(2026, 10, d, 12), utc(d, 12)));
      }
      expect(paid, [...b.dailyRewardCoins, b.dailyRewardCoins[0]]);
      expect(p.rewardStreak, 8);
      expect(p.coins, paid.reduce((a, c) => a + c));
    });

    test('second claim on the same day gives nothing', () {
      final p = Profile();
      expect(claimDailyReward(p, DateTime(2026, 10, 1, 9), utc(1, 9)), b.dailyRewardCoins[0]);
      expect(claimDailyReward(p, DateTime(2026, 10, 1, 23), utc(1, 23)), 0);
      expect(dailyRewardStatus(p, DateTime(2026, 10, 1, 23), utc(1, 23)).state, RewardState.claimed);
    });

    test('moving the clock back gives nothing and keeps the streak', () {
      final p = Profile();
      claimDailyReward(p, DateTime(2026, 10, 5, 12), utc(5, 12));
      claimDailyReward(p, DateTime(2026, 10, 6, 12), utc(6, 12));
      expect(claimDailyReward(p, DateTime(2026, 10, 2, 12), utc(2, 12)), 0);
      expect(dailyRewardStatus(p, DateTime(2026, 10, 2, 12), utc(2, 12)).state, RewardState.clockBehind);
      expect(p.rewardStreak, 2);
      expect(p.rewardDay, 2);
      // Back to the real date: the streak simply continues.
      expect(claimDailyReward(p, DateTime(2026, 10, 7, 12), utc(7, 12)), b.dailyRewardCoins[2]);
    });

    test('moving the clock forward a day without real time passing gives nothing', () {
      final p = Profile();
      claimDailyReward(p, DateTime(2026, 10, 1, 23, 50), utc(1, 23));
      // Local date jumped to the 2nd, but only an hour of real time passed.
      expect(claimDailyReward(p, DateTime(2026, 10, 2, 0, 50), utc(2, 0)), 0);
    });

    test('a time zone change does not break an honest streak', () {
      final p = Profile();
      // Claim late on the 1st, fly east: 20 real hours later it is already the 3rd locally.
      claimDailyReward(p, DateTime(2026, 10, 1, 23, 30), utc(1, 18));
      final got = claimDailyReward(p, DateTime(2026, 10, 3, 5, 30), utc(2, 14));
      expect(got, b.dailyRewardCoins[1]);
      expect(p.rewardStreak, 2);
    });

    test('missing several days restarts the cycle', () {
      final p = Profile();
      claimDailyReward(p, DateTime(2026, 10, 1, 12), utc(1, 12));
      claimDailyReward(p, DateTime(2026, 10, 2, 12), utc(2, 12));
      expect(claimDailyReward(p, DateTime(2026, 10, 9, 12), utc(9, 12)), b.dailyRewardCoins[0]);
      expect(p.rewardStreak, 1);
      expect(p.rewardDay, 1);
    });

    test('date helpers', () {
      expect(dateKeyOf(DateTime(2026, 10, 4, 23, 59)), 20261004);
      expect(dayNumber(20260301) - dayNumber(20260228), 1);
      expect(dayNumber(20270101) - dayNumber(20261231), 1);
    });
  });

  group('ads policy', () {
    test('interstitial: every N runs, with cooldown, never right after a rewarded ad', () {
      final pacer = InterstitialPacer();
      bool ask({int runsSince = 3, int total = 10, double now = 1000, bool removeAds = false, bool tut = true}) => pacer
          .shouldShow(runsSince: runsSince, totalRuns: total, nowSec: now, removeAds: removeAds, tutorialDone: tut);

      expect(ask(), isTrue);
      expect(ask(runsSince: 2), isFalse);
      expect(ask(removeAds: true), isFalse);
      expect(ask(tut: false), isFalse, reason: 'never during onboarding');
      expect(ask(total: b.interstitialSkipFirstRuns), isFalse, reason: 'first runs are ad free');

      pacer.noteInterstitialShown(1000);
      expect(ask(now: 1000.0 + b.interstitialCooldownSec - 1), isFalse);
      expect(ask(now: 1000.0 + b.interstitialCooldownSec + 1), isTrue);

      pacer.noteRewardedShown(2000);
      expect(ask(now: 2001), isFalse);
      expect(ask(now: 2000.0 + b.interstitialAfterRewardedSec + 1), isTrue);
    });

    test('reward gate pays each token once', () {
      final gate = RewardGate();
      expect(gate.grant('continue:run1'), isTrue);
      expect(gate.grant('continue:run1'), isFalse);
      expect(gate.grant('double:run1'), isTrue);
      expect(gate.grant(''), isFalse);
    });
  });

  test('economy: first purchase is close, the full collection is far', () {
    // An average player sits between the two bots; simulate 400 runs of each.
    final p = Profile();
    var runs = 0;
    var firstPurchaseAt = 0;
    var repeatable = 0;
    final cheapest = shopItems.where((i) => i.price > 0).map((i) => i.price).reduce((a, c) => a < c ? a : c);
    final total = shopItems.fold<int>(0, (s, i) => s + i.price);
    for (var seed = 1; seed <= 24; seed++) {
      final bot = seed.isEven ? greedyBot : randomBot;
      final s = simulate(bot, seed);
      final core = GameCore(seed: seed)
        ..score = s.score
        ..merges = s.merges
        ..maxLevel = s.maxLevel
        ..maxChain = s.maxChain
        ..bonusCoins = s.bonusCoins
        ..forceGameOver();
      final out = applyRun(p, core, runId: 'r$seed')!;
      // One-off achievement coins are excluded from the long-run income estimate.
      repeatable += out.coins + out.levelCoins;
      runs++;
      if (firstPurchaseAt == 0 && p.coins >= cheapest) firstPurchaseAt = runs;
    }
    expect(firstPurchaseAt, inInclusiveRange(2, 8), reason: 'first purchase after $firstPurchaseAt runs');
    final perRun = repeatable / runs;
    // At ten runs a day plus the daily reward, the whole shop must take at least three weeks.
    final perDay = perRun * 10 + b.dailyRewardCoins.reduce((a, c) => a + c) / 7 + b.dailyCompleteCoins;
    expect(total / perDay, greaterThan(21), reason: 'coins/run $perRun, shop total $total');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
