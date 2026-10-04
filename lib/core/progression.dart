/// What a finished run is worth and what it unlocks: coins, XP, levels, achievements, the shop.
/// All of it is plain data plus pure functions over [Profile], so it is unit-tested end to end.
library;

import 'balance.dart';
import 'campaign.dart';
import 'campaign_data.dart';
import 'daily.dart';
import 'game_core.dart';
import 'profile.dart';

enum Stat {
  totalMerges,
  maxChain,
  maxLevel,
  bestScore,
  runs,
  dailyCompleted,
  bigBangs,
  perfects,
  campaignLevels,
  stars,
  masters,
  worlds,
  weeklies,
}

class Achievement {
  const Achievement(this.id, this.stat, this.target, this.coins);
  final String id;
  final Stat stat;
  final int target;
  final int coins;
}

const List<Achievement> achievements = [
  Achievement('merges_10', Stat.totalMerges, 10, 20),
  Achievement('merges_100', Stat.totalMerges, 100, 40),
  Achievement('merges_1000', Stat.totalMerges, 1000, 150),
  Achievement('merges_5000', Stat.totalMerges, 5000, 400),
  Achievement('first_chain', Stat.maxChain, 2, 15),
  Achievement('chain_5', Stat.maxChain, 5, 50),
  Achievement('chain_7', Stat.maxChain, 7, 150),
  Achievement('evo_6', Stat.maxLevel, 6, 20),
  Achievement('evo_8', Stat.maxLevel, 8, 60),
  Achievement('evo_10', Stat.maxLevel, 10, 200),
  Achievement('evo_12', Stat.maxLevel, 12, 500),
  Achievement('big_bang', Stat.bigBangs, 1, 1000),
  Achievement('score_5k', Stat.bestScore, 5000, 30),
  Achievement('score_20k', Stat.bestScore, 20000, 100),
  Achievement('score_50k', Stat.bestScore, 50000, 300),
  Achievement('perfect_25', Stat.perfects, 25, 60),
  Achievement('perfect_250', Stat.perfects, 250, 250),
  Achievement('runs_10', Stat.runs, 10, 30),
  Achievement('runs_100', Stat.runs, 100, 200),
  Achievement('daily_1', Stat.dailyCompleted, 1, 40),
  Achievement('daily_7', Stat.dailyCompleted, 7, 250),
  Achievement('camp_10', Stat.campaignLevels, 10, 40),
  Achievement('camp_40', Stat.campaignLevels, 40, 150),
  Achievement('camp_100', Stat.campaignLevels, 100, 500),
  Achievement('stars_30', Stat.stars, 30, 60),
  Achievement('stars_150', Stat.stars, 150, 250),
  Achievement('stars_300', Stat.stars, 300, 800),
  Achievement('master_5', Stat.masters, 5, 60),
  Achievement('master_40', Stat.masters, 40, 300),
  Achievement('master_100', Stat.masters, 100, 1000),
  Achievement('world_1', Stat.worlds, 1, 100),
  Achievement('world_3', Stat.worlds, 3, 300),
  Achievement('world_5', Stat.worlds, 5, 1000),
  Achievement('weekly_5', Stat.weeklies, 5, 150),
];

int statValue(Profile p, Stat s) => switch (s) {
  Stat.totalMerges => p.totalMerges,
  Stat.maxChain => p.maxChain,
  Stat.maxLevel => p.maxLevel,
  Stat.bestScore => p.bestScore,
  Stat.runs => p.runs,
  Stat.dailyCompleted => p.dailyCompleted,
  Stat.bigBangs => p.bigBangs,
  Stat.perfects => p.perfects,
  Stat.campaignLevels => p.levelsDone,
  Stat.stars => p.totalStars,
  Stat.masters => p.mastersDone,
  Stat.worlds => worldsCompleted(p),
  Stat.weeklies => p.weekliesClaimed,
};

// --- Campaign progress (derived from the level records, so it cannot drift out of sync) ---

bool worldCompleted(Profile p, int world) {
  final list = worldLevels(world);
  return list.isNotEmpty && p.starsOf(list.last.id) > 0;
}

int worldsCompleted(Profile p) => worlds.where((w) => worldCompleted(p, w.id)).length;

int worldStars(Profile p, int world) => worldLevels(world).fold(0, (a, l) => a + p.starsOf(l.id));

int worldLevelsDone(Profile p, int world) => worldLevels(world).where((l) => p.starsOf(l.id) > 0).length;

/// A level opens when the one before it in campaign order has been completed.
bool levelUnlocked(Profile p, LevelDef level) {
  final i = campaignLevels.indexWhere((l) => l.id == level.id);
  if (i < 0) return false;
  return i == 0 || p.starsOf(campaignLevels[i - 1].id) > 0;
}

/// The level the "Continue" button leads to: the first one not completed yet, or null when
/// the whole campaign is done.
LevelDef? currentLevel(Profile p) {
  for (final l in campaignLevels) {
    if (p.starsOf(l.id) == 0) return l;
  }
  return null;
}

// --- Weekly personal goals and the monthly archive (local, no server, no competition) ---

enum WeekStat { levels, stars, chains, masters, dailies, merges }

class WeeklyGoal {
  const WeeklyGoal(this.stat, this.target, this.coins);
  final WeekStat stat;
  final int target;
  final int coins;
  String get id => stat.name;
}

const List<WeeklyGoal> weeklyPool = [
  WeeklyGoal(WeekStat.levels, 10, 80),
  WeeklyGoal(WeekStat.merges, 300, 60),
  WeeklyGoal(WeekStat.stars, 12, 100),
  WeeklyGoal(WeekStat.dailies, 3, 100),
  WeeklyGoal(WeekStat.chains, 5, 80),
  WeeklyGoal(WeekStat.masters, 3, 120),
];

/// A chain this long counts as a "big combo" for the weekly goal.
const int bigChain = 4;
const int weeklyGoalCount = 3;
const int monthlyTarget = 40;
const int monthlyCoins = 300;
const String monthlyTheme = 'theme_archive';
const int pointsPerStar = 1;
const int pointsPerMaster = 2;
const int pointsPerDaily = 2;
const int pointsPerWeekly = 3;

/// Monday-based week number of a date key.
int weekKeyOf(int dateKey) => (dayNumber(dateKey) + 3) ~/ 7;

int monthKeyOf(int dateKey) => dateKey ~/ 100;

/// Starts a new week / month when the calendar has moved on. A clock set back changes
/// nothing: progress is kept and nothing can be claimed twice.
void syncCalendar(Profile p, DateTime nowLocal) {
  final date = dateKeyOf(nowLocal);
  final week = weekKeyOf(date);
  if (week > p.weekKey) {
    p.weekKey = week;
    p.weekProgress = {};
    p.weekClaimed = {};
  }
  final month = monthKeyOf(date);
  if (month > p.monthKey) {
    p.monthKey = month;
    p.monthPoints = 0;
    p.monthClaimed = false;
  }
}

/// This week's three goals. Goals that can no longer be reached (every star or master
/// challenge already earned) are swapped for ones that can.
List<WeeklyGoal> weeklyGoals(Profile p) {
  final starsLeft = campaignLevels.length * 3 - p.totalStars;
  final mastersLeft = p.levelsDone - p.mastersDone;
  bool reachable(WeeklyGoal g) => switch (g.stat) {
    WeekStat.stars => starsLeft >= g.target || p.weekClaimed.contains(g.id),
    WeekStat.masters => mastersLeft >= g.target || p.weekClaimed.contains(g.id),
    _ => true,
  };
  final out = <WeeklyGoal>[];
  for (var i = 0; i < weeklyPool.length && out.length < weeklyGoalCount; i++) {
    final g = weeklyPool[(p.weekKey.abs() % 2 + i * 2) % weeklyPool.length];
    if (!out.contains(g) && reachable(g)) out.add(g);
  }
  for (final g in weeklyPool) {
    if (out.length >= weeklyGoalCount) break;
    if (!out.contains(g) && reachable(g)) out.add(g);
  }
  return out;
}

int weeklyProgress(Profile p, WeeklyGoal g) => (p.weekProgress[g.id] ?? 0).clamp(0, g.target);

void _week(Profile p, WeekStat stat, int amount) {
  if (amount > 0) p.weekProgress[stat.name] = (p.weekProgress[stat.name] ?? 0) + amount;
}

/// Pays a finished weekly goal. Returns the coins, or 0 when there is nothing to claim.
int claimWeekly(Profile p, String goalId) {
  for (final g in weeklyGoals(p)) {
    if (g.id != goalId) continue;
    if (p.weekClaimed.contains(g.id) || weeklyProgress(p, g) < g.target) return 0;
    p.weekClaimed.add(g.id);
    p.weekliesClaimed++;
    p.monthPoints += pointsPerWeekly;
    p.coins += g.coins;
    return g.coins;
  }
  return 0;
}

/// Pays the monthly archive once per month. The first time ever it also gives the archive theme.
int claimMonthly(Profile p) {
  if (p.monthClaimed || p.monthPoints < monthlyTarget) return 0;
  p.monthClaimed = true;
  p.owned.add(monthlyTheme);
  p.coins += monthlyCoins;
  return monthlyCoins;
}

/// Hands over the gift for players from before the campaign update. Returns the coins.
int claimGift(Profile p) {
  final coins = p.gift;
  p.gift = 0;
  p.coins += coins;
  return coins;
}

enum ItemKind { theme, background }

class ShopItem {
  const ShopItem(
    this.id,
    this.kind,
    this.price,
    this.rarity, {
    this.reqLevel = 0,
    this.reqWorld = 0,
    this.archive = false,
  });
  final String id;
  final ItemKind kind;
  final int price;

  /// 0 common .. 3 legendary.
  final int rarity;

  /// When > 0 the item is not sold: it unlocks for free on reaching this player level.
  final int reqLevel;

  /// When > 0 the item is not sold: it is the prize for completing this campaign world.
  final int reqWorld;

  /// Not sold: the prize of the monthly archive.
  final bool archive;

  bool get earned => reqLevel > 0 || reqWorld > 0 || archive;
}

const List<ShopItem> shopItems = [
  ShopItem('theme_cosmos', ItemKind.theme, 0, 0),
  ShopItem('theme_neon', ItemKind.theme, 400, 1),
  ShopItem('theme_crystal', ItemKind.theme, 0, 1, reqLevel: 6),
  ShopItem('theme_ember', ItemKind.theme, 2000, 2),
  ShopItem('theme_aurora', ItemKind.theme, 3500, 2),
  ShopItem('theme_void', ItemKind.theme, 6000, 3),
  ShopItem('theme_archive', ItemKind.theme, 0, 3, archive: true),
  ShopItem('bg_deep', ItemKind.background, 0, 0),
  ShopItem('bg_nebula', ItemKind.background, 300, 0),
  ShopItem('bg_dawn', ItemKind.background, 0, 1, reqLevel: 3),
  ShopItem('bg_emerald', ItemKind.background, 1500, 1),
  ShopItem('bg_crimson', ItemKind.background, 2800, 2),
  ShopItem('bg_singularity', ItemKind.background, 5000, 3),
  ShopItem('bg_origin', ItemKind.background, 0, 1, reqWorld: 1),
  ShopItem('bg_cradle', ItemKind.background, 0, 1, reqWorld: 2),
  ShopItem('bg_forge', ItemKind.background, 0, 2, reqWorld: 3),
  ShopItem('bg_spiral', ItemKind.background, 0, 2, reqWorld: 4),
  ShopItem('bg_horizon', ItemKind.background, 0, 3, reqWorld: 5),
];

ShopItem? shopItem(String id) {
  for (final i in shopItems) {
    if (i.id == id) return i;
  }
  return null;
}

enum BuyResult { ok, alreadyOwned, notEnoughCoins, locked, unknown }

BuyResult buyItem(Profile p, String id) {
  final item = shopItem(id);
  if (item == null) return BuyResult.unknown;
  if (p.owned.contains(id)) return BuyResult.alreadyOwned;
  if (item.earned) return BuyResult.locked;
  if (p.coins < item.price) return BuyResult.notEnoughCoins;
  p.coins -= item.price;
  p.owned.add(id);
  return BuyResult.ok;
}

bool equipItem(Profile p, String id) {
  final item = shopItem(id);
  if (item == null || !p.owned.contains(id)) return false;
  if (item.kind == ItemKind.theme) {
    p.theme = id;
  } else {
    p.background = id;
  }
  return true;
}

/// Gives the player every earned item their level and completed worlds entitle them to.
/// Returns the new ones.
List<ShopItem> grantLevelItems(Profile p) {
  final out = <ShopItem>[];
  for (final i in shopItems) {
    final due = (i.reqLevel > 0 && p.level >= i.reqLevel) || (i.reqWorld > 0 && worldCompleted(p, i.reqWorld));
    if (due && p.owned.add(i.id)) out.add(i);
  }
  return out;
}

class RunOutcome {
  int score = 0;
  int coins = 0;
  int xp = 0;
  int levelsGained = 0;
  int levelCoins = 0;
  bool record = false;
  int previousBest = 0;
  int achievementCoins = 0;
  List<Achievement> newAchievements = [];
  List<int> discoveries = [];
  List<ShopItem> unlockedItems = [];
  bool dailyCompletedNow = false;
  int dailyCoins = 0;

  // Campaign level results (all zero / false for classic and daily runs).
  bool passed = false;
  int stars = 0;
  int starsBefore = 0;
  bool firstClear = false;
  bool masterNow = false;
  int campaignCoins = 0;

  /// The world whose trial was completed for the first time by this run, or 0.
  int worldDone = 0;
  int fewestBefore = 0;

  int get newStars => stars > starsBefore ? stars - starsBefore : 0;
  int get totalCoins => coins + levelCoins + achievementCoins + dailyCoins + campaignCoins;
}

/// Applies a finished run to the profile. Safe to call twice for the same [runId]: the second
/// call changes nothing and returns null.
RunOutcome? applyRun(
  Profile p,
  GameCore core, {
  required String runId,
  DailyChallenge? daily,
  LevelDef? level,
  bool master = false,
  DateTime? now,
  Balance balance = Balance.standard,
}) {
  if (runId.isEmpty || p.lastRewardedRun == runId) return null;
  p.lastRewardedRun = runId;
  if (now != null) syncCalendar(p, now);

  final out = RunOutcome()
    ..score = core.score
    ..previousBest = p.bestScore;

  var xpBonus = 0;
  if (level != null) {
    xpBonus = _applyLevel(p, core, level, master, out);
  } else if (daily == null) {
    out.record = core.score > p.bestScore && core.score > 0;
    if (out.record) p.bestScore = core.score;
  } else {
    if (p.dailyDate != daily.dateKey) {
      p.dailyDate = daily.dateKey;
      p.dailyBest = 0;
      p.dailyDone = false;
    }
    out.previousBest = p.dailyBest;
    out.record = core.score > p.dailyBest && core.score > 0;
    if (out.record) p.dailyBest = core.score;
    if (!p.dailyDone && daily.completed(core)) {
      p.dailyDone = true;
      p.dailyCompleted++;
      out.dailyCompletedNow = true;
      out.dailyCoins = balance.dailyCompleteCoins;
    }
  }

  out.coins = core.score ~/ balance.pointsPerCoin + core.bonusCoins;
  // A record on the very first run is not an achievement worth paying for.
  if (out.record && daily == null && level == null && p.runs > 0) out.coins += balance.recordBonusCoins;
  p.lastRunCoins = out.coins;

  p.runs++;
  p.totalMerges += core.merges;
  p.totalScore += core.score;
  p.perfects += core.perfects;
  p.bigBangs += core.bigBangs;
  if (core.maxChain > p.maxChain) p.maxChain = core.maxChain;
  if (core.maxLevel > p.maxLevel) p.maxLevel = core.maxLevel;
  for (final lv in core.createdLevels) {
    if (p.discovered.add(lv)) out.discoveries.add(lv);
  }
  out.discoveries.sort();

  out.xp =
      core.merges * balance.xpPerMerge +
      (core.score * balance.xpPerScore).floor() +
      balance.xpPerRun +
      xpBonus +
      (out.dailyCompletedNow ? balance.xpDailyComplete : 0);
  _week(p, WeekStat.merges, core.merges);
  if (core.maxChain >= bigChain) _week(p, WeekStat.chains, 1);
  if (out.dailyCompletedNow) {
    _week(p, WeekStat.dailies, 1);
    p.monthPoints += pointsPerDaily;
  }
  p.xp += out.xp;
  while (p.xp >= balance.xpForLevel(p.level)) {
    p.xp -= balance.xpForLevel(p.level);
    p.level++;
    out.levelsGained++;
    out.levelCoins += balance.levelUpCoins;
  }
  out.unlockedItems = grantLevelItems(p);

  for (final a in achievements) {
    if (!p.achievements.contains(a.id) && statValue(p, a.stat) >= a.target) {
      p.achievements.add(a.id);
      out.newAchievements.add(a);
      out.achievementCoins += a.coins;
    }
  }

  p.coins += out.totalCoins;
  p.runsSinceInterstitial++;
  return out;
}

/// Books a campaign run into the level's record. Returns the bonus XP. A locked level, or a
/// master run on a level that was never completed, earns nothing here.
int _applyLevel(Profile p, GameCore core, LevelDef level, bool master, RunOutcome out) {
  p.attempts++;
  final rec = p.levels[level.id] ?? LevelRecord();
  out.starsBefore = rec.stars;
  out.previousBest = rec.best;
  out.fewestBefore = rec.fewest;
  if (!levelUnlocked(p, level) || (master && rec.stars == 0)) return 0;

  out.passed = level.passed(core, master: master);
  out.record = !master && core.score > rec.best && core.score > 0;
  var xp = 0;
  if (master) {
    out.stars = rec.stars;
    if (out.passed && !rec.master) {
      rec.master = true;
      out.masterNow = true;
      out.campaignCoins += level.masterCoins;
      xp += level.xp;
      p.monthPoints += pointsPerMaster;
      _week(p, WeekStat.masters, 1);
    }
  } else {
    final stars = level.stars(core);
    out.stars = stars > rec.stars ? stars : rec.stars;
    if (out.record) rec.best = core.score;
    if (core.maxChain > rec.chain) rec.chain = core.maxChain;
    if (out.passed) {
      p.fails.remove(level.id);
      if (!level.byScore && (rec.fewest == 0 || core.drops < rec.fewest)) rec.fewest = core.drops;
      if (rec.stars == 0) {
        out.firstClear = true;
        out.campaignCoins += level.coins;
        xp += level.xp;
      }
      if (stars > rec.stars) {
        out.campaignCoins += (stars - rec.stars) * level.starCoins;
        p.monthPoints += (stars - rec.stars) * pointsPerStar;
        _week(p, WeekStat.stars, stars - rec.stars);
        rec.stars = stars;
      }
      _week(p, WeekStat.levels, 1);
    } else {
      p.fails[level.id] = (p.fails[level.id] ?? 0) + 1;
    }
  }
  if (rec.stars > 0 || rec.best > 0 || rec.chain > 0) p.levels[level.id] = rec;
  if (out.firstClear && level.trial) out.worldDone = level.world;
  return xp;
}

/// Rewarded "2x coins". Doubles only the run's own coins and only once per run, no matter how
/// many times the ad SDK fires its callback.
int doubleRunCoins(Profile p, String runId) {
  if (runId.isEmpty || p.lastRewardedRun != runId || p.lastDoubledRun == runId) return 0;
  p.lastDoubledRun = runId;
  p.coins += p.lastRunCoins;
  return p.lastRunCoins;
}
