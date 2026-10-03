/// Every tunable number of the game lives here. A designer rebalances Novalith by editing this
/// file only - the physics, merge and reward code read these values and never hardcode their own.
library;

/// One step of the evolution chain. Adding a level means adding one entry to [Balance.levels];
/// nothing in the merge engine refers to a level by number.
class EvoLevel {
  const EvoLevel({
    required this.id,
    required this.key,
    required this.radius,
    required this.coins,
    required this.rarity,
  });

  /// 1-based position in the chain.
  final int id;

  /// Stable identifier: localization key (`evo_<key>`), sprite recipe and sound are looked up by it.
  final String key;
  final double radius;

  /// Bonus coins granted when this level is created by a merge.
  final int coins;

  /// 0 common .. 3 legendary; drives how loud the merge feedback is.
  final int rarity;
}

class Balance {
  const Balance({
    this.worldW = 340,
    this.floorY = 480,
    this.dangerY = 84,
    this.spawnY = 42,
    this.gravity = 2100,
    this.stepDt = 1 / 120,
    this.maxStepsPerFrame = 4,
    this.solverIterations = 6,
    this.maxSpeed = 1500,
    this.contactDamping = 0.965,
    this.airDamping = 0.9992,
    this.friction = 0.12,
    this.growTime = 0.10,
    this.dropCooldown = 0.45,
    this.spawnWeights = const [35, 30, 20, 10, 5],
    this.maxSameInRow = 3,
    this.openingPairWithin = 3,
    this.recoveryBoost = 2.2,
    this.comboWindow = 1.0,
    this.comboMultipliers = const [1, 2, 3, 5, 6, 8],
    this.perfectBonusFactor = 2.0,
    this.overflowTime = 2.0,
    this.dropGrace = 0.5,
    this.continueGrace = 3.0,
    this.continuesPerRun = 1,
    this.continueClearMaxLevel = 3,
    this.bigBangScore = 600,
    this.bigBangCoins = 40,
    this.bigBangImpulse = 520,
    this.pointsPerCoin = 200,
    this.recordBonusCoins = 15,
    this.comboCoinFrom = 3,
    this.xpPerMerge = 1,
    this.xpPerScore = 0.04,
    this.xpPerRun = 10,
    this.xpDailyComplete = 60,
    this.levelUpCoins = 25,
    this.interstitialEveryRuns = 3,
    this.interstitialCooldownSec = 120,
    this.interstitialAfterRewardedSec = 60,
    this.interstitialSkipFirstRuns = 2,
    this.dailyRewardCoins = const [20, 30, 40, 60, 80, 100, 200],
    this.dailyCompleteCoins = 60,
    this.settleSpeed = 14,
    this.levels = defaultLevels,
  });

  static const Balance standard = Balance();

  // --- World (logical units; the renderer scales them to the screen) ---
  final double worldW;
  final double floorY;

  /// Overflow line: anything resting above it for [overflowTime] ends the run.
  final double dangerY;
  final double spawnY;

  // --- Physics ---
  final double gravity;
  final double stepDt;
  final int maxStepsPerFrame;
  final int solverIterations;
  final double maxSpeed;
  final double contactDamping;
  final double airDamping;

  /// Share of the sliding speed between two touching bodies removed per solver pass.
  final double friction;

  /// A freshly merged body grows to full size over this time, so a merge pushes neighbours
  /// apart smoothly instead of teleporting them.
  final double growTime;
  final double dropCooldown;

  // --- Fair spawner ---
  /// Weights for levels 1..n; only these levels are ever handed to the player.
  final List<int> spawnWeights;
  final int maxSameInRow;

  /// The first N pieces are guaranteed to contain a mergeable pair.
  final int openingPairWithin;

  /// In danger, pieces that already exist on the board are this many times more likely.
  final double recoveryBoost;

  // --- Combo / score ---
  final double comboWindow;
  final List<int> comboMultipliers;
  final double perfectBonusFactor;

  // --- Game over ---
  final double overflowTime;
  final double dropGrace;
  final double continueGrace;
  final int continuesPerRun;
  final int continueClearMaxLevel;

  // --- Big bang (two top-level bodies) ---
  final int bigBangScore;
  final int bigBangCoins;
  final double bigBangImpulse;

  // --- Economy ---
  final int pointsPerCoin;
  final int recordBonusCoins;
  final int comboCoinFrom;
  final int xpPerMerge;
  final double xpPerScore;
  final int xpPerRun;
  final int xpDailyComplete;
  final int levelUpCoins;

  // --- Ads pacing ---
  final int interstitialEveryRuns;
  final int interstitialCooldownSec;
  final int interstitialAfterRewardedSec;
  final int interstitialSkipFirstRuns;

  // --- Daily ---
  final List<int> dailyRewardCoins;
  final int dailyCompleteCoins;

  /// Below this speed (units/s) the board counts as settled.
  final double settleSpeed;

  final List<EvoLevel> levels;

  int get maxLevel => levels.length;
  EvoLevel level(int id) => levels[id - 1];
  double radius(int id) => levels[id - 1].radius;

  /// Points for creating level [id] by a merge, before the combo multiplier.
  int mergeScore(int id) => id * (id + 1) * (id + 2) ~/ 6;

  int comboMultiplier(int chain) {
    if (chain < 1) return 1;
    final i = chain - 1;
    return comboMultipliers[i < comboMultipliers.length ? i : comboMultipliers.length - 1];
  }

  /// XP needed to go from [level] to the next one.
  int xpForLevel(int level) => 80 + 45 * (level - 1) + 6 * (level - 1) * (level - 1);

  static const List<EvoLevel> defaultLevels = [
    EvoLevel(id: 1, key: 'dust', radius: 17, coins: 0, rarity: 0),
    EvoLevel(id: 2, key: 'meteor', radius: 23, coins: 0, rarity: 0),
    EvoLevel(id: 3, key: 'asteroid', radius: 30, coins: 0, rarity: 0),
    EvoLevel(id: 4, key: 'moon', radius: 37, coins: 0, rarity: 0),
    EvoLevel(id: 5, key: 'planet', radius: 45, coins: 0, rarity: 1),
    EvoLevel(id: 6, key: 'giant', radius: 53, coins: 1, rarity: 1),
    EvoLevel(id: 7, key: 'dwarf', radius: 61, coins: 2, rarity: 1),
    EvoLevel(id: 8, key: 'sun', radius: 69, coins: 3, rarity: 2),
    EvoLevel(id: 9, key: 'redgiant', radius: 77, coins: 5, rarity: 2),
    EvoLevel(id: 10, key: 'neutron', radius: 85, coins: 8, rarity: 2),
    EvoLevel(id: 11, key: 'blackhole', radius: 93, coins: 12, rarity: 3),
    EvoLevel(id: 12, key: 'galaxy', radius: 100, coins: 20, rarity: 3),
  ];
}
