/// Automated players. They exist to measure the game, not to ship in it: the balance report and
/// the stress tests run thousands of bot games against the real [GameCore].
library;

import 'balance.dart';
import 'game_core.dart';
import 'rng.dart';

typedef Bot = double Function(GameCore core, SeededRng rng);

/// Drops anywhere. The baseline: what the game gives you for no skill at all.
double randomBot(GameCore core, SeededRng rng) => rng.nextDouble() * core.balance.worldW;

/// Looks at where the piece would land: prefers touching its twin, then a low spot next to the
/// next size up, and avoids burying smaller pieces. Roughly what an attentive player does.
double greedyBot(GameCore core, SeededRng rng) {
  final b = core.balance;
  final level = core.currentPiece;
  final r = b.radius(level);

  var bestX = b.worldW / 2;
  var bestScore = -1e18;
  for (var x = r; x <= b.worldW - r; x += 4) {
    final y = core.landingY(x, r);
    var s = y * 0.25;
    for (final o in core.bodies) {
      final dx = o.x - x;
      final dy = o.y - y;
      final reach = o.r + r + 2.5;
      if (dx * dx + dy * dy > reach * reach) continue;
      if (o.level == level) {
        s += 120;
      } else if (o.level == level + 1) {
        s += 18;
      } else if (o.level < level && dy > 0) {
        s -= 22;
      }
    }
    if (s > bestScore) {
      bestScore = s;
      bestX = x;
    }
  }
  return bestX;
}

class RunStats {
  int score = 0;
  int drops = 0;
  int merges = 0;
  int firstMergeDrop = 0;
  int maxLevel = 0;
  int maxChain = 0;
  int maxBodies = 0;
  int bonusCoins = 0;
  int steps = 0;
  bool finished = false;
}

/// Plays one whole game. [dropEvery] is how long the bot waits between drops (a human pace).
RunStats simulate(
  Bot bot,
  int seed, {
  Balance balance = Balance.standard,
  double dropEvery = 0.9,
  int maxDrops = 3000,
  bool adaptive = true,
}) {
  final core = GameCore(balance: balance, seed: seed, adaptiveSpawns: adaptive);
  final rng = SeededRng(seed ^ 0x5F3759DF);
  final stats = RunStats();
  var nextDropAt = 0.0;
  final maxSteps = (maxDrops * (dropEvery + 0.5) / balance.stepDt).ceil() + 2000;

  while (!core.over && stats.steps < maxSteps) {
    if (core.canDrop && core.time >= nextDropAt && core.drops < maxDrops) {
      core.drop(bot(core, rng));
      nextDropAt = core.time + dropEvery;
    }
    core.step();
    stats.steps++;
    if (core.bodies.length > stats.maxBodies) stats.maxBodies = core.bodies.length;
    if (stats.firstMergeDrop == 0 && core.merges > 0) stats.firstMergeDrop = core.drops;
    core.events.clear();
    if (core.drops >= maxDrops && core.time > nextDropAt + 3) break;
  }
  stats
    ..score = core.score
    ..drops = core.drops
    ..merges = core.merges
    ..maxLevel = core.maxLevel
    ..maxChain = core.maxChain
    ..bonusCoins = core.bonusCoins
    ..finished = core.over;
  return stats;
}

int median(List<int> values) {
  if (values.isEmpty) return 0;
  final s = [...values]..sort();
  return s[s.length ~/ 2];
}
