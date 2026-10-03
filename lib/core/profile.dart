/// The player's saved data and its (de)serialisation. Loading is defensive field by field: one
/// broken value costs the player that one value, never the whole save and never a crash.
library;

import 'dart:convert';

enum LoadStatus {
  /// No save yet (first launch).
  fresh,
  ok,

  /// Something was invalid; what could be kept was kept, the rest reset to defaults.
  recovered,
}

class LoadResult {
  LoadResult(this.profile, this.status);
  final Profile profile;
  final LoadStatus status;
}

/// Upgrades a raw save from version N to N+1.
typedef Migration = Map<String, dynamic> Function(Map<String, dynamic> old);

class Profile {
  /// Bump when the layout changes and add the matching entry to [migrations].
  static const int currentVersion = 1;

  /// version N -> function producing version N+1. Empty today: version 1 is the first layout.
  static const Map<int, Migration> migrations = {};

  int coins = 0;
  int xp = 0;
  int level = 1;
  int bestScore = 0;

  Set<String> owned = {'theme_cosmos', 'bg_deep'};
  String theme = 'theme_cosmos';
  String background = 'bg_deep';

  Set<String> achievements = {};

  /// Evolution levels the player has ever created (the collection).
  Set<int> discovered = {};

  // Lifetime statistics (achievements read these).
  int runs = 0;
  int totalMerges = 0;
  int totalScore = 0;
  int maxChain = 0;
  int maxLevel = 0;
  int bigBangs = 0;
  int perfects = 0;
  int dailyCompleted = 0;

  // Daily challenge.
  int dailyDate = 0;
  int dailyBest = 0;
  bool dailyDone = false;

  // Daily reward.
  int rewardDay = 0;
  int rewardStreak = 0;
  int rewardLastDate = 0;
  int rewardLastUtcMs = 0;

  // Settings.
  bool music = true;
  bool sfx = true;
  bool haptics = true;
  bool showNumbers = false;

  /// Empty = follow the device language.
  String language = '';

  bool tutorialDone = false;
  bool removeAds = false;

  // Reward idempotency: the id of the last run whose rewards / doubling were applied.
  String lastRewardedRun = '';
  String lastDoubledRun = '';
  int lastRunCoins = 0;

  int runsSinceInterstitial = 0;

  /// Snapshot of an unfinished classic run (see GameCore.toJson), or null.
  Map<String, dynamic>? activeRun;

  Map<String, dynamic> toJson() => {
    'v': currentVersion,
    'coins': coins,
    'xp': xp,
    'level': level,
    'bestScore': bestScore,
    'owned': owned.toList(),
    'theme': theme,
    'background': background,
    'achievements': achievements.toList(),
    'discovered': discovered.toList(),
    'stats': {
      'runs': runs,
      'totalMerges': totalMerges,
      'totalScore': totalScore,
      'maxChain': maxChain,
      'maxLevel': maxLevel,
      'bigBangs': bigBangs,
      'perfects': perfects,
      'dailyCompleted': dailyCompleted,
    },
    'daily': {'date': dailyDate, 'best': dailyBest, 'done': dailyDone},
    'reward': {'day': rewardDay, 'streak': rewardStreak, 'lastDate': rewardLastDate, 'lastUtcMs': rewardLastUtcMs},
    'settings': {'music': music, 'sfx': sfx, 'haptics': haptics, 'showNumbers': showNumbers, 'language': language},
    'tutorialDone': tutorialDone,
    'removeAds': removeAds,
    'lastRewardedRun': lastRewardedRun,
    'lastDoubledRun': lastDoubledRun,
    'lastRunCoins': lastRunCoins,
    'runsSinceInterstitial': runsSinceInterstitial,
    'activeRun': activeRun,
  };

  String encode() => jsonEncode(toJson());

  /// Parses a save file. Never throws.
  static LoadResult decode(
    String? text, {
    Map<int, Migration> migrations = Profile.migrations,
    int currentVersion = Profile.currentVersion,
  }) {
    if (text == null || text.trim().isEmpty) return LoadResult(Profile(), LoadStatus.fresh);
    Map<String, dynamic> raw;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return LoadResult(Profile(), LoadStatus.recovered);
      raw = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return LoadResult(Profile(), LoadStatus.recovered);
    }

    var damaged = false;
    var version = raw['v'] is int ? raw['v'] as int : 1;
    if (version < 1) {
      version = 1;
      damaged = true;
    }
    // Walk the migration chain. A save from a newer app version is read as-is, best effort.
    while (version < currentVersion) {
      final step = migrations[version];
      if (step == null) {
        damaged = true;
        break;
      }
      try {
        raw = step(raw);
      } catch (_) {
        damaged = true;
        break;
      }
      version++;
    }

    final p = Profile();
    final r = _Reader(raw);
    p.coins = r.integer('coins', 0, max: 2000000000);
    p.xp = r.integer('xp', 0, max: 2000000000);
    p.level = r.integer('level', 1, min: 1, max: 100000);
    p.bestScore = r.integer('bestScore', 0, max: 4000000000000);
    p.owned = r.strings('owned')..addAll(const ['theme_cosmos', 'bg_deep']);
    p.theme = r.string('theme', 'theme_cosmos');
    p.background = r.string('background', 'bg_deep');
    if (!p.owned.contains(p.theme)) {
      p.theme = 'theme_cosmos';
      r.damaged = true;
    }
    if (!p.owned.contains(p.background)) {
      p.background = 'bg_deep';
      r.damaged = true;
    }
    p.achievements = r.strings('achievements');
    p.discovered = r.ints('discovered', min: 1, max: 64);

    final s = r.child('stats');
    p.runs = s.integer('runs', 0);
    p.totalMerges = s.integer('totalMerges', 0);
    p.totalScore = s.integer('totalScore', 0);
    p.maxChain = s.integer('maxChain', 0);
    p.maxLevel = s.integer('maxLevel', 0, max: 64);
    p.bigBangs = s.integer('bigBangs', 0);
    p.perfects = s.integer('perfects', 0);
    p.dailyCompleted = s.integer('dailyCompleted', 0);

    final d = r.child('daily');
    p.dailyDate = d.integer('date', 0);
    p.dailyBest = d.integer('best', 0);
    p.dailyDone = d.boolean('done', false);

    final w = r.child('reward');
    p.rewardDay = w.integer('day', 0, max: 6);
    p.rewardStreak = w.integer('streak', 0);
    p.rewardLastDate = w.integer('lastDate', 0);
    p.rewardLastUtcMs = w.integer('lastUtcMs', 0);

    final t = r.child('settings');
    p.music = t.boolean('music', true);
    p.sfx = t.boolean('sfx', true);
    p.haptics = t.boolean('haptics', true);
    p.showNumbers = t.boolean('showNumbers', false);
    p.language = t.string('language', '');

    p.tutorialDone = r.boolean('tutorialDone', false);
    p.removeAds = r.boolean('removeAds', false);
    p.lastRewardedRun = r.string('lastRewardedRun', '');
    p.lastDoubledRun = r.string('lastDoubledRun', '');
    p.lastRunCoins = r.integer('lastRunCoins', 0);
    p.runsSinceInterstitial = r.integer('runsSinceInterstitial', 0);
    final run = raw['activeRun'];
    if (run is Map) {
      p.activeRun = Map<String, dynamic>.from(run);
    } else if (run != null) {
      r.damaged = true;
    }

    final bad = damaged || r.damaged || s.damaged || d.damaged || w.damaged || t.damaged;
    return LoadResult(p, bad ? LoadStatus.recovered : LoadStatus.ok);
  }
}

/// Reads typed values out of untrusted JSON, falling back to a default and remembering that it
/// had to.
class _Reader {
  _Reader(this.map);
  final Map<String, dynamic> map;
  bool damaged = false;

  _Reader child(String key) {
    final v = map[key];
    if (v is Map) return _Reader(Map<String, dynamic>.from(v));
    if (v != null) damaged = true;
    return _Reader(const {});
  }

  int integer(String key, int def, {int min = 0, int max = 9000000000000000}) {
    final v = map[key];
    if (v == null) return def;
    if (v is num && v.isFinite) {
      final i = v.toInt();
      if (i >= min && i <= max) return i;
    }
    damaged = true;
    return def;
  }

  bool boolean(String key, bool def) {
    final v = map[key];
    if (v == null) return def;
    if (v is bool) return v;
    damaged = true;
    return def;
  }

  String string(String key, String def) {
    final v = map[key];
    if (v == null) return def;
    if (v is String && v.length <= 64) return v;
    damaged = true;
    return def;
  }

  Set<String> strings(String key) {
    final v = map[key];
    if (v == null) return {};
    if (v is List) {
      final out = <String>{};
      for (final e in v) {
        if (e is String && e.length <= 64) {
          out.add(e);
        } else {
          damaged = true;
        }
      }
      return out;
    }
    damaged = true;
    return {};
  }

  Set<int> ints(String key, {required int min, required int max}) {
    final v = map[key];
    if (v == null) return {};
    if (v is List) {
      final out = <int>{};
      for (final e in v) {
        if (e is int && e >= min && e <= max) {
          out.add(e);
        } else {
          damaged = true;
        }
      }
      return out;
    }
    damaged = true;
    return {};
  }
}
