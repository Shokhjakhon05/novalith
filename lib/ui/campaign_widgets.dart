/// Words and small widgets the campaign screens share: goal texts, star rows, level tags.
library;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/campaign.dart';
import 'widgets.dart';

/// "2-7": world and position, the way a level is named everywhere.
String levelTag(LevelDef l) => '${l.world}-${l.index}';

Color worldColor(int world) => Color(0xFF000000 | worldDef(world).accent);

String goalText(AppModel m, LevelDef l, Goal g, {bool master = false}) => switch (g.type) {
  GoalType.score => m.t('ach_score', {'n': formatNumber(master ? l.master.score : g.target)}),
  GoalType.evolve => m.t('ach_evo', {'name': m.evoName(g.target)}),
  GoalType.chain => m.t('ach_chain', {'n': g.target}),
  GoalType.merges => m.t('ach_merges', {'n': g.target}),
  GoalType.perfects => m.t('ach_perfect', {'n': g.target}),
  GoalType.survive => m.t('goal_survive', {'n': master ? l.master.drops : l.drops}),
};

/// Everything the player has to do, one line per requirement.
List<String> goalLines(AppModel m, LevelDef l, {bool master = false}) => [
  for (final g in l.goals) goalText(m, l, g, master: master),
  if (master && l.byScore && !l.goals.any((g) => g.type == GoalType.score))
    m.t('ach_score', {'n': formatNumber(l.master.score)}),
];

/// What the second ([star] = 2) or third star asks for.
String starText(AppModel m, LevelDef l, int star) {
  final v = star == 2 ? l.star2 : l.star3;
  return l.byScore ? m.t('points_n', {'n': formatNumber(v)}) : m.t('in_drops', {'n': v});
}

class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 16, this.color = Palette.gold});
  final int stars;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 3; i++)
          Icon(
            i <= stars ? Icons.star_rounded : Icons.star_border_rounded,
            size: size,
            color: i <= stars ? color : Palette.faint,
          ),
      ],
    );
  }
}

/// A slim progress bar in the game's style.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.color = Palette.cyan, this.height = 8});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: const Color(0x26FFFFFF),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
