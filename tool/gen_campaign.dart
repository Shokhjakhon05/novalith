// ignore_for_file: avoid_print
// Builds lib/core/campaign_data.dart from the design table below:
//
//   dart run tool/gen_campaign.dart && dart format lib/core/campaign_data.dart
//
// A row says what a level asks for and under which conditions. The numbers a player is held
// to (drop limit, star thresholds, master target) are not typed in by hand: the validation bot
// plays every candidate piece sequence, and the level ships only with sequences it finished,
// with a first star below what it scored and a third star it actually reached. Adding a level
// means adding a row. Results are cached per row in tool/.campaign_cache.json.
import 'dart:convert';
import 'dart:io';

import 'package:novalith/core/bots.dart';
import 'package:novalith/core/campaign.dart';
import 'package:novalith/core/game_core.dart';
import 'package:novalith/core/rng.dart';

class Row {
  Row(this.goals, {this.drops = 0, this.spawn = 0, this.line = 0, this.start = '', this.ease = 1, this.cap = 60});
  final List<Goal> goals;

  /// Drops of a score / survival level. Levels that end at the goal get theirs from the bot.
  final int drops;
  final int spawn;
  final int line;
  final String start;

  /// 0 gentle, 1 normal, 2 demanding: how close the first star sits to the bot's result.
  final int ease;
  final int cap;

  String get signature =>
      'v5|${goals.map((g) => '${g.type.name}${g.target}').join('+')}|$drops|$spawn|$line|$start|$ease|$cap';
}

Goal get s => const Goal(GoalType.score, 0);
Goal get v => const Goal(GoalType.survive, 0);
Goal e(int n) => Goal(GoalType.evolve, n);
Goal c(int n) => Goal(GoalType.chain, n);
Goal m(int n) => Goal(GoalType.merges, n);
Goal p(int n) => Goal(GoalType.perfects, n);

const Map<String, List<List<int>>> starts = {
  '': [],
  // Touching bodies of falling size: one right merge sets off a chain.
  'ladder3': [
    [4, 40],
    [3, 108],
    [2, 162],
  ],
  'ladder4': [
    [5, 48],
    [4, 131],
    [3, 199],
    [2, 253],
  ],
  'ladder5': [
    [6, 56],
    [5, 155],
    [4, 238],
    [3, 306],
  ],
  'ladder6': [
    [7, 64],
    [6, 180],
    [5, 280],
  ],
  // Mismatched leftovers that have to be cleaned up.
  'rubble': [
    [2, 26],
    [1, 68],
    [3, 112],
    [1, 160],
    [2, 202],
    [4, 262],
    [1, 318],
  ],
  'rubble2': [
    [2, 26],
    [1, 68],
    [3, 112],
    [1, 160],
    [2, 202],
    [4, 262],
    [1, 318],
    [3, 40],
    [2, 100],
    [4, 170],
    [3, 240],
    [2, 300],
  ],
  // One big body in the way.
  'obstacle6': [
    [6, 170],
  ],
  'obstacle7': [
    [7, 170],
  ],
  'obstacle8': [
    [8, 170],
  ],
  // What an earlier age left behind: finish the job.
  'legacy8': [
    [8, 72],
    [7, 205],
  ],
  'legacy9': [
    [9, 80],
    [8, 232],
  ],
  'legacy10': [
    [10, 88],
    [9, 252],
  ],
  'legacy11': [
    [11, 96],
    [10, 250],
  ],
  'lone8': [
    [8, 72],
  ],
  'lone11': [
    [11, 96],
  ],
  'triad': [
    [11, 96],
    [10, 250],
    [9, 180],
  ],
};

/// Twenty rows per world, in play order; the last row of a world is its Cosmic Trial.
final List<List<Row>> design = [
  // 1. Origin: the basics, one idea at a time.
  [
    Row([m(3)], ease: 0, spawn: 1),
    Row([e(3)], ease: 0, spawn: 1),
    Row([s], drops: 12, ease: 0, spawn: 1),
    Row([e(4)], ease: 0),
    Row([m(8)], ease: 0),
    Row([c(2)], ease: 0),
    Row([s], drops: 18, ease: 0),
    Row([e(5)], ease: 0),
    Row([c(3)], ease: 0, start: 'ladder3'),
    Row([p(2)], ease: 0),
    Row([s], drops: 24),
    Row([m(14), c(2)]),
    Row([p(4)]),
    Row([e(6)], ease: 0),
    Row([m(20)]),
    Row([s], drops: 30),
    Row([c(3)], ease: 0, cap: 40),
    Row([s, e(5)], drops: 25),
    Row([m(12)], ease: 0, start: 'ladder4'),
    Row([s, e(6)], drops: 40),
  ],
  // 2. Nebula: boards that are not empty, survival, a heavier mix.
  [
    Row([s], drops: 30, ease: 0),
    Row([e(6)]),
    Row([m(15)], ease: 0, start: 'rubble'),
    Row([c(3)]),
    Row([v], drops: 30, ease: 0, start: 'rubble2'),
    Row([p(5)]),
    Row([s], drops: 30, ease: 0, spawn: 2),
    Row([e(7)], ease: 0, spawn: 2),
    Row([e(7)], ease: 0, start: 'ladder5'),
    Row([v], drops: 35, start: 'rubble2', spawn: 2),
    Row([s, c(3)], drops: 35),
    Row([m(25)], start: 'rubble'),
    Row([e(7)]),
    Row([p(7)]),
    Row([s], drops: 40, spawn: 2),
    Row([c(4)], ease: 0, start: 'ladder4', cap: 50),
    Row([v, s], drops: 40, start: 'rubble2'),
    Row([e(7), c(3)], start: 'rubble'),
    Row([s], drops: 30, ease: 0, spawn: 1, start: 'ladder4'),
    Row([v, e(7)], drops: 50, start: 'rubble2', spawn: 2),
  ],
  // 3. Stellar: less room, six kinds of pieces, things in the way.
  [
    Row([s], drops: 40, ease: 0),
    Row([e(7)], ease: 0, spawn: 3),
    Row([s], drops: 35, ease: 0, line: 30),
    Row([c(4)]),
    Row([e(8)], ease: 0, spawn: 4),
    Row([m(30)], line: 30),
    Row([v], drops: 40, line: 40),
    Row([s], drops: 40, ease: 0, start: 'obstacle7'),
    Row([e(8)], ease: 0, start: 'ladder6'),
    Row([p(8)], spawn: 3),
    Row([s, e(7)], drops: 45, spawn: 3),
    Row([c(3), m(25)], line: 30),
    Row([v], drops: 45, spawn: 3, start: 'obstacle6'),
    Row([e(8)], spawn: 4),
    Row([s], drops: 50, line: 40, spawn: 2),
    Row([c(4)], ease: 0, start: 'ladder5'),
    Row([e(8), p(6)], spawn: 4),
    Row([v, s], drops: 50, line: 40, spawn: 3),
    Row([s], drops: 35, ease: 0, spawn: 1, start: 'ladder5'),
    Row([s, e(8)], drops: 60, line: 30, spawn: 3),
  ],
  // 4. Galactic: big pieces rain down, old giants wait to be finished.
  [
    Row([s], drops: 40, ease: 0, spawn: 3),
    Row([e(8)], ease: 0, spawn: 5),
    Row([s], drops: 26, ease: 0, spawn: 5),
    Row([c(3)], spawn: 5),
    Row([e(9)], ease: 0, spawn: 5),
    Row([v], drops: 20, spawn: 5),
    Row([m(18)], spawn: 5),
    Row([e(9)], ease: 0, spawn: 3, start: 'legacy8'),
    Row([e(10)], ease: 0, spawn: 5, start: 'legacy9'),
    Row([p(6)], spawn: 5),
    Row([s, c(3)], drops: 45, spawn: 3, line: 30),
    Row([v], drops: 45, spawn: 4, line: 20),
    Row([e(9), c(3)], spawn: 5),
    Row([s], drops: 28, spawn: 5, start: 'obstacle8'),
    Row([e(10)], spawn: 6, start: 'legacy8'),
    Row([c(4)], spawn: 3),
    Row([v, s], drops: 22, spawn: 5, line: 20),
    Row([m(35), p(10)], spawn: 2, line: 30),
    Row([s], drops: 40, ease: 0, spawn: 1, start: 'ladder5'),
    Row([s, e(10)], drops: 35, spawn: 6, start: 'lone8'),
  ],
  // 5. Singularity: titans only, the line closes in, the chain is completed.
  [
    Row([s], drops: 30, ease: 0, spawn: 5, line: 20),
    Row([e(9)], ease: 0, spawn: 6),
    Row([s], drops: 20, ease: 0, spawn: 6),
    Row([e(10)], ease: 0, spawn: 6, start: 'obstacle8'),
    Row([c(4)], start: 'ladder5', line: 20),
    Row([v], drops: 18, spawn: 6),
    Row([e(11)], ease: 0, spawn: 7, cap: 30),
    Row([s, e(10)], drops: 20, spawn: 7, ease: 0),
    Row([e(11)], ease: 0, spawn: 7, start: 'legacy10'),
    Row([p(6)], spawn: 6),
    Row([v, s], drops: 20, spawn: 6),
    Row([e(10), p(4)], spawn: 6, start: 'obstacle8'),
    Row([s], drops: 50, ease: 2, spawn: 4, line: 40),
    Row([c(4)], spawn: 3, line: 30),
    Row([e(12)], ease: 0, spawn: 7, start: 'legacy11', cap: 30),
    Row([m(16)], spawn: 6),
    Row([v], drops: 50, ease: 2, spawn: 4, line: 40),
    Row([e(11)], spawn: 7, line: 20, cap: 30),
    Row([s], drops: 30, ease: 0, spawn: 1, start: 'ladder5'),
    Row([s, e(12)], drops: 20, ease: 0, spawn: 7, start: 'legacy11'),
  ],
];

const int candidates = 16;
const List<double> paces = [0.75, 1.0];

int nice(num v) => v < 1000 ? v ~/ 10 * 10 : v ~/ 50 * 50;

class Played {
  Played(this.ok, this.score, this.drops);
  final bool ok;
  final int score;
  final int drops;
}

/// One bot game of [row] on [seed]. For score levels `ok` covers the goals other than score.
Played play(Row row, int id, int seed, double pace, bool master, int masterLine) {
  final byScore = row.goals.any((g) => g.type == GoalType.score || g.type == GoalType.survive);
  final limit = byScore ? row.drops : row.cap;
  final def = LevelDef(
    id: id,
    goals: row.goals,
    drops: limit,
    star2: 0,
    star3: 0,
    seeds: [seed],
    master: MasterDef(drops: limit, score: 0, seeds: [seed], line: masterLine),
    spawn: row.spawn,
    line: row.line,
    start: starts[row.start]!,
  );
  final core = playLevel(def, greedyBot, master: master, dropEvery: pace);
  final ok = byScore
      ? row.goals.where((g) => g.type != GoalType.score).every((g) => def.goalMet(core, g))
      : core.endReason == EndReason.completed;
  return Played(ok, core.score, core.drops);
}

class SeedStat {
  SeedStat(this.seed, this.ok, this.lo, this.hi);
  final int seed;
  final bool ok;

  /// Worst and best over the paces: score for score levels, drops used otherwise.
  final int lo;
  final int hi;
}

List<SeedStat> survey(Row row, int id, bool master, bool byScore, [int line = masterLine]) {
  final out = <SeedStat>[];
  for (var k = 0; k < candidates; k++) {
    final seed = hashSeed('novalith|campaign|$id|${master ? 'm' : 'n'}|$k') & 0x7FFFFFFF;
    final runs = [for (final pace in paces) play(row, id, seed, pace, master, line)];
    final ok = runs.every((r) => r.ok);
    final values = [for (final r in runs) byScore ? r.score : r.drops]..sort();
    out.add(SeedStat(seed, ok, byScore ? values.first : values.last, byScore ? values.last : values.first));
  }
  return out;
}

/// Returns the level as a JSON-able map, or throws a description of why the row cannot ship.
Map<String, dynamic> build(Row row, int id) {
  final byScore = row.goals.any((g) => g.type == GoalType.score || g.type == GoalType.survive);
  final hasScore = row.goals.any((g) => g.type == GoalType.score);
  final normal = survey(row, id, false, byScore).where((x) => x.ok).toList();
  // A master challenge normally lowers the line; where even the bot cannot live with that, the
  // challenge keeps the level's own line and is hard through its tighter target alone.
  var hardLine = masterLine;
  var hard = survey(row, id, true, byScore).where((x) => x.ok).toList();
  if (hard.length < 3) {
    hardLine = 0;
    hard = survey(row, id, true, byScore, 0).where((x) => x.ok).toList();
  }
  // Last resort: the level's own proven sequences, with only the target tightened.
  if (hard.length < 3) hard = List.of(normal);
  if (normal.length < 4) throw 'only ${normal.length}/$candidates sequences are finished by the bot';
  if (hard.length < 3) throw 'master: only ${hard.length}/$candidates sequences are finished by the bot';

  late int drops, star2, star3, target, masterDrops, masterScore;
  late List<SeedStat> pick, pickHard;
  if (byScore) {
    normal.sort((a, b) => a.lo.compareTo(b.lo));
    final from = ((normal.length - 4) * 0.6).round();
    pick = normal.sublist(from, from + 4);
    final base = pick.first.lo;
    final top = pick.map((x) => x.hi).reduce((a, b) => a > b ? a : b);
    target = nice(base * const [0.6, 0.75, 0.88][row.ease]);
    star3 = nice(top * 0.98);
    star2 = nice(((hasScore ? target : base * 0.7) + star3) / 2);
    drops = row.drops;
    hard.sort((a, b) => b.lo.compareTo(a.lo));
    pickHard = hard.take(4).toList();
    masterScore = nice(pickHard.last.lo * 0.95);
    masterDrops = drops;
    if (!(target < star2 && star2 < star3)) throw 'score stars collapse: $target / $star2 / $star3';
    if (hasScore && masterScore <= target) throw 'master score $masterScore is not above the first star $target';
  } else {
    normal.sort((a, b) => a.lo.compareTo(b.lo));
    final from = ((normal.length - 4) * 0.5).round();
    pick = normal.sublist(from, from + 4);
    final worst = pick.last.lo;
    final best = pick.map((x) => x.hi).reduce((a, b) => a < b ? a : b);
    target = 0;
    star3 = best + (row.ease == 0 ? 1 : 0);
    star2 = ((star3 + worst) / 2).round();
    // Two stars must be visibly easier than three, not one drop apart.
    if (star2 < star3 + 2) star2 = star3 + 2;
    drops = (worst * const [1.5, 1.3, 1.18][row.ease]).ceil() + 1;
    hard.sort((a, b) => a.lo.compareTo(b.lo));
    pickHard = hard.take(4).toList();
    masterDrops = pickHard.last.lo + 1;
    if (masterDrops < star3) masterDrops = star3;
    if (drops <= star2) drops = star2 + 2;
    if (drops <= masterDrops) drops = masterDrops + 2;
    masterScore = 0;
  }
  return {
    'sig': row.signature,
    'target': target,
    'drops': drops,
    'star2': star2,
    'star3': star3,
    'seeds': [for (final x in pick) x.seed],
    'masterDrops': masterDrops,
    'masterScore': masterScore,
    'masterSeeds': [for (final x in pickHard) x.seed],
    'masterLine': hardLine,
  };
}

void main(List<String> args) {
  final cacheFile = File('tool/.campaign_cache.json');
  final Map<String, dynamic> cache = cacheFile.existsSync()
      ? jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>
      : {};
  final out = StringBuffer()
    ..writeln('// GENERATED by tool/gen_campaign.dart from its design table. Do not edit by hand:')
    ..writeln('// change the table and run the tool again, so every number stays bot-verified.')
    ..writeln("import 'campaign.dart';")
    ..writeln()
    ..writeln('const List<LevelDef> campaignLevels = [');
  var failed = 0;
  final sw = Stopwatch()..start();
  for (var w = 0; w < design.length; w++) {
    for (var i = 0; i < design[w].length; i++) {
      final row = design[w][i];
      final id = (w + 1) * 100 + i + 1;
      var r = cache['$id'] as Map<String, dynamic>?;
      if (r == null || r['sig'] != row.signature) {
        try {
          r = build(row, id);
          cache['$id'] = r;
          cacheFile.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(cache));
          print(
            '$id ok  ${row.signature}  -> drops ${r['drops']} target ${r['target']} '
            '** ${r['star2']} *** ${r['star3']} master ${r['masterDrops']}/${r['masterScore']} '
            '[${sw.elapsed.inSeconds}s]',
          );
        } catch (err) {
          failed++;
          print('$id FAILED  ${row.signature}: $err');
          continue;
        }
      }
      final goals = row.goals
          .map((g) => 'Goal(GoalType.${g.type.name}, ${g.type == GoalType.score ? r!['target'] : g.target})')
          .join(', ');
      out
        ..writeln('  LevelDef(')
        ..writeln('    id: $id,')
        ..writeln('    goals: [$goals],')
        ..writeln('    drops: ${r['drops']},')
        ..writeln('    star2: ${r['star2']},')
        ..writeln('    star3: ${r['star3']},')
        ..writeln('    seeds: ${r['seeds']},')
        ..writeln(
          '    master: MasterDef(drops: ${r['masterDrops']}, score: ${r['masterScore']}, '
          'seeds: ${r['masterSeeds']}${(r['masterLine'] ?? masterLine) == masterLine ? '' : ', line: ${r['masterLine']}'}),',
        );
      if (row.spawn != 0) out.writeln('    spawn: ${row.spawn},');
      if (row.line != 0) out.writeln('    line: ${row.line},');
      if (row.start.isNotEmpty) out.writeln('    start: ${starts[row.start]},');
      if (i == design[w].length - 1) out.writeln('    trial: true,');
      out.writeln('  ),');
    }
  }
  out.writeln('];');
  if (failed > 0) {
    print('$failed rows cannot ship; campaign_data.dart was left untouched.');
    exit(1);
  }
  File('lib/core/campaign_data.dart').writeAsStringSync(out.toString());
  print('Wrote ${design.fold(0, (a, b) => a + b.length)} levels in ${sw.elapsed.inSeconds}s.');
}
