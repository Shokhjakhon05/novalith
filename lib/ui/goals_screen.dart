/// Personal goals: three for the week and the monthly Cosmic Archive. Everything here is local
/// and optional - no timers that block play, no comparison with anyone.
library;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/progression.dart';
import 'campaign_widgets.dart';
import 'widgets.dart';

String weeklyGoalText(AppModel m, WeeklyGoal g) => switch (g.stat) {
  WeekStat.levels => m.t('wg_levels', {'n': g.target}),
  WeekStat.stars => m.t('earn_stars', {'n': g.target}),
  WeekStat.chains => m.t('wg_chains', {'n': g.target}),
  WeekStat.masters => m.t('wg_masters', {'n': g.target}),
  WeekStat.dailies => m.t('ach_daily', {'n': g.target}),
  WeekStat.merges => m.t('ach_merges', {'n': formatNumber(g.target)}),
};

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final p = model.profile;
    final goals = model.weekGoals;
    final archiveReady = !p.monthClaimed && p.monthPoints >= monthlyTarget;
    final hasTheme = p.owned.contains(monthlyTheme);
    return GameScaffold(
      title: model.t('weekly_title'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final g in goals) ...[_goal(context, model, g), const SizedBox(height: 10)],
          const SizedBox(height: 14),
          GlassPanel(
            border: Palette.gold.withValues(alpha: 0.7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: Palette.gold),
                    const SizedBox(width: 10),
                    Expanded(child: Text(model.t('archive_title'), style: ts(20, weight: 800))),
                    Text(
                      '${p.monthPoints.clamp(0, monthlyTarget)} / $monthlyTarget',
                      style: ts(15, weight: 800, color: Palette.gold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(model.t('archive_desc'), style: ts(13.5, color: Palette.dim, height: 1.3)),
                const SizedBox(height: 12),
                ProgressBar(value: p.monthPoints / monthlyTarget, color: Palette.gold),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (!hasTheme) ...[
                      const OrbView(level: 8, size: 46, theme: monthlyTheme),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(model.t(monthlyTheme), style: ts(14, weight: 700, color: Palette.gold)),
                      ),
                    ] else
                      const Spacer(),
                    if (p.monthClaimed)
                      const Icon(Icons.check_circle_rounded, color: Palette.green)
                    else if (archiveReady)
                      GameButton(
                        label: model.t('claim'),
                        primary: true,
                        color: Palette.gold,
                        compact: true,
                        onTap: model.claimMonthlyReward,
                      )
                    else
                      const CoinBadge(amount: monthlyCoins, size: 15),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _goal(BuildContext context, AppModel model, WeeklyGoal g) {
    final p = model.profile;
    final value = weeklyProgress(p, g);
    final claimed = p.weekClaimed.contains(g.id);
    final ready = !claimed && value >= g.target;
    return GlassPanel(
      border: claimed ? Palette.green.withValues(alpha: 0.6) : (ready ? Palette.gold : null),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(weeklyGoalText(model, g), style: ts(15, weight: 700, color: claimed ? Palette.dim : Palette.text)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ProgressBar(
                        value: value / g.target,
                        color: ready || claimed ? Palette.gold : Palette.cyan,
                        height: 6,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${formatNumber(value)} / ${formatNumber(g.target)}',
                      style: ts(12.5, weight: 700, color: Palette.dim),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (claimed)
            const Icon(Icons.check_circle_rounded, color: Palette.green)
          else if (ready)
            GameButton(
              label: model.t('claim'),
              primary: true,
              color: Palette.gold,
              compact: true,
              onTap: () => model.claimWeeklyGoal(g.id),
            )
          else
            CoinBadge(amount: g.coins, size: 14),
        ],
      ),
    );
  }
}
