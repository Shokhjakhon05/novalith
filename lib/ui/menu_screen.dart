/// Main menu: one big PLAY, the daily challenge, and the long-term goals a tap away.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/campaign.dart';
import '../core/campaign_data.dart';
import '../core/daily.dart';
import '../core/progression.dart';
import 'campaign_widgets.dart';
import 'collection_screen.dart';
import 'game_screen.dart';
import 'goals_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'widgets.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(seconds: 5))
    ..repeat();
  bool _offeredReward = false;
  bool _offeredGift = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeOfferReward();
  }

  /// Returning players are greeted with today's reward - but only on the menu itself, never
  /// on top of a game in progress, and a first launch goes straight to play.
  void _maybeOfferReward() {
    final model = AppScope.of(context);
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    // The thank-you for players from before the campaign comes first, once.
    if (model.profile.gift > 0 && !_offeredGift) {
      _offeredGift = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          showDialog<void>(
            context: context,
            barrierColor: const Color(0xCC050816),
            builder: (_) => const _GiftDialog(),
          );
        }
      });
      return;
    }
    if (_offeredReward || model.profile.runs == 0) return;
    if (model.rewardStatus.state != RewardState.available) return;
    _offeredReward = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) _showReward();
    });
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (context, a, b) => screen,
        transitionsBuilder: (context, a, b, child) => FadeTransition(opacity: a, child: child),
      ),
    );
    if (mounted) _maybeOfferReward();
  }

  void _showReward() {
    showDialog<void>(context: context, barrierColor: const Color(0xCC050816), builder: (_) => const _RewardDialog());
  }

  void _showDaily() {
    final model = AppScope.read(context);
    model.analytics.log('daily_opened');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xCC050816),
      isScrollControlled: true,
      builder: (sheet) => _DailySheet(
        onStart: () {
          Navigator.of(sheet).pop();
          _open(GameScreen(daily: model.todayChallenge));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final p = model.profile;
    final reward = model.rewardStatus.state == RewardState.available;
    final current = model.nextCampaignLevel;
    return Scaffold(
      backgroundColor: Palette.ink,
      body: SpaceBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          // The player's own rank (XP), shown as a badge so it is not confused
                          // with campaign levels.
                          GlassPanel(
                            radius: 16,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bolt_rounded, size: 18, color: Palette.violet),
                                const SizedBox(width: 2),
                                Text('${p.level}', style: ts(15, weight: 800, color: Palette.violet)),
                              ],
                            ),
                          ),
                          const Spacer(),
                          CoinBadge(amount: p.coins),
                          const SizedBox(width: 12),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              RoundButton(
                                icon: Icons.card_giftcard_rounded,
                                semantic: model.t('reward_title'),
                                onTap: _showReward,
                              ),
                              if (reward)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: Palette.rose,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Palette.ink, width: 2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const SizedBox(height: 12),
                          AnimatedBuilder(
                            animation: _float,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(0, math.sin(_float.value * math.pi * 2) * 7),
                              child: child,
                            ),
                            child: Image.asset(
                              'assets/brand/logo.png',
                              width: (box.maxHeight * 0.17).clamp(72.0, 150.0),
                              height: (box.maxHeight * 0.17).clamp(72.0, 150.0),
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (context, error, stack) => const OrbView(level: 8, size: 180),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ShaderMask(
                              shaderCallback: (rect) =>
                                  const LinearGradient(colors: [Colors.white, Palette.cyan, Palette.violet])
                                      .createShader(rect),
                              child: Text('NOVALITH', style: ts(40, weight: 800, spacing: 5)),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Where the player is and what comes next: the campaign is the main road.
                            _ProgressCard(current: current, onTap: () => _open(const MapScreen())),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 68,
                              child: GameButton(
                                label: model
                                    .t(current == null ? 'map' : (p.levelsDone == 0 ? 'play' : 'resume'))
                                    .toUpperCase(),
                                icon: current == null ? Icons.map_rounded : Icons.play_arrow_rounded,
                                primary: true,
                                onTap: () => _open(current == null ? const MapScreen() : GameScreen(level: current)),
                                trailing: current == null
                                    ? null
                                    : Text(levelTag(current), style: ts(17, weight: 800, color: Palette.ink)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: GameButton(
                                    label: model.t('daily'),
                                    icon: Icons.flag_rounded,
                                    color: Palette.gold,
                                    compact: true,
                                    onTap: _showDaily,
                                    trailing: model.dailyDoneToday
                                        ? const Icon(Icons.check_circle_rounded, color: Palette.green, size: 18)
                                        : Container(
                                            width: 9,
                                            height: 9,
                                            decoration: const BoxDecoration(
                                              color: Palette.gold,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GameButton(
                                    label: model.t('endless'),
                                    icon: Icons.all_inclusive_rounded,
                                    compact: true,
                                    onTap: () => _open(const GameScreen()),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _GoalsStrip(onTap: () => _open(const GoalsScreen())),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _Tile(
                                  icon: Icons.storefront_rounded,
                                  label: model.t('shop'),
                                  onTap: () {
                                    model.analytics.log('shop_opened');
                                    _open(const ShopScreen());
                                  },
                                ),
                                const SizedBox(width: 10),
                                _Tile(
                                  icon: Icons.auto_awesome_mosaic_rounded,
                                  label: model.t('collection'),
                                  note: '${model.collectionCount}/${model.balance.maxLevel}',
                                  onTap: () => _open(const CollectionScreen()),
                                ),
                                const SizedBox(width: 10),
                                _Tile(
                                  icon: Icons.military_tech_rounded,
                                  label: model.t('achievements'),
                                  note: '${p.achievements.length}/${achievements.length}',
                                  onTap: () => _open(const AchievementsScreen()),
                                ),
                                const SizedBox(width: 10),
                                _Tile(
                                  icon: Icons.settings_rounded,
                                  label: model.t('settings'),
                                  onTap: () => _open(const SettingsScreen()),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap, this.note});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Progress shown next to the icon, e.g. "7/12".
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: GlassPanel(
            radius: 18,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Palette.cyan, size: note == null ? 26 : 20),
                    if (note != null) ...[
                      const SizedBox(width: 4),
                      Text(note!, style: ts(11.5, weight: 800, color: Palette.cyan)),
                    ],
                  ],
                ),
                SizedBox(height: note == null ? 6 : 9),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: ts(11.5, weight: 600, color: Palette.dim)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// World, level and stars at a glance; a tap opens the map.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.current, required this.onTap});
  final LevelDef? current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final p = model.profile;
    final world = (current ?? campaignLevels.last).world;
    final levels = worldLevels(world);
    final done = worldLevelsDone(p, world);
    final accent = worldColor(world);
    return Semantics(
      button: true,
      label: model.t('map'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassPanel(
          border: accent.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              OrbView(level: worldDef(world).emblem, size: 56),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '${model.t('world_n', {'n': world})} · ${model.worldName(world)}'.toUpperCase(),
                        style: ts(13, weight: 800, color: accent, spacing: 0.8),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              current == null
                                  ? model.t('campaign_done')
                                  : model.t('level_of', {'n': current!.index, 'm': levels.length}),
                              style: ts(17, weight: 700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.star_rounded, size: 16, color: Palette.gold),
                        const SizedBox(width: 3),
                        Text(
                          '${worldStars(p, world)} / ${levels.length * 3}',
                          style: ts(13.5, weight: 800, color: Palette.gold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ProgressBar(value: done / levels.length, color: accent, height: 6),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(model.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: Palette.dim),
            ],
          ),
        ),
      ),
    );
  }
}

/// This week's goals in one line; a dot says a reward is waiting.
class _GoalsStrip extends StatelessWidget {
  const _GoalsStrip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final p = model.profile;
    final goals = model.weekGoals;
    final done = goals.where((g) => weeklyProgress(p, g) >= g.target).length;
    return Semantics(
      button: true,
      label: model.t('weekly_title'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassPanel(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.checklist_rounded, color: Palette.violet, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  model.t('weekly_title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(14.5, weight: 700, color: Palette.dim),
                ),
              ),
              Text('$done / ${goals.length}', style: ts(14.5, weight: 800, color: Palette.violet)),
              if (model.goalsClaimable) ...[
                const SizedBox(width: 8),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: Palette.rose, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One-time thank-you for players who were here before the campaign.
class _GiftDialog extends StatelessWidget {
  const _GiftDialog();

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.transparent,
            child: GlassPanel(
              solid: true,
              radius: 26,
              border: Palette.gold,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(model.t('gift_title'), style: ts(24, weight: 800), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    model.t('gift_text'),
                    style: ts(15, color: Palette.dim, height: 1.3),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Center(child: CoinBadge(amount: model.profile.gift, size: 26)),
                  const SizedBox(height: 18),
                  GameButton(
                    label: model.t('claim'),
                    primary: true,
                    color: Palette.gold,
                    onTap: () {
                      model.takeGift();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DailySheet extends StatelessWidget {
  const _DailySheet({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final d = model.todayChallenge;
    final done = model.dailyDoneToday;
    final best = model.dailyBestToday;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xF0140F33), borderRadius: BorderRadius.circular(26)),
          child: GlassPanel(
            border: done ? Palette.green : Palette.gold,
            radius: 26,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_rounded, color: Palette.gold),
                    const SizedBox(width: 10),
                    Expanded(child: Text(model.t('daily_title'), style: ts(22, weight: 800))),
                    if (done) const Icon(Icons.check_circle_rounded, color: Palette.green),
                  ],
                ),
                const SizedBox(height: 14),
                Text(dailyGoalText(model, d), style: ts(18, weight: 600, height: 1.3)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (best > 0)
                      Expanded(
                        child: Text(model.t('your_best', {'n': formatNumber(best)}), style: ts(14, color: Palette.dim)),
                      ),
                    if (best == 0) const Spacer(),
                    if (!done) CoinBadge(amount: model.balance.dailyCompleteCoins),
                    if (done) Text(model.t('completed'), style: ts(14, weight: 700, color: Palette.green)),
                  ],
                ),
                const SizedBox(height: 18),
                GameButton(
                  label: model.t(best > 0 ? 'play_again' : 'start'),
                  icon: Icons.play_arrow_rounded,
                  primary: true,
                  onTap: onStart,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RewardDialog extends StatelessWidget {
  const _RewardDialog();

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final status = model.rewardStatus;
    final available = status.state == RewardState.available;
    final rewards = model.balance.dailyRewardCoins;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: const Color(0xF0140F33),
            borderRadius: BorderRadius.circular(26),
            child: GlassPanel(
              radius: 26,
              border: Palette.gold,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(model.t('reward_title'), style: ts(24, weight: 800), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < rewards.length; i++)
                        _RewardDay(
                          label: model.t('day_n', {'n': i + 1}),
                          coins: rewards[i],
                          // Claimed days are ticked; today's is highlighted.
                          claimed: available ? i < status.day : i < (status.day == 0 ? rewards.length : status.day),
                          today: available && i == status.day,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (available)
                    GameButton(
                      label: model.t('claim'),
                      primary: true,
                      color: Palette.gold,
                      onTap: () {
                        model.claimReward();
                        Navigator.of(context).pop();
                      },
                    )
                  else ...[
                    Text(
                      model.t('come_back'),
                      style: ts(15, color: Palette.dim),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    GameButton(label: 'OK', compact: true, onTap: () => Navigator.of(context).pop()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RewardDay extends StatelessWidget {
  const _RewardDay({required this.label, required this.coins, required this.claimed, required this.today});
  final String label;
  final int coins;
  final bool claimed;
  final bool today;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: today ? const Color(0x33FFD65A) : const Color(0x14FFFFFF),
        border: Border.all(color: today ? Palette.gold : const Color(0x33FFFFFF), width: today ? 2 : 1),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: ts(11.5, weight: 600, color: Palette.dim)),
          ),
          const SizedBox(height: 6),
          claimed ? const Icon(Icons.check_circle_rounded, color: Palette.green, size: 24) : const CoinIcon(size: 24),
          const SizedBox(height: 4),
          Text('$coins', style: ts(15, weight: 800, color: claimed ? Palette.faint : Palette.gold)),
        ],
      ),
    );
  }
}
