/// Long-term goals: the evolution collection and the achievement list.
library;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/progression.dart';
import 'game_screen.dart' show achievementText;
import 'widgets.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final levels = model.balance.levels;
    // The spawnable pieces are known from the first drop; the rest must be created by merging.
    bool found(int id) => id <= model.balance.spawnWeights.length
        ? model.profile.runs > 0 || model.profile.discovered.isNotEmpty
        : model.profile.discovered.contains(id);
    final count = levels.where((l) => found(l.id)).length;
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
