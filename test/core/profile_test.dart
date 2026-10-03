import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/core/game_core.dart';
import 'package:novalith/core/profile.dart';

void main() {
  Profile sample() => Profile()
    ..coins = 1234
    ..xp = 55
    ..level = 7
    ..bestScore = 98765
    ..owned = {'theme_cosmos', 'bg_deep', 'theme_neon'}
    ..theme = 'theme_neon'
    ..achievements = {'merges_10'}
    ..discovered = {2, 3, 4}
    ..runs = 12
    ..totalMerges = 340
    ..maxChain = 4
    ..maxLevel = 9
    ..dailyDate = 20261004
    ..dailyBest = 2100
    ..dailyDone = true
    ..rewardDay = 3
    ..rewardStreak = 3
    ..rewardLastDate = 20261003
    ..rewardLastUtcMs = 1790000000000
    ..music = false
    ..language = 'uz'
    ..tutorialDone = true
    ..lastRewardedRun = 'r1'
    ..activeRun = (GameCore(seed: 3)..drop(100)).toJson();

  test('first launch: no file gives a fresh profile', () {
    expect(Profile.decode(null).status, LoadStatus.fresh);
    expect(Profile.decode('   ').status, LoadStatus.fresh);
    expect(Profile.decode(null).profile.coins, 0);
  });

  test('round trip keeps everything', () {
    final res = Profile.decode(sample().encode());
    expect(res.status, LoadStatus.ok);
    expect(jsonEncode(res.profile.toJson()), jsonEncode(sample().toJson()));
    expect(GameCore.fromJson(res.profile.activeRun), isNotNull);
  });

  test('garbage text recovers to defaults without throwing', () {
    for (final text in ['{', 'null', '[]', '42', '"str"', '{"v":', '\u0000\u0001', '{"v":"x"}']) {
      final res = Profile.decode(text);
      expect(res.profile.level, 1, reason: text);
      expect(res.profile.owned, containsAll(['theme_cosmos', 'bg_deep']));
    }
    expect(Profile.decode('{').status, LoadStatus.recovered);
  });

  test('one bad field costs only that field', () {
    final raw = sample().toJson();
    raw['coins'] = 'lots';
    raw['stats'] = 'broken';
    raw['settings'] = {'music': 'yes', 'language': 'uz'};
    final res = Profile.decode(jsonEncode(raw));
    expect(res.status, LoadStatus.recovered);
    expect(res.profile.coins, 0);
    expect(res.profile.runs, 0);
    expect(res.profile.music, isTrue);
    // Everything else survived.
    expect(res.profile.bestScore, 98765);
    expect(res.profile.level, 7);
    expect(res.profile.language, 'uz');
    expect(res.profile.theme, 'theme_neon');
  });

  test('negative, absurd and non-finite numbers are rejected', () {
    final raw = sample().toJson();
    raw['coins'] = -50;
    raw['level'] = 0;
    raw['xp'] = 1e300;
    final p = Profile.decode(jsonEncode(raw)).profile;
    expect(p.coins, 0);
    expect(p.level, 1);
    expect(p.xp, 0);
  });

  test('equipped item that is not owned falls back to the default', () {
    final raw = sample().toJson();
    raw['theme'] = 'theme_void';
    final res = Profile.decode(jsonEncode(raw));
    expect(res.profile.theme, 'theme_cosmos');
    expect(res.status, LoadStatus.recovered);
  });

  test('migrations run in order up to the current version', () {
    // A pretend history: v1 kept gold under "gold", v2 renamed it, v3 added a bonus.
    final migrations = <int, Migration>{
      1: (old) => {...old, 'coins': old['gold'], 'v': 2},
      2: (old) => {...old, 'coins': (old['coins'] as int) + 1, 'v': 3},
    };
    final res = Profile.decode('{"v":1,"gold":41,"level":4}', migrations: migrations, currentVersion: 3);
    expect(res.status, LoadStatus.ok);
    expect(res.profile.coins, 42);
    expect(res.profile.level, 4);

    final fromV2 = Profile.decode('{"v":2,"coins":10}', migrations: migrations, currentVersion: 3);
    expect(fromV2.profile.coins, 11);
  });

  test('a failing or missing migration still yields a usable profile', () {
    final throwing = <int, Migration>{1: (old) => throw StateError('boom')};
    final a = Profile.decode('{"v":1,"coins":7}', migrations: throwing, currentVersion: 2);
    expect(a.status, LoadStatus.recovered);
    expect(a.profile.coins, 7);
    final b = Profile.decode('{"v":1,"coins":7}', migrations: const {}, currentVersion: 5);
    expect(b.status, LoadStatus.recovered);
    expect(b.profile.coins, 7);
  });

  test('a save from a newer app version is read best effort', () {
    final res = Profile.decode('{"v":99,"coins":5,"futureField":[1,2,3]}');
    expect(res.profile.coins, 5);
  });

  test('fuzz: randomly mutated saves never throw', () {
    final rng = Random(1);
    final base = sample().encode();
    for (var i = 0; i < 3000; i++) {
      final chars = base.codeUnits.toList();
      final edits = 1 + rng.nextInt(6);
      for (var e = 0; e < edits; e++) {
        final at = rng.nextInt(chars.length);
        switch (rng.nextInt(3)) {
          case 0:
            chars[at] = 32 + rng.nextInt(90);
          case 1:
            chars.removeAt(at);
          default:
            chars.insert(at, 32 + rng.nextInt(90));
        }
      }
      final cut = rng.nextInt(8) == 0 ? rng.nextInt(chars.length) : chars.length;
      final res = Profile.decode(String.fromCharCodes(chars.take(cut)));
      final p = res.profile;
      expect(p.coins, greaterThanOrEqualTo(0));
      expect(p.level, greaterThanOrEqualTo(1));
      expect(p.owned.contains(p.theme), isTrue);
      // Whatever came out must itself be saveable and loadable.
      expect(Profile.decode(p.encode()).profile.coins, p.coins);
      // A damaged run snapshot must be refused, not crash.
      GameCore.fromJson(p.activeRun);
    }
  });
}
