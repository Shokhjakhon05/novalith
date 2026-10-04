/// The campaign: worlds, level definitions, goals and stars. Levels are plain data
/// (`campaign_data.dart`, produced by `tool/gen_campaign.dart`); this file only knows how to
/// start a level and how to judge a run against it. Nothing here imports Flutter.
library;

import 'balance.dart';
import 'bots.dart';
import 'campaign_data.dart';
import 'game_core.dart';
import 'rng.dart';

enum GoalType { score, evolve, chain, merges, perfects, survive }

class Goal {
  const Goal(this.type, this.target);
  final GoalType type;

  /// Points, evolution level, chain length, merge count or perfect drops. Unused for survive.
  final int target;
}

/// The harder replay of a level that opens once the level is completed.
class MasterDef {
  const MasterDef({required this.drops, required this.score, required this.seeds, this.line = masterLine});
  final int drops;

  /// Score to reach (levels judged by score); 0 for levels judged by drops.
  final int score;
  final List<int> seeds;

  /// How much lower than in the level itself the overflow line sits.
  final int line;
}

class LevelDef {
  const LevelDef({
    required this.id,
    required this.goals,
    required this.drops,
    required this.star2,
    required this.star3,
    required this.seeds,
    required this.master,
    this.spawn = 0,
    this.line = 0,
    this.start = const [],
    this.trial = false,
  });

  /// world * 100 + position in the world (101 = first level of the first world).
  final int id;
  final List<Goal> goals;
  final int drops;

  /// Second and third star. Score to reach when [byScore], otherwise drops to finish within.
  final int star2;
  final int star3;

  /// Piece sequences this level rotates through, one per attempt. Each was played to the end
  /// by the validation bot, so no attempt starts from an impossible deal.
  final List<int> seeds;
  final MasterDef master;

  /// Index into [spawnPresets].
  final int spawn;

  /// How much lower than usual the overflow line sits.
  final int line;

  /// Bodies already on the board: `[level, x]`.
  final List<List<int>> start;

  /// The world's finale.
  final bool trial;

  int get world => id ~/ 100;
  int get index => id % 100;

  /// Levels with a score or survival goal play all their drops and are rated by score; the
  /// others end the moment the goal is reached and are rated by how few drops that took.
  bool get byScore => goals.any((g) => g.type == GoalType.score || g.type == GoalType.survive);

  int get coins => trial ? 60 + 40 * world : 8 + 4 * world;
  int get starCoins => 4 + 2 * world;
  int get masterCoins => 20 + 5 * world;
  int get xp => trial ? 150 : 30 + 10 * world;

  Balance balanceFor(Balance base, {bool master = false}) =>
      base.tuned(spawnWeights: spawnPresets[spawn], dangerY: base.dangerY + line + (master ? this.master.line : 0));

  /// Extra drops granted after repeated failures, so nobody stays stuck on one level.
  int assistDrops(int fails) => drops * (fails ~/ 3).clamp(0, 3) ~/ 10;

  GameCore createRun({Balance balance = Balance.standard, int attempt = 0, bool master = false, int fails = 0}) {
    final list = master ? this.master.seeds : seeds;
    final limit = master ? this.master.drops : drops + assistDrops(fails);
    return GameCore(
      balance: balanceFor(balance, master: master),
      seed: list[attempt.abs() % list.length],
      adaptiveSpawns: false,
      dropLimit: limit,
    )..seedBoard(start);
  }

  int goalProgress(GameCore core, Goal g) => switch (g.type) {
    GoalType.score => core.score,
    GoalType.evolve => core.maxLevel,
    GoalType.chain => core.maxChain,
    GoalType.merges => core.merges,
    GoalType.perfects => core.perfects,
    GoalType.survive => core.drops,
  };

  bool goalMet(GameCore core, Goal g, {bool master = false}) => switch (g.type) {
    GoalType.score => core.score >= (master ? this.master.score : g.target),
    GoalType.survive => core.over && core.endReason == EndReason.dropsExhausted,
    _ => goalProgress(core, g) >= g.target,
  };

  bool passed(GameCore core, {bool master = false}) {
    for (final g in goals) {
      if (!goalMet(core, g, master: master)) return false;
    }
    if (master && byScore && core.score < this.master.score) return false;
    return true;
  }

  /// 0 = not passed. Stars never depend on how the run ended, only on what was achieved.
  int stars(GameCore core) {
    if (!passed(core)) return 0;
    if (byScore) return 1 + (core.score >= star2 ? 1 : 0) + (core.score >= star3 ? 1 : 0);
    return 1 + (core.drops <= star2 ? 1 : 0) + (core.drops <= star3 ? 1 : 0);
  }
}

/// How much lower the overflow line usually sits in a master challenge.
const int masterLine = 22;

/// Piece mixes: weights for levels 1..n. 0 is the classic mix.
const List<List<int>> spawnPresets = [
  [35, 30, 20, 10, 5],
  [45, 30, 17, 6, 2],
  [22, 26, 24, 17, 11],
  [30, 26, 20, 12, 8, 4],
  [24, 22, 20, 16, 11, 7],
  [0, 0, 30, 28, 22, 14, 6],
  [0, 0, 0, 30, 28, 22, 14, 6],
  [0, 0, 0, 0, 0, 34, 30, 20, 11, 5],
];

class WorldDef {
  const WorldDef(this.id, this.key, this.background, this.accent, this.emblem);
  final int id;

  /// Localisation key suffix: `world_<key>`.
  final String key;

  /// Backdrop of the world's levels; finishing the world gives it to the player.
  final String background;
  final int accent;

  /// Evolution level drawn as the world's emblem.
  final int emblem;
}

const List<WorldDef> worlds = [
  WorldDef(1, 'origin', 'bg_origin', 0xFFC58A, 3),
  WorldDef(2, 'nebula', 'bg_cradle', 0xFF7AD0, 5),
  WorldDef(3, 'stellar', 'bg_forge', 0xFFD65A, 8),
  WorldDef(4, 'galactic', 'bg_spiral', 0x7FE3FF, 10),
  WorldDef(5, 'singularity', 'bg_horizon', 0xB48CFF, 11),
];

WorldDef worldDef(int id) => worlds[(id - 1).clamp(0, worlds.length - 1)];

final Map<int, LevelDef> _byId = {for (final l in campaignLevels) l.id: l};

LevelDef? levelDef(int id) => _byId[id];

List<LevelDef> worldLevels(int world) => [
  for (final l in campaignLevels)
    if (l.world == world) l,
];

/// The level after [id] in campaign order, or null after the very last one.
LevelDef? nextLevel(int id) {
  final i = campaignLevels.indexWhere((l) => l.id == id);
  return i < 0 || i + 1 >= campaignLevels.length ? null : campaignLevels[i + 1];
}

/// Plays a level with a bot, the way the game screen does: an early-finish level stops at the
/// merge that reaches its goal.
GameCore playLevel(
  LevelDef def,
  Bot bot, {
  int attempt = 0,
  bool master = false,
  double dropEvery = 0.9,
  Balance balance = Balance.standard,
}) {
  final core = def.createRun(balance: balance, attempt: attempt, master: master);
  final rng = SeededRng(core.seed ^ 0x5F3759DF);
  var nextDropAt = 0.0;
  var merges = 0;
  final maxSteps = ((core.dropLimit + 12) * (dropEvery + 0.5) / core.balance.stepDt).ceil();
  for (var i = 0; i < maxSteps && !core.over; i++) {
    if (core.canDrop && core.time >= nextDropAt) {
      core.drop(bot(core, rng));
      nextDropAt = core.time + dropEvery;
    }
    core.step();
    core.events.clear();
    if (!def.byScore && core.merges != merges) {
      merges = core.merges;
      if (def.passed(core, master: master)) core.complete();
    }
  }
  return core;
}

/// Development-time check of the level data. Returns human-readable problems; empty = valid.
List<String> validateCampaign(List<LevelDef> levels, {Balance balance = Balance.standard}) {
  final out = <String>[];
  final seen = <int>{};
  for (final l in levels) {
    final at = 'level ${l.id}';
    if (!seen.add(l.id)) out.add('$at: duplicate id');
    if (l.world < 1 || l.world > worlds.length) out.add('$at: unknown world');
    if (l.index < 1) out.add('$at: bad index');
    if (l.goals.isEmpty || l.goals.length > 2) out.add('$at: needs one or two goals');
    if (l.goals.map((g) => g.type).toSet().length != l.goals.length) out.add('$at: repeated goal type');
    if (l.spawn < 0 || l.spawn >= spawnPresets.length) out.add('$at: unknown spawn preset');
    if (l.drops < 3 || l.drops > 200) out.add('$at: drop limit out of range');
    if (l.seeds.isEmpty || l.master.seeds.isEmpty) out.add('$at: no seeds');
    if (l.line < 0 || balance.dangerY + l.line + masterLine > balance.floorY - 220) out.add('$at: line too low');
    if (l.coins <= 0 || l.xp <= 0 || l.starCoins <= 0 || l.masterCoins <= 0) out.add('$at: invalid reward');
    for (final g in l.goals) {
      final ok = switch (g.type) {
        GoalType.score => g.target > 0,
        GoalType.evolve => g.target >= 2 && g.target <= balance.maxLevel,
        GoalType.chain => g.target >= 2 && g.target <= 12,
        GoalType.merges || GoalType.perfects => g.target >= 1 && g.target < l.drops,
        GoalType.survive => true,
      };
      if (!ok) out.add('$at: invalid ${g.type.name} target ${g.target}');
    }
    for (final s in l.start) {
      if (s.length != 2 || s[0] < 1 || s[0] > balance.maxLevel || s[1] < 0 || s[1] > balance.worldW) {
        out.add('$at: bad starting body $s');
      }
    }
    if (l.byScore) {
      final first = l.goals.where((g) => g.type == GoalType.score).map((g) => g.target).fold(0, (a, b) => a + b);
      if (!(first < l.star2 && l.star2 < l.star3)) {
        out.add('$at: score stars must rise ($first, ${l.star2}, ${l.star3})');
      }
      if (l.master.score <= 0) out.add('$at: master needs a score');
    } else {
      if (!(l.star3 < l.star2 && l.star2 < l.drops && l.star3 >= 1)) {
        out.add('$at: drop stars must tighten (${l.drops}, ${l.star2}, ${l.star3})');
      }
      if (l.master.drops >= l.drops || l.master.drops < l.star3) out.add('$at: master drops out of range');
    }
  }
  for (final w in worlds) {
    final list = [
      for (final l in levels)
        if (l.world == w.id) l,
    ];
    if (list.isEmpty) {
      out.add('world ${w.id}: no levels');
      continue;
    }
    for (var i = 0; i < list.length; i++) {
      if (list[i].index != i + 1) out.add('world ${w.id}: level ${list[i].id} is out of sequence');
      if (list[i].trial != (i == list.length - 1)) out.add('world ${w.id}: the trial must be the last level only');
    }
  }
  for (var i = 1; i < levels.length; i++) {
    if (levels[i].id <= levels[i - 1].id) out.add('level ${levels[i].id}: not in campaign order');
  }
  return out;
}
