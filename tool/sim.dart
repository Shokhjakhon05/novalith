// Balance probe: `dart run tool/sim.dart [games]`. Prints the bot metrics the design targets.
import 'package:novalith/core/balance.dart';
import 'package:novalith/core/bots.dart';

void main(List<String> args) {
  final games = args.isEmpty ? 200 : int.parse(args[0]);
  final scale = args.length > 1 ? double.parse(args[1]) : 1.0;
  final balance = Balance(levels: [
    for (final l in Balance.defaultLevels)
      EvoLevel(id: l.id, key: l.key, radius: l.radius * scale, coins: l.coins, rarity: l.rarity),
  ]);
  final sw = Stopwatch()..start();
  for (final entry in {'random': randomBot, 'greedy': greedyBot}.entries) {
    final scores = <int>[];
    final drops = <int>[];
    final first = <int>[];
    final levels = <int>[];
    final coins = <int>[];
    var maxBodies = 0;
    var unfinished = 0;
    var minDrops = 1 << 30;
    for (var seed = 1; seed <= games; seed++) {
      final s = simulate(entry.value, seed, balance: balance);
      scores.add(s.score);
      drops.add(s.drops);
      first.add(s.firstMergeDrop);
      levels.add(s.maxLevel);
      coins.add(s.score ~/ 100 + s.bonusCoins);
      if (s.maxBodies > maxBodies) maxBodies = s.maxBodies;
      if (!s.finished) unfinished++;
      if (s.drops < minDrops) minDrops = s.drops;
    }
    print('${entry.key}: medianScore=${median(scores)} medianDrops=${median(drops)} '
        'minDrops=$minDrops firstMerge(median)=${median(first)} medianMaxLevel=${median(levels)} '
        'bestLevel=${levels.reduce((a, b) => a > b ? a : b)} medianCoins=${median(coins)} '
        'maxBodies=$maxBodies unfinished=$unfinished');
  }
  print('elapsed ${sw.elapsedMilliseconds} ms');
}
