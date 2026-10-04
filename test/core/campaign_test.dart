// The campaign as data and as rules: the level table is valid, every level and every master
// challenge is finished by the validation bot, and progress / rewards cannot be earned twice,
// skipped into or lost.
import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/core/bots.dart';
import 'package:novalith/core/campaign.dart';
import 'package:novalith/core/campaign_data.dart';
import 'package:novalith/core/game_core.dart';
import 'package:novalith/core/profile.dart';
import 'package:novalith/core/progression.dart';

/// A finished run of [l] with the given achievements, without simulating it.
GameCore runOf(
  LevelDef l, {
  int score = 0,
  int merges = 0,
  int maxLevel = 0,
  int chain = 0,
  int perfects = 0,
  int? drops,
  bool overflow = false,
  bool master = false,
}) {
  final c = l.createRun(master: master)
    ..score = score
    ..merges = merges
    ..maxLevel = maxLevel
    ..maxChain = chain
    ..perfects = perfects
    ..drops = drops ?? l.drops;
  if (overflow) {
    c.forceGameOver();
  } else if (l.byScore) {
    c
      ..over = true
      ..endReason = EndReason.dropsExhausted;
  } else {
    c.complete();
  }
  return c;
}

/// A run that earns exactly [stars] on [l] (0 = a failed attempt).
GameCore starRun(LevelDef l, int stars) {
  if (stars == 0) return runOf(l, overflow: true, drops: 3);
  int goal(GoalType t) => l.goals.where((g) => g.type == t).fold(0, (a, g) => g.target);
  final score = !l.byScore ? 10 : (stars == 3 ? l.star3 : (stars == 2 ? l.star2 : goal(GoalType.score)));
  final drops = l.byScore ? l.drops : (stars == 3 ? l.star3 : (stars == 2 ? l.star2 : l.drops));
  return runOf(
    l,
    score: score,
    merges: goal(GoalType.merges),
    maxLevel: goal(GoalType.evolve),
    chain: goal(GoalType.chain),
    perfects: goal(GoalType.perfects),
    drops: drops,
  );
}

var _run = 0;
RunOutcome play(Profile p, LevelDef l, int stars, {bool master = false}) => applyRun(
  p,
  master
      ? runOf(
          l,
          score: l.master.score,
          merges: 999,
          maxLevel: 12,
          chain: 12,
          perfects: 999,
          drops: l.master.drops,
          master: true,
        )
      : starRun(l, stars),
  runId: 'r${_run++}',
  level: l,
  master: master,
  now: DateTime(2026, 10, 5, 12),
)!;

void main() {
  final first = campaignLevels.first;

  group('level data', () {
    test('5 worlds of 20 levels, valid by the validator', () {
      expect(validateCampaign(campaignLevels), isEmpty);
      expect(campaignLevels.length, 100);
      for (final w in worlds) {
        expect(worldLevels(w.id).length, 20, reason: 'world ${w.id}');
        expect(worldLevels(w.id).last.trial, isTrue);
      }
    });

    test('the validator catches broken data', () {
      LevelDef make({
        int id = 101,
        List<Goal> goals = const [Goal(GoalType.merges, 3)],
        int drops = 12,
        int star2 = 7,
        int star3 = 6,
        int spawn = 0,
        bool trial = true,
        List<List<int>> start = const [],
        MasterDef master = const MasterDef(drops: 7, score: 0, seeds: [1]),
      }) => LevelDef(
        id: id,
        goals: goals,
        drops: drops,
        star2: star2,
        star3: star3,
        seeds: const [1],
        master: master,
        spawn: spawn,
        trial: trial,
        start: start,
      );
      bool bad(List<LevelDef> l, String what) => validateCampaign(l).any((m) => m.contains(what));
      // Only world 1 is present in these samples, so "no levels" for the others is expected.
      expect(validateCampaign([make()]).where((m) => !m.contains('no levels')), isEmpty);
      expect(bad([make(), make()], 'duplicate id'), isTrue);
      expect(bad([make(id: 901)], 'unknown world'), isTrue);
      expect(bad([make(goals: const [])], 'one or two goals'), isTrue);
      expect(
        bad([
          make(goals: const [Goal(GoalType.evolve, 13)]),
        ], 'invalid evolve'),
        isTrue,
      );
      expect(
        bad([
          make(goals: const [Goal(GoalType.merges, 30)]),
        ], 'invalid merges'),
        isTrue,
      );
      expect(bad([make(star2: 6, star3: 7)], 'drop stars must tighten'), isTrue);
      expect(bad([make(star2: 20)], 'drop stars must tighten'), isTrue);
      expect(
        bad([
          make(goals: const [Goal(GoalType.score, 500)], star2: 400, star3: 900),
        ], 'score stars must rise'),
        isTrue,
      );
      expect(bad([make(spawn: 99)], 'unknown spawn'), isTrue);
      expect(
        bad([
          make(
            start: const [
              [20, 100],
            ],
          ),
        ], 'bad starting body'),
        isTrue,
      );
      expect(
        bad([
          make(master: const MasterDef(drops: 12, score: 0, seeds: [1])),
        ], 'master drops'),
        isTrue,
      );
      expect(bad([make(trial: false)], 'trial must be the last'), isTrue);
      expect(bad([make(id: 102)], 'out of sequence'), isTrue);
    });

    test('no filler: neighbours differ, and every world brings its own conditions', () {
      String shape(LevelDef l) =>
          '${l.goals.map((g) => '${g.type.name}${g.type == GoalType.score ? '' : g.target}').join('+')}|${l.spawn}|${l.line}|${l.start}';
      for (var i = 1; i < campaignLevels.length; i++) {
        expect(shape(campaignLevels[i]), isNot(shape(campaignLevels[i - 1])), reason: 'level ${campaignLevels[i].id}');
      }
      for (final w in worlds) {
        final list = worldLevels(w.id);
        expect(list.map((l) => l.goals.first.type).toSet().length, greaterThanOrEqualTo(4), reason: 'world ${w.id}');
        expect(list.where((l) => l.goals.length == 2).length, greaterThanOrEqualTo(2), reason: 'world ${w.id} hybrids');
      }
      // New mechanics arrive world by world, never all at once.
      expect(worldLevels(1).every((l) => l.line == 0 && l.spawn <= 1), isTrue);
      expect(worldLevels(1).any((l) => l.goals.any((g) => g.type == GoalType.survive)), isFalse);
      expect(worldLevels(2).any((l) => l.goals.any((g) => g.type == GoalType.survive)), isTrue);
      expect(worldLevels(2).every((l) => l.line == 0), isTrue);
      expect(worldLevels(3).any((l) => l.line > 0), isTrue);
      expect(worldLevels(5).any((l) => l.goals.any((g) => g.type == GoalType.evolve && g.target == 12)), isTrue);
    });

    test('every level and master challenge is finished by the bot; three stars are reachable', () {
      const paces = [0.75, 1.0];
      for (final l in campaignLevels) {
        var best = 0;
        for (var k = 0; k < l.seeds.length; k++) {
          for (final pace in paces) {
            final core = playLevel(l, greedyBot, attempt: k, dropEvery: pace);
            final stars = l.stars(core);
            expect(stars, greaterThan(0), reason: 'level ${l.id} sequence $k at pace $pace is not passable');
            if (stars > best) best = stars;
          }
        }
        expect(best, 3, reason: 'level ${l.id}: three stars were never reached');
        for (var k = 0; k < l.master.seeds.length; k++) {
          for (final pace in paces) {
            final core = playLevel(l, greedyBot, attempt: k, master: true, dropEvery: pace);
            expect(l.passed(core, master: true), isTrue, reason: 'master ${l.id} sequence $k at pace $pace');
          }
        }
      }
    }, timeout: const Timeout(Duration(minutes: 20)));

    test('a level is the same game for the same attempt, and rotates sequences between attempts', () {
      final l = levelDef(105)!;
      final a = playLevel(l, greedyBot, attempt: 1);
      final b = playLevel(l, greedyBot, attempt: 1);
      expect([a.score, a.drops, a.merges], [b.score, b.drops, b.merges]);
      expect(l.createRun(attempt: 0).seed, isNot(l.createRun(attempt: 1).seed));
      expect(l.createRun(attempt: l.seeds.length).seed, l.createRun(attempt: 0).seed);
      expect(l.createRun(attempt: -3).seed, isIn(l.seeds), reason: 'a corrupted counter cannot crash');
    });

    test('start boards are placed without overlap and settle without ending the run', () {
      for (final l in campaignLevels.where((l) => l.start.isNotEmpty)) {
        final core = l.createRun();
        expect(core.bodies.length, l.start.length);
        for (var i = 0; i < 240; i++) {
          core.step();
        }
        expect(core.over, isFalse, reason: 'level ${l.id}');
        expect(core.score, 0, reason: 'level ${l.id}: the start board must not merge by itself');
      }
    });
  });

  group('stars and goals', () {
    test('score levels: stars by score, however the run ended', () {
      final l = campaignLevels.firstWhere(
        (l) => l.byScore && l.goals.length == 1 && l.goals.first.type == GoalType.score,
      );
      final target = l.goals.first.target;
      expect(l.stars(runOf(l, score: target - 1)), 0);
      expect(l.stars(runOf(l, score: target)), 1);
      expect(l.stars(runOf(l, score: l.star2)), 2);
      expect(l.stars(runOf(l, score: l.star3)), 3);
      expect(l.stars(runOf(l, score: l.star3, overflow: true)), 3, reason: 'overflowing after the target still counts');
    });

    test('goal levels: stars by drops used', () {
      final l = first;
      expect(l.byScore, isFalse);
      expect(l.stars(runOf(l, merges: 2)), 0);
      expect(l.stars(runOf(l, merges: 3, drops: l.drops)), 1);
      expect(l.stars(runOf(l, merges: 3, drops: l.star2)), 2);
      expect(l.stars(runOf(l, merges: 3, drops: l.star3)), 3);
    });

    test('survival needs the run to reach its last drop', () {
      final l = campaignLevels.firstWhere((l) => l.goals.length == 1 && l.goals.first.type == GoalType.survive);
      expect(l.stars(runOf(l, score: l.star3, overflow: true)), 0);
      expect(l.stars(runOf(l, score: 0)), 1);
      expect(l.stars(runOf(l, score: l.star3)), 3);
      expect(l.passed(runOf(l, score: l.master.score - 1, master: true), master: true), isFalse);
      expect(l.passed(runOf(l, score: l.master.score, master: true), master: true), isTrue);
    });

    test('hybrid levels need both goals', () {
      final l = campaignLevels.firstWhere((l) => l.goals.length == 2 && !l.byScore);
      final a = l.goals[0];
      final b = l.goals[1];
      GameCore half(Goal g) => l.createRun()
        ..merges = g.type == GoalType.merges ? g.target : 0
        ..maxChain = g.type == GoalType.chain ? g.target : 0
        ..maxLevel = g.type == GoalType.evolve ? g.target : 0
        ..perfects = g.type == GoalType.perfects ? g.target : 0;
      expect(l.passed(half(a)), isFalse);
      expect(l.passed(half(b)), isFalse);
      expect(l.stars(starRun(l, 1)), 1);
    });

    test('assist: three failures add drops, capped', () {
      final l = levelDef(111)!;
      expect(l.assistDrops(0), 0);
      expect(l.assistDrops(2), 0);
      expect(l.assistDrops(3), l.drops ~/ 10);
      expect(l.assistDrops(99), l.drops * 3 ~/ 10);
      expect(l.createRun(fails: 6).dropLimit, l.drops + l.drops * 2 ~/ 10);
      expect(l.createRun(fails: 6, master: true).dropLimit, l.master.drops, reason: 'no assist in master');
    });
  });

  group('progress and rewards', () {
    test('first clear pays once; replays pay only for new stars', () {
      final p = Profile();
      final a = play(p, first, 1);
      expect(a.passed, isTrue);
      expect(a.firstClear, isTrue);
      expect(a.campaignCoins, first.coins + first.starCoins);
      expect(p.starsOf(101), 1);
      final coins = p.coins;

      final b = play(p, first, 1);
      expect(b.firstClear, isFalse);
      expect(b.campaignCoins, 0, reason: 'the same result again is worth no campaign reward');
      expect(b.newStars, 0);
      expect(p.coins - coins, b.coins + b.levelCoins + b.achievementCoins);

      final c = play(p, first, 3);
      expect(c.newStars, 2);
      expect(c.campaignCoins, 2 * first.starCoins);
      final d = play(p, first, 2);
      expect(d.campaignCoins, 0);
      expect(p.starsOf(101), 3, reason: 'a weaker replay never lowers the stars');
    });

    test('the same run cannot be banked twice', () {
      final p = Profile();
      final core = starRun(first, 3);
      expect(applyRun(p, core, runId: 'same', level: first), isNotNull);
      final snapshot = p.encode();
      expect(applyRun(p, core, runId: 'same', level: first), isNull);
      expect(p.encode(), snapshot);
    });

    test('locked levels cannot be played into progress', () {
      final p = Profile();
      final far = levelDef(305)!;
      expect(levelUnlocked(p, far), isFalse);
      final out = play(p, far, 3);
      expect(out.passed, isFalse);
      expect(out.campaignCoins, 0);
      expect(p.starsOf(305), 0);
      expect(p.fails[305], isNull);
      expect(currentLevel(p)!.id, 101);
    });

    test('levels unlock one by one; a failed attempt unlocks nothing', () {
      final p = Profile();
      final second = campaignLevels[1];
      expect(levelUnlocked(p, first), isTrue);
      expect(levelUnlocked(p, second), isFalse);
      play(p, first, 0);
      expect(levelUnlocked(p, second), isFalse);
      expect(p.fails[101], 1);
      play(p, first, 1);
      expect(levelUnlocked(p, second), isTrue);
      expect(p.fails[101], isNull, reason: 'completing a level clears its failure count');
      expect(currentLevel(p)!.id, 102);
    });

    test('master: only after completion, paid once, no stars from it', () {
      final p = Profile();
      final early = play(p, first, 0, master: true);
      expect(early.masterNow, isFalse);
      expect(p.levels[101]?.master ?? false, isFalse);

      play(p, first, 1);
      final a = play(p, first, 0, master: true);
      expect(a.masterNow, isTrue);
      expect(a.campaignCoins, first.masterCoins);
      expect(p.starsOf(101), 1, reason: 'a master run does not change stars');
      final b = play(p, first, 0, master: true);
      expect(b.masterNow, isFalse);
      expect(b.campaignCoins, 0);
      expect(p.mastersDone, 1);
    });

    test('a world trial completes the world, hands over its backdrop and opens the next world', () {
      final p = Profile();
      for (final l in worldLevels(1)) {
        final out = play(p, l, 1);
        expect(out.worldDone, l.trial ? 1 : 0);
        if (l.trial) expect(out.unlockedItems.map((i) => i.id), contains('bg_origin'));
      }
      expect(worldCompleted(p, 1), isTrue);
      expect(worldsCompleted(p), 1);
      expect(p.owned, contains('bg_origin'));
      expect(p.achievements, containsAll(['world_1', 'camp_10']));
      expect(levelUnlocked(p, levelDef(201)!), isTrue);
      expect(play(p, worldLevels(1).last, 2).worldDone, 0, reason: 'celebrated once');
      expect(buyItem(p, 'bg_cradle'), BuyResult.locked, reason: 'world prizes cannot be bought');
    });

    test('the whole campaign can be completed; nothing is left to continue to', () {
      final p = Profile();
      for (final l in campaignLevels) {
        expect(levelUnlocked(p, l), isTrue, reason: 'level ${l.id}');
        play(p, l, 3);
        play(p, l, 0, master: true);
      }
      expect(currentLevel(p), isNull);
      expect(p.totalStars, 300);
      expect(p.mastersDone, 100);
      expect(worldsCompleted(p), 5);
      expect(p.achievements, containsAll(['camp_100', 'stars_300', 'master_100', 'world_5']));
      expect(p.owned, containsAll(['bg_origin', 'bg_cradle', 'bg_forge', 'bg_spiral', 'bg_horizon']));
      // With everything earned, the weekly goals still offer three reachable ones.
      final goals = weeklyGoals(p);
      expect(goals.length, weeklyGoalCount);
      expect(goals.any((g) => g.stat == WeekStat.stars || g.stat == WeekStat.masters), isFalse);
    });

    test('campaign runs leave the classic record and the unfinished classic run alone', () {
      final p = Profile()
        ..bestScore = 50
        ..activeRun = {'seed': 1};
      final l = campaignLevels.firstWhere((l) => l.byScore);
      for (final x in campaignLevels.takeWhile((x) => x.id != l.id)) {
        play(p, x, 1);
      }
      final out = play(p, l, 3);
      expect(out.record, isTrue);
      expect(p.levels[l.id]!.best, l.star3);
      expect(p.bestScore, 50);
      expect(p.activeRun, isNotNull);
    });
  });

  group('weekly goals and the monthly archive', () {
    final monday = DateTime(2026, 10, 5, 12);

    test('progress counts, a goal is paid once, a new week starts clean', () {
      final p = Profile();
      syncCalendar(p, monday);
      final week = p.weekKey;
      expect(weeklyGoals(p).length, weeklyGoalCount);
      expect(weeklyGoals(p).map((g) => g.id).toSet().length, weeklyGoalCount, reason: 'three different goals');
      for (final l in campaignLevels.take(10)) {
        play(p, l, 3);
      }
      expect(p.weekProgress['levels'], 10);
      expect(p.weekProgress['stars'], 30);
      final levels = weeklyPool.firstWhere((g) => g.stat == WeekStat.levels);
      if (weeklyGoals(p).contains(levels)) {
        final before = p.coins;
        expect(claimWeekly(p, 'levels'), levels.coins);
        expect(p.coins, before + levels.coins);
        expect(claimWeekly(p, 'levels'), 0);
        expect(p.weekliesClaimed, 1);
      }
      expect(claimWeekly(p, 'no_such_goal'), 0);

      syncCalendar(p, monday.add(const Duration(days: 6)));
      expect(p.weekKey, week, reason: 'Sunday is the same week');
      syncCalendar(p, monday.add(const Duration(days: 7)));
      expect(p.weekKey, week + 1);
      expect(p.weekProgress, isEmpty);
      expect(p.weekClaimed, isEmpty);
    });

    test('an unfinished goal cannot be claimed', () {
      final p = Profile();
      syncCalendar(p, monday);
      for (final g in weeklyGoals(p)) {
        expect(claimWeekly(p, g.id), 0);
      }
      expect(p.coins, 0);
    });

    test('setting the clock back neither resets nor re-pays', () {
      final p = Profile();
      syncCalendar(p, monday);
      final g = weeklyGoals(p).first;
      p.weekProgress[g.id] = g.target;
      expect(claimWeekly(p, g.id), g.coins);
      syncCalendar(p, monday.subtract(const Duration(days: 30)));
      expect(p.weekClaimed, contains(g.id));
      expect(claimWeekly(p, g.id), 0);
      expect(p.monthKey, 202610);
    });

    test('the archive fills from stars, masters, dailies and weekly goals; paid once a month', () {
      final p = Profile();
      syncCalendar(p, monday);
      expect(claimMonthly(p), 0);
      for (final l in campaignLevels.take(12)) {
        play(p, l, 3);
      }
      expect(p.monthPoints, 36 * pointsPerStar);
      play(p, first, 0, master: true);
      play(p, campaignLevels[1], 0, master: true);
      expect(p.monthPoints, 36 + 2 * pointsPerMaster);
      expect(p.monthPoints, greaterThanOrEqualTo(monthlyTarget));
      final before = p.coins;
      expect(claimMonthly(p), monthlyCoins);
      expect(p.coins, before + monthlyCoins);
      expect(p.owned, contains(monthlyTheme));
      expect(claimMonthly(p), 0);

      syncCalendar(p, DateTime(2026, 11, 1, 9));
      expect(p.monthPoints, 0);
      expect(p.monthClaimed, isFalse);
      expect(p.owned, contains(monthlyTheme), reason: 'the prize is kept');
    });
  });

  group('save', () {
    test('campaign progress survives a save and load', () {
      final p = Profile();
      syncCalendar(p, DateTime(2026, 10, 5, 12));
      for (final l in campaignLevels.take(5)) {
        play(p, l, 2);
      }
      play(p, first, 0, master: true);
      play(p, campaignLevels[5], 0);
      final r = Profile.decode(p.encode());
      expect(r.status, LoadStatus.ok);
      expect(r.profile.encode(), p.encode());
      expect(r.profile.levels[101]!.master, isTrue);
      expect(r.profile.fails[106], 1);
    });

    test('a damaged campaign section costs only itself', () {
      final p = Profile()..coins = 321;
      play(p, first, 3);
      final good = p.encode();
      for (final broken in [
        good.replaceFirst('"campaign":{', '"campaign":[],"x":{'),
        good.replaceFirst('"101":[3,', '"101":[9,'),
        good.replaceFirst('"101":[', '"abc":['),
        good.replaceFirst('"weekly":{', '"weekly":7,"y":{'),
      ]) {
        final r = Profile.decode(broken);
        expect(r.status, LoadStatus.recovered);
        expect(r.profile.coins, p.coins);
        expect(r.profile.runs, 1);
        expect(currentLevel(r.profile), isNotNull);
      }
    });

    test('a hand-edited save cannot hold a master mark without the level, or more than 3 stars', () {
      final r = Profile.decode('{"v":2,"campaign":{"levels":{"101":[0,0,0,0,1],"102":[7,0,0,0,0],"305":[3,9,9,9,1]}}}');
      expect(r.profile.levels[101]!.master, isFalse);
      expect(r.profile.starsOf(102), 0);
      // Stars on a level far ahead do not unlock what lies between.
      expect(currentLevel(r.profile)!.id, 101);
      expect(levelUnlocked(r.profile, levelDef(304)!), isFalse);
    });

    test('version 1 saves migrate: everything kept, players who had played get a gift', () {
      final played = Profile.decode('{"v":1,"coins":40,"bestScore":4000,"achievements":["a","b"],"stats":{"runs":9}}');
      expect(played.status, LoadStatus.ok);
      expect(played.profile.coins, 40);
      expect(played.profile.bestScore, 4000);
      expect(played.profile.gift, 50 + 20 + 10);
      expect(claimGift(played.profile), 80);
      expect(played.profile.coins, 120);
      expect(claimGift(played.profile), 0);

      final untouched = Profile.decode('{"v":1,"coins":0,"stats":{"runs":0}}');
      expect(untouched.profile.gift, 0);
      final rich = Profile.decode('{"v":1,"bestScore":9000000,"stats":{"runs":500}}');
      expect(rich.profile.gift, 600, reason: 'capped');
      // Saved again, it is a version 2 file and the gift is not granted a second time.
      final again = Profile.decode(played.profile.encode());
      expect(again.profile.gift, 0);
    });
  });
}
