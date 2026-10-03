/// What a finished run is worth and what it unlocks: coins, XP, levels, achievements, the shop.
/// All of it is plain data plus pure functions over [Profile], so it is unit-tested end to end.
library;

import 'balance.dart';
import 'daily.dart';
import 'game_core.dart';
import 'profile.dart';

enum Stat { totalMerges, maxChain, maxLevel, bestScore, runs, dailyCompleted, bigBangs, perfects }

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
};

enum ItemKind { theme, background }

class ShopItem {
  const ShopItem(this.id, this.kind, this.price, this.rarity, {this.reqLevel = 0});
  final String id;
  final ItemKind kind;
  final int price;

  /// 0 common .. 3 legendary.
  final int rarity;

  /// When > 0 the item is not sold: it unlocks for free on reaching this player level.
  final int reqLevel;
}

const List<ShopItem> shopItems = [
  ShopItem('theme_cosmos', ItemKind.theme, 0, 0),
  ShopItem('theme_neon', ItemKind.theme, 400, 1),
  ShopItem('theme_crystal', ItemKind.theme, 0, 1, reqLevel: 6),
  ShopItem('theme_ember', ItemKind.theme, 2000, 2),
  ShopItem('theme_aurora', ItemKind.theme, 3500, 2),
  ShopItem('theme_void', ItemKind.theme, 6000, 3),
  ShopItem('bg_deep', ItemKind.background, 0, 0),
  ShopItem('bg_nebula', ItemKind.background, 300, 0),
  ShopItem('bg_dawn', ItemKind.background, 0, 1, reqLevel: 3),
  ShopItem('bg_emerald', ItemKind.background, 1500, 1),
  ShopItem('bg_crimson', ItemKind.background, 2800, 2),
  ShopItem('bg_singularity', ItemKind.background, 5000, 3),
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
  if (item.reqLevel > 0) return BuyResult.locked;
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

/// Gives the player every level-gated item their level entitles them to. Returns the new ones.
List<ShopItem> grantLevelItems(Profile p) {
  final out = <ShopItem>[];
  for (final i in shopItems) {
    if (i.reqLevel > 0 && p.level >= i.reqLevel && p.owned.add(i.id)) out.add(i);
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

  int get totalCoins => coins + levelCoins + achievementCoins + dailyCoins;
}

/// Applies a finished run to the profile. Safe to call twice for the same [runId]: the second
/// call changes nothing and returns null.
RunOutcome? applyRun(
  Profile p,
  GameCore core, {
  required String runId,
  DailyChallenge? daily,
  Balance balance = Balance.standard,
}) {
  if (runId.isEmpty || p.lastRewardedRun == runId) return null;
  p.lastRewardedRun = runId;

  final out = RunOutcome()
    ..score = core.score
    ..previousBest = p.bestScore;

  if (daily == null) {
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
  if (out.record && daily == null && p.runs > 0) out.coins += balance.recordBonusCoins;
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
      (out.dailyCompletedNow ? balance.xpDailyComplete : 0);
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

/// Rewarded "2x coins". Doubles only the run's own coins and only once per run, no matter how
/// many times the ad SDK fires its callback.
int doubleRunCoins(Profile p, String runId) {
  if (runId.isEmpty || p.lastRewardedRun != runId || p.lastDoubledRun == runId) return 0;
  p.lastDoubledRun = runId;
  p.coins += p.lastRunCoins;
  return p.lastRunCoins;
}
