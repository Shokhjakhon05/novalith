/// Long-term goals: the evolution collection and the achievement list.
library;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/campaign.dart';
import '../core/progression.dart';
import 'campaign_widgets.dart';
import 'game_screen.dart' show achievementText;
import 'widgets.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final levels = model.balance.levels;
    final found = model.evoFound;
    final count = model.collectionCount;
    return GameScaffold(
      title: model.t('collection'),
      showCoins: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: count / levels.length,
                      minHeight: 8,
                      backgroundColor: const Color(0x26FFFFFF),
                      valueColor: const AlwaysStoppedAnimation(Palette.cyan),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('$count / ${levels.length}', style: ts(16, weight: 800, color: Palette.cyan)),
              ],
            ),
          ),
          // World badges: silver for a completed world, with a diamond once every master
          // challenge in it is done.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                for (final w in worlds)
                  Expanded(
                    child: _WorldBadge(
                      world: w,
                      done: worldCompleted(model.profile, w.id),
                      mastered: worldLevels(w.id).every((l) => model.profile.levels[l.id]?.master ?? false),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: levels.length,
              itemBuilder: (context, i) {
                final lv = levels[i];
                final has = found(lv.id);
                return GlassPanel(
                  padding: const EdgeInsets.all(10),
                  border: has ? Palette.rarity[lv.rarity.clamp(0, 3)].withValues(alpha: 0.7) : null,
                  child: Column(
                    children: [
                      Expanded(
                        child: FittedBox(
                          child: OrbView(level: lv.id, size: 90, locked: !has),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: has
                            ? Text(model.evoName(lv.id), style: ts(13, weight: 700))
                            : const Icon(Icons.lock_rounded, size: 18, color: Palette.faint),
                      ),
                      Text('${lv.id}', style: ts(11, weight: 700, color: Palette.faint)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldBadge extends StatelessWidget {
  const _WorldBadge({required this.world, required this.done, required this.mastered});
  final WorldDef world;
  final bool done;
  final bool mastered;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final accent = worldColor(world.id);
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? accent.withValues(alpha: 0.25) : const Color(0x14FFFFFF),
                border: Border.all(color: done ? accent : const Color(0x33FFFFFF), width: done ? 2 : 1),
              ),
              child: Icon(
                done ? Icons.public_rounded : Icons.lock_rounded,
                color: done ? accent : Palette.faint,
                size: done ? 26 : 18,
              ),
            ),
            if (mastered) const Icon(Icons.diamond_rounded, size: 16, color: Palette.cyan),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            model.worldName(world.id),
            maxLines: 1,
            style: ts(10.5, weight: 600, color: done ? Palette.dim : Palette.faint),
          ),
        ),
      ],
    );
  }
}

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final p = model.profile;
    final done = achievements.where((a) => p.achievements.contains(a.id)).length;
    return GameScaffold(
      title: model.t('achievements'),
      showCoins: false,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: achievements.length + 1,
        separatorBuilder: (context, i) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text('$done / ${achievements.length}', style: ts(16, weight: 800, color: Palette.gold)),
            );
          }
          final a = achievements[i - 1];
          final have = p.achievements.contains(a.id);
          final value = statValue(p, a.stat).clamp(0, a.target);
          return GlassPanel(
            border: have ? Palette.gold.withValues(alpha: 0.7) : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  have ? Icons.military_tech_rounded : Icons.radio_button_unchecked_rounded,
                  color: have ? Palette.gold : Palette.faint,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        achievementText(model, a),
                        style: ts(15, weight: 700, color: have ? Palette.text : Palette.dim),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value / a.target,
                          minHeight: 5,
                          backgroundColor: const Color(0x26FFFFFF),
                          valueColor: AlwaysStoppedAnimation(have ? Palette.gold : Palette.cyan),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                have ? const Icon(Icons.check_rounded, color: Palette.green) : CoinBadge(amount: a.coins, size: 14),
              ],
            ),
          );
        },
      ),
    );
  }
}
