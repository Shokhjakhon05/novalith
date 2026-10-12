/// The play screen: board, HUD, onboarding hints, pause, rewarded continue and the result card.
library;

import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/ad_policy.dart';
import '../core/campaign.dart';
import '../core/daily.dart';
import '../core/game_core.dart';
import '../core/progression.dart';
import '../game/board_game.dart';
import '../services/feedback.dart';
import 'campaign_widgets.dart';
import 'widgets.dart';

enum _Phase { intro, playing, paused, continuePrompt, results }

String achievementText(AppModel m, Achievement a) => switch (a.stat) {
  Stat.totalMerges => m.t('ach_merges', {'n': formatNumber(a.target)}),
  Stat.maxChain => m.t('ach_chain', {'n': a.target}),
  Stat.maxLevel => m.t('ach_evo', {'name': m.evoName(a.target)}),
  Stat.bestScore => m.t('ach_score', {'n': formatNumber(a.target)}),
  Stat.runs => m.t('ach_runs', {'n': a.target}),
  Stat.dailyCompleted => m.t('ach_daily', {'n': a.target}),
  Stat.bigBangs => m.t('ach_bigbang'),
  Stat.perfects => m.t('ach_perfect', {'n': a.target}),
  Stat.campaignLevels => m.t('wg_levels', {'n': a.target}),
  Stat.stars => m.t('earn_stars', {'n': a.target}),
  Stat.masters => m.t('wg_masters', {'n': a.target}),
  Stat.worlds => m.t('ach_worlds', {'n': a.target}),
  Stat.weeklies => m.t('ach_weekly', {'n': a.target}),
};

String dailyGoalText(AppModel m, DailyChallenge d) => switch (d.type) {
  DailyType.score => m.t('goal_score', {'n': formatNumber(d.target), 'd': d.dropLimit}),
  DailyType.evolution => m.t('goal_evo', {'name': m.evoName(d.target), 'd': d.dropLimit}),
  DailyType.chain => m.t('goal_chain', {'n': d.target, 'd': d.dropLimit}),
};

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.daily, this.level, this.master = false, this.exitLabel = 'home'});

  /// Null (and no [level]) = classic endless mode.
  final DailyChallenge? daily;

  /// A campaign level to play; "next level" moves on from it without leaving the screen.
  final LevelDef? level;

  /// Play the level's master challenge.
  final bool master;

  /// Localisation key of the button that leaves the screen.
  final String exitLabel;

  /// The debug button is shown only in debug builds; tests that render store screenshots
  /// switch it off as well.
  static bool debugTools = kDebugMode;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  /// Makes run ids unique within a session even if the clock does not advance.
  static int _runCounter = 0;

  late AppModel _model;
  BoardGame? _game;
  String _runId = '';
  _Phase _phase = _Phase.playing;
  RunOutcome? _outcome;
  int _doubled = 0;
  bool _busy = false;
  int _tutorial = 3;
  int? _pointer;
  String _banner = '';
  Timer? _bannerTimer;
  Timer? _continueTimer;
  int _continueLeft = 0;
  final RewardGate _gate = RewardGate();
  LevelDef? _level;
  bool _master = false;

  bool get _classic => widget.daily == null && _level == null;

  BoardGame get game => _game!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model = AppScope.of(context);
    if (_game == null) {
      _level = widget.level;
      _master = widget.master;
      _game = BoardGame(core: _newCore(resume: true), model: _model)
        ..onEvent = _onEvent
        ..onRunEnded = _onRunEnded;
      game.startRun(game.core);
      _tutorial = _model.profile.tutorialDone ? 3 : 0;
      // A first-time player is told what the game is about before anything moves.
      if (_tutorial == 0) {
        _phase = _Phase.intro;
        game.paused = true;
      }
      _announceLevel();
    }
  }

  /// Says what the level asks for as it starts (the goal also stays in the HUD).
  void _announceLevel() {
    final level = _level;
    game.backgroundOverride = level == null ? null : worldDef(level.world).background;
    if (level == null || _tutorial < 3) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showBanner(goalLines(_model, level, master: _master).join(' · '));
    });
  }

  GameCore _newCore({bool resume = false}) {
    final level = _level;
    if (level != null) {
      _runId = 'l-${level.id}-${_master ? 'm' : 'n'}-${_model.now.microsecondsSinceEpoch}-${_runCounter++}';
      return _model.startLevel(level, master: _master);
    }
    final daily = widget.daily;
    if (daily != null) {
      _runId = 'd-${daily.dateKey}-${_model.now.microsecondsSinceEpoch}-${_runCounter++}';
      _model.analytics.log('daily_started', {'date': daily.dateKey});
      return daily.createRun(balance: _model.balance);
    }
    final saved = resume ? _model.takeActiveRun() : null;
    final core = saved ?? GameCore(balance: _model.balance, seed: _model.now.microsecondsSinceEpoch & 0x7FFFFFFF);
    _runId = 'c-${core.seed}-${core.drops == 0 ? '${_model.now.millisecondsSinceEpoch}-${_runCounter++}' : 'resumed'}';
    _model.analytics.log('game_started', {'resumed': saved != null});
    return core;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bannerTimer?.cancel();
    _continueTimer?.cancel();
    _game?.disposeResources();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    // Going to the background: freeze the board and keep the run safe on disk.
    if (_phase == _Phase.playing) _setPhase(_Phase.paused);
    _stashRun();
  }

  void _stashRun() {
    if (_classic && _phase != _Phase.results && !game.core.over) {
      _model.storeActiveRun(game.core);
    }
  }

  void _setPhase(_Phase phase) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      game.paused = phase != _Phase.playing;
    });
  }

  // --- Simulation events ---

  void _onEvent(GameEvent e) {
    if (_tutorial == 1 && e.type == EventType.drop) setState(() => _tutorial = 2);
    // Autosave every few drops, so even a killed process loses at most a moment of play.
    if (e.type == EventType.drop && game.core.drops % 5 == 0) _stashRun();
    if (e.type == EventType.merge) {
      // A level that is judged by drops is over the moment its goal is reached.
      final level = _level;
      if (level != null && !level.byScore && !game.core.over && level.passed(game.core, master: _master)) {
        game.core.complete();
      }
      // The daily challenge has nothing more to give once its target is reached.
      final daily = widget.daily;
      if (daily != null && !game.core.over && daily.completed(game.core)) game.core.complete();
      if (_tutorial < 3) {
        setState(() => _tutorial = 3);
        _model.completeTutorial();
      }
      if (e.firstTime && !_model.profile.discovered.contains(e.level) && e.level >= 6) {
        _showBanner('${_model.t('new_discovery')}: ${_model.evoName(e.level)}');
        _model.audio.play(Sfx.unlock, volume: 0.7);
      }
    }
  }

  void _showBanner(String text) {
    _bannerTimer?.cancel();
    setState(() => _banner = text);
    _bannerTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _banner = '');
    });
  }

  void _onRunEnded() {
    final core = game.core;
    if (_classic && core.canContinue && _model.ads.rewardedReady) {
      _continueLeft = 6;
      _setPhase(_Phase.continuePrompt);
      _continueTimer?.cancel();
      _continueTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _phase != _Phase.continuePrompt) {
          t.cancel();
          return;
        }
        if (_busy) return;
        setState(() => _continueLeft--);
        if (_continueLeft <= 0) {
          t.cancel();
          _finalize();
        }
      });
    } else {
      _finalize();
    }
  }

  void _finalize() {
    _continueTimer?.cancel();
    final outcome = _bank();
    _model.completeTutorial();
    if (outcome != null) {
      _outcome = outcome;
      _doubled = 0;
      if (outcome.record && outcome.previousBest > 0) _model.audio.play(Sfx.record);
      if (outcome.worldDone > 0 || outcome.masterNow) _model.audio.play(Sfx.unlock);
    }
    _setPhase(_Phase.results);
  }

  RunOutcome? _bank() => _model.finishRun(game.core, _runId, daily: widget.daily, level: _level, master: _master);

  // --- Ads (always optional: a failure simply means "no bonus") ---

  Future<bool> _rewarded(String placement) async {
    if (_busy) return false;
    setState(() => _busy = true);
    _model.audio.pauseAll();
    var earned = false;
    try {
      earned = await _model.ads.showRewarded(placement);
    } catch (_) {
      earned = false;
    }
    _model.audio.resumeAll();
    if (mounted) setState(() => _busy = false);
    return earned;
  }

  Future<void> _continueWithAd() async {
    final earned = await _rewarded('continue');
    if (!mounted) return;
    if (earned && _gate.grant('continue:$_runId') && game.core.continueRun()) {
      _continueTimer?.cancel();
      _setPhase(_Phase.playing);
    } else {
      if (!earned) showToast(context, _model.t('ad_unavailable'));
      _finalize();
    }
  }

  Future<void> _doubleWithAd() async {
    final earned = await _rewarded('double_coins');
    if (!mounted) return;
    if (earned && _gate.grant('double:$_runId')) {
      final coins = _model.doubleCoins(_runId);
      setState(() => _doubled = coins);
    } else if (!earned) {
      showToast(context, _model.t('ad_unavailable'));
    }
  }

  Future<void> _interstitialIfDue() async {
    final p = _model.profile;
    _model.audio.pauseAll();
    try {
      final shown = await _model.ads.maybeShowInterstitial(
        runsSince: p.runsSinceInterstitial,
        totalRuns: p.runs,
        removeAds: p.removeAds,
        tutorialDone: p.tutorialDone,
      );
      if (shown) _model.noteInterstitialShown();
    } catch (_) {}
    _model.audio.resumeAll();
  }

  // --- Navigation ---

  Future<void> _playAgain() async {
    if (_busy) return;
    _busy = true;
    if (_phase != _Phase.results) _bank();
    await _interstitialIfDue();
    _busy = false;
    if (!mounted) return;
    _outcome = null;
    game.startRun(_newCore());
    _announceLevel();
    _setPhase(_Phase.playing);
  }

  /// Result screen -> the following campaign level, without going back to the map.
  Future<void> _nextLevel() async {
    final next = _level == null ? null : nextLevel(_level!.id);
    // Checked before the level is switched: a second tap while the first is still being
    // handled must not move on twice.
    if (_busy || next == null || !_model.unlocked(next)) return;
    _level = next;
    _master = false;
    await _playAgain();
  }

  Future<void> _goHome() async {
    if (_busy) return;
    if (_phase == _Phase.results) {
      _busy = true;
      await _interstitialIfDue();
      _busy = false;
    } else if (!_classic) {
      // A daily or campaign attempt cannot be resumed later: bank what was achieved.
      _bank();
    } else {
      _stashRun();
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _onBack() {
    switch (_phase) {
      case _Phase.intro:
        _setPhase(_Phase.playing);
      case _Phase.playing:
        _setPhase(_Phase.paused);
      case _Phase.paused:
        _setPhase(_Phase.playing);
      case _Phase.continuePrompt:
        _finalize();
      case _Phase.results:
        _goHome();
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    game.setInsets(media.padding.top + 168, media.padding.bottom + 18);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Palette.ink,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                if (_phase != _Phase.playing || _pointer != null) return;
                _pointer = e.pointer;
                game.aimAt(e.localPosition.dx);
              },
              onPointerMove: (e) {
                if (e.pointer != _pointer) return;
                game.aimAt(e.localPosition.dx);
                if (_tutorial == 0) setState(() => _tutorial = 1);
              },
              onPointerUp: (e) {
                if (e.pointer != _pointer) return;
                _pointer = null;
                if (_phase != _Phase.playing) return;
                game.aimAt(e.localPosition.dx);
                game.release();
                if (_tutorial == 0) setState(() => _tutorial = 1);
              },
              onPointerCancel: (e) {
                if (e.pointer == _pointer) _pointer = null;
              },
              child: GameWidget(game: game),
            ),
            SafeArea(child: _hud()),
            if (_banner.isNotEmpty) _bannerView(media),
            if (_phase == _Phase.playing && _tutorial < 3) _tutorialHint(media),
            if (_phase == _Phase.playing) _countingView(media),
            if (_phase == _Phase.intro) _overlay(_howToPlayPanel()),
            if (_phase == _Phase.paused) _overlay(_pausePanel()),
            if (_phase == _Phase.continuePrompt) _overlay(_continuePanel()),
            if (_phase == _Phase.results) _overlay(_level != null ? _levelResults() : _resultsPanel()),
          ],
        ),
      ),
    );
  }

  Widget _hud() {
    final daily = widget.daily;
    final level = _level;
    final best = level != null
        ? (_model.profile.levels[level.id]?.best ?? 0)
        : daily == null
        ? _model.profile.bestScore
        : _model.dailyBestToday;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RoundButton(
                icon: Icons.pause_rounded,
                semantic: _model.t('paused'),
                onTap: () => _setPhase(_Phase.paused),
              ),
              if (kDebugMode && GameScreen.debugTools) ...[
                const SizedBox(width: 8),
                RoundButton(icon: Icons.bug_report_rounded, semantic: 'debug', onTap: _debugPanel),
              ],
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: game.score,
                  builder: (context, score, _) {
                    final progress = best > 0 ? (score / best).clamp(0.0, 1.0) : 0.0;
                    return Column(
                      children: [
                        Text(
                          _model.t('score').toUpperCase(),
                          style: ts(11, weight: 700, color: Palette.faint, spacing: 1.6),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(formatNumber(score), style: ts(40, weight: 800, height: 1.05)),
                        ),
                        const SizedBox(height: 4),
                        // The record is always in sight: the bar fills as the run approaches it.
                        SizedBox(
                          width: 150,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 5,
                              backgroundColor: const Color(0x26FFFFFF),
                              valueColor: AlwaysStoppedAnimation(progress >= 1 ? Palette.gold : Palette.cyan),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.emoji_events_rounded, size: 14, color: Palette.gold.withValues(alpha: 0.9)),
                              const SizedBox(width: 4),
                              Text(
                                '${_model.t('best')} ${formatNumber(best)}',
                                style: ts(13, weight: 600, color: Palette.dim),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              GlassPanel(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                radius: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _model.t('next').toUpperCase(),
                      style: ts(10, weight: 700, color: Palette.faint, spacing: 1.2),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: ValueListenableBuilder<int>(
                          valueListenable: game.nextPiece,
                          builder: (context, level, _) => OrbView(level: level, size: 22.0 + level * 4.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (level != null)
            _levelGoalPanel(level)
          else if (daily != null)
            GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              radius: 14,
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded, size: 16, color: Palette.gold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dailyGoalText(_model, daily),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ts(12.5, weight: 600, color: Palette.dim),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: game.dropsLeft,
                    builder: (context, left, _) => Text('$left', style: ts(18, weight: 800, color: Palette.cyan)),
                  ),
                ],
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: CoinBadge(amount: _model.profile.coins, size: 14),
            ),
        ],
      ),
    );
  }

  /// The level's goal, how many stars are still in reach, and the drops that remain.
  Widget _levelGoalPanel(LevelDef level) {
    final accent = worldColor(level.world);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      radius: 14,
      border: accent.withValues(alpha: 0.6),
      child: AnimatedBuilder(
        animation: Listenable.merge([game.score, game.dropsLeft]),
        builder: (context, _) {
          final core = game.core;
          final ready = level.goals.every((g) => g.type == GoalType.survive || level.goalMet(core, g, master: _master));
          final int stars;
          if (level.byScore) {
            stars = ready ? 1 + (core.score >= level.star2 ? 1 : 0) + (core.score >= level.star3 ? 1 : 0) : 0;
          } else {
            stars = core.drops <= level.star3 ? 3 : (core.drops <= level.star2 ? 2 : 1);
          }
          return Row(
            children: [
              Text(levelTag(level), style: ts(15, weight: 800, color: accent)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  goalLines(_model, level, master: _master).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ts(12.5, weight: 600, color: ready ? Palette.green : Palette.dim),
                ),
              ),
              const SizedBox(width: 8),
              _master
                  ? Icon(Icons.diamond_rounded, size: 18, color: ready ? Palette.cyan : Palette.faint)
                  : StarRow(stars: stars, size: 15),
              const SizedBox(width: 8),
              Text('${game.dropsLeft.value}', style: ts(18, weight: 800, color: Palette.cyan)),
            ],
          );
        },
      ),
    );
  }

  Widget _bannerView(MediaQueryData media) {
    return Positioned(
      top: media.padding.top + 176,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (context, v, child) => Transform.scale(
            scale: 0.8 + 0.2 * v,
            child: Opacity(opacity: v.clamp(0, 1), child: child),
          ),
          child: Center(
            child: GlassPanel(
              border: Palette.gold,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Palette.gold, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(_banner, style: ts(15, weight: 700), textAlign: TextAlign.center),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shown from the last drop until the result: the pile is still settling, and the player
  /// should see that the game is counting rather than stuck.
  Widget _countingView(MediaQueryData media) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: media.padding.bottom + 70,
      child: IgnorePointer(
        child: ValueListenableBuilder<int>(
          valueListenable: game.dropsLeft,
          builder: (context, left, _) {
            if (left != 0) return const SizedBox.shrink();
            return Center(
              child: GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Palette.cyan),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(_model.t('counting'), style: ts(15, weight: 700), textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// What the game is about, in three pictures. Opens by itself before the first run and
  /// from the pause menu afterwards.
  Widget _howToPlayPanel() {
    Widget step(Widget picture, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox(width: 92, height: 54, child: Center(child: picture)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: ts(14.5, weight: 600, color: Palette.text, height: 1.25)),
          ),
        ],
      ),
    );
    return GlassPanel(
      solid: true,
      padding: const EdgeInsets.all(22),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_model.t('how_title'), style: ts(26, weight: 800), textAlign: TextAlign.center),
            const SizedBox(height: 18),
            step(const Icon(Icons.swipe_rounded, color: Palette.cyan, size: 40), _model.t('how_1')),
            step(
              const FittedBox(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OrbView(level: 2, size: 30),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.add_rounded, color: Palette.dim, size: 16),
                    ),
                    OrbView(level: 2, size: 30),
                    Icon(Icons.arrow_right_alt_rounded, color: Palette.gold, size: 22),
                    OrbView(level: 3, size: 40),
                  ],
                ),
              ),
              _model.t('how_2'),
            ),
            step(const Icon(Icons.vertical_align_top_rounded, color: Palette.gold, size: 40), _model.t('how_3')),
            const SizedBox(height: 6),
            GameButton(
              key: const ValueKey('how-ok'),
              label: _model.t('play'),
              icon: Icons.play_arrow_rounded,
              primary: true,
              onTap: () => _setPhase(_Phase.playing),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tutorialHint(MediaQueryData media) {
    final key = const ['tut_aim', 'tut_drop', 'tut_merge'][_tutorial];
    return Positioned(
      left: 24,
      right: 24,
      bottom: media.padding.bottom + 70,
      child: IgnorePointer(
        child: Center(
          child: GlassPanel(
            border: Palette.cyan,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SlidingHand(slide: _tutorial == 0),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(_model.t(key), style: ts(17, weight: 700), textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(Widget panel) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xB3050816),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, child) => Transform.translate(
                    offset: Offset(0, 24 * (1 - v)),
                    child: Opacity(opacity: v, child: child),
                  ),
                  child: panel,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pausePanel() {
    final p = _model.profile;
    return GlassPanel(
      solid: true,
      padding: const EdgeInsets.all(22),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_model.t('paused'), style: ts(28, weight: 800), textAlign: TextAlign.center),
            const SizedBox(height: 18),
            GameButton(
              label: _model.t('resume'),
              icon: Icons.play_arrow_rounded,
              primary: true,
              onTap: () => _setPhase(_Phase.playing),
            ),
            const SizedBox(height: 12),
            GameButton(label: _model.t('restart'), icon: Icons.refresh_rounded, onTap: _playAgain),
            const SizedBox(height: 12),
            GameButton(
              label: _model.t('how_title'),
              icon: Icons.help_outline_rounded,
              onTap: () => _setPhase(_Phase.intro),
            ),
            const SizedBox(height: 12),
            GameButton(
              label: _model.t(widget.exitLabel),
              icon: widget.exitLabel == 'map' ? Icons.map_rounded : Icons.home_rounded,
              onTap: _goHome,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Toggle(
                  icon: Icons.music_note_rounded,
                  label: _model.t('music'),
                  on: p.music,
                  onChanged: _model.setMusic,
                ),
                _Toggle(icon: Icons.volume_up_rounded, label: _model.t('sound'), on: p.sfx, onChanged: _model.setSfx),
                _Toggle(
                  icon: Icons.vibration_rounded,
                  label: _model.t('vibration'),
                  on: p.haptics,
                  onChanged: _model.setHaptics,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _continuePanel() {
    return GlassPanel(
      solid: true,
      padding: const EdgeInsets.all(22),
      border: Palette.cyan,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_model.t('game_over'), style: ts(26, weight: 800), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            formatNumber(game.core.score),
            style: ts(40, weight: 800, color: Palette.cyan),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          GameButton(
            label: _model.t('continue_ad'),
            icon: Icons.play_circle_fill_rounded,
            primary: true,
            enabled: !_busy,
            onTap: _continueWithAd,
            trailing: Text('$_continueLeft', style: ts(18, weight: 800, color: Palette.ink)),
          ),
          const SizedBox(height: 12),
          GameButton(label: _model.t('play_again'), icon: Icons.refresh_rounded, enabled: !_busy, onTap: _finalize),
        ],
      ),
    );
  }

  Widget _resultsPanel() {
    final o = _outcome;
    final daily = widget.daily;
    final core = game.core;
    final String title;
    final Color accent;
    if (daily != null) {
      final done = daily.completed(core);
      title = _model.t(done ? 'completed' : 'challenge_failed');
      accent = done ? Palette.green : Palette.violet;
    } else if (o != null && o.record && o.previousBest > 0) {
      title = _model.t('new_record');
      accent = Palette.gold;
    } else {
      title = _model.t('game_over');
      accent = Palette.cyan;
    }
    final best = daily == null ? _model.profile.bestScore : _model.dailyBestToday;
    final gap = best - core.score;
    final canDouble = o != null && o.coins > 0 && _doubled == 0 && _model.ads.rewardedReady;

    return GlassPanel(
      solid: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      border: accent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(title, style: ts(28, weight: 800, color: accent)),
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: core.score.toDouble()),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(formatNumber(v.round()), style: ts(54, weight: 800, height: 1.1)),
            ),
          ),
          if (daily != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                dailyGoalText(_model, daily),
                style: ts(13, color: Palette.dim),
                textAlign: TextAlign.center,
              ),
            )
          else if (gap > 0)
            Text(
              _model.t('to_record', {'n': formatNumber(gap)}),
              style: ts(15, color: Palette.dim),
              textAlign: TextAlign.center,
            )
          else
            Text(
              '${_model.t('best')} ${formatNumber(best)}',
              style: ts(15, color: Palette.dim),
              textAlign: TextAlign.center,
            ),
          if (o != null) Flexible(child: SingleChildScrollView(child: _rewards(o))),
          const SizedBox(height: 16),
          GameButton(
            label: _model.t('play_again'),
            icon: Icons.refresh_rounded,
            primary: true,
            enabled: !_busy,
            onTap: _playAgain,
          ),
          if (canDouble) ...[
            const SizedBox(height: 10),
            GameButton(
              label: _model.t('double_coins'),
              icon: Icons.play_circle_fill_rounded,
              color: Palette.gold,
              enabled: !_busy,
              onTap: _doubleWithAd,
            ),
          ],
          const SizedBox(height: 10),
          GameButton(label: _model.t('home'), icon: Icons.home_rounded, enabled: !_busy, compact: true, onTap: _goHome),
        ],
      ),
    );
  }

  /// Everything a run paid out, spelled out: coins, XP, discoveries, achievements, unlocks.
  Widget _rewards(RunOutcome o, {List<Widget> extra = const []}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('+', style: ts(22, weight: 800, color: Palette.gold)),
            CoinBadge(amount: o.totalCoins + _doubled, size: 22),
            if (_doubled > 0) ...[
              const SizedBox(width: 8),
              Text('×2', style: ts(18, weight: 800, color: Palette.green)),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _XpBar(model: _model, gained: o.levelsGained),
        if (o.discoveries.any((lv) => lv > _model.balance.spawnWeights.length)) ...[
          const SizedBox(height: 14),
          Text(
            _model.t('new_discovery'),
            style: ts(13, weight: 700, color: Palette.gold, spacing: 0.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              for (final lv in o.discoveries.where((lv) => lv > _model.balance.spawnWeights.length))
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OrbView(level: lv, size: 46),
                    Text(_model.evoName(lv), style: ts(11, color: Palette.dim)),
                  ],
                ),
            ],
          ),
        ],
        for (final a in o.newAchievements)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.military_tech_rounded, color: Palette.gold, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(achievementText(_model, a), style: ts(13.5, weight: 600))),
                CoinBadge(amount: a.coins, size: 13),
              ],
            ),
          ),
        for (final item in o.unlockedItems)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.lock_open_rounded, color: Palette.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${_model.t('unlocked')}: ${_model.itemName(item)}', style: ts(13.5, weight: 600)),
                ),
              ],
            ),
          ),
        ...extra,
      ],
    );
  }

  Widget _levelResults() {
    final o = _outcome;
    final level = _level!;
    final core = game.core;
    final p = _model.profile;
    final rec = p.levels[level.id];
    final passed = o?.passed ?? level.passed(core, master: _master);
    final accent = !passed ? Palette.violet : (_master ? Palette.cyan : Palette.gold);
    final String title;
    if (!passed) {
      title = _model.t('challenge_failed');
    } else if (_master) {
      title = _model.t('completed');
    } else {
      title = _model.t(o != null && o.worldDone > 0 ? 'world_complete' : 'level_complete');
    }
    final next = nextLevel(level.id);
    final canNext = passed && !_master && next != null && _model.unlocked(next);
    final canDouble = o != null && o.coins > 0 && _doubled == 0 && _model.ads.rewardedReady;
    final done = worldLevels(level.world).where((l) => p.starsOf(l.id) > 0).length;
    final total = worldLevels(level.world).length;
    final assist = passed || _master ? 0 : level.assistDrops(p.fails[level.id] ?? 0);

    final String record;
    if (_master) {
      record = _model.t('master');
    } else if (!level.byScore && (rec?.fewest ?? 0) > 0) {
      record = _model.t('fewest_drops', {'n': rec!.fewest});
    } else if (o != null && o.record && o.previousBest > 0) {
      record = _model.t('new_record');
    } else if ((rec?.best ?? 0) > core.score) {
      record = _model.t('to_record', {'n': formatNumber(rec!.best - core.score)});
    } else {
      record = '${_model.t('best')} ${formatNumber(rec?.best ?? core.score)}';
    }

    return GlassPanel(
      solid: true,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      border: accent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_model.worldName(level.world)} · ${levelTag(level)}',
            style: ts(13, weight: 700, color: worldColor(level.world), spacing: 0.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(title, style: ts(28, weight: 800, color: accent)),
          ),
          const SizedBox(height: 8),
          if (_master)
            Icon(Icons.diamond_rounded, size: 54, color: passed ? Palette.cyan : Palette.faint)
          else
            _BigStars(stars: passed ? level.stars(core) : 0),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: core.score.toDouble()),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(formatNumber(v.round()), style: ts(44, weight: 800, height: 1.1)),
            ),
          ),
          Text(
            record,
            style: ts(14, color: Palette.dim),
            textAlign: TextAlign.center,
          ),
          if (!passed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                goalLines(_model, level, master: _master).join(' · '),
                style: ts(13, color: Palette.dim),
                textAlign: TextAlign.center,
              ),
            ),
          if (o != null)
            Flexible(
              child: SingleChildScrollView(
                child: _rewards(
                  o,
                  extra: [
                    if (o.worldDone > 0) _unlockLine(Icons.public_rounded, Palette.gold, _model.t('world_complete')),
                    if (o.firstClear && !level.trial)
                      _unlockLine(Icons.diamond_rounded, Palette.cyan, _model.t('master')),
                    if (o.masterNow) _unlockLine(Icons.diamond_rounded, Palette.cyan, _model.t('completed')),
                    if (assist > 0)
                      _unlockLine(Icons.volunteer_activism_rounded, Palette.green, _model.t('assist', {'n': assist})),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('${_model.worldName(level.world)} $done / $total', style: ts(12.5, weight: 700, color: Palette.dim)),
              const SizedBox(width: 10),
              Expanded(
                child: ProgressBar(value: done / total, color: worldColor(level.world), height: 6),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GameButton(
            label: _model.t(canNext ? 'next_level' : 'play_again'),
            icon: canNext ? Icons.arrow_forward_rounded : Icons.refresh_rounded,
            primary: true,
            enabled: !_busy,
            onTap: canNext ? _nextLevel : _playAgain,
          ),
          if (canDouble) ...[
            const SizedBox(height: 10),
            GameButton(
              label: _model.t('double_coins'),
              icon: Icons.play_circle_fill_rounded,
              color: Palette.gold,
              enabled: !_busy,
              compact: true,
              onTap: _doubleWithAd,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (canNext) ...[
                Expanded(
                  child: GameButton(
                    label: _model.t('play_again'),
                    icon: Icons.refresh_rounded,
                    enabled: !_busy,
                    compact: true,
                    onTap: _playAgain,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: GameButton(
                  label: _model.t(widget.exitLabel),
                  icon: widget.exitLabel == 'map' ? Icons.map_rounded : Icons.home_rounded,
                  enabled: !_busy,
                  compact: true,
                  onTap: _goHome,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _unlockLine(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: ts(13.5, weight: 600))),
        ],
      ),
    );
  }

  // --- Debug tools: compiled out of release builds (kDebugMode is a constant false there) ---

  void _debugPanel() {
    if (!kDebugMode) return;
    final core = game.core;
    final was = _phase;
    _setPhase(_Phase.paused);
    var level = 6;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Debug  seed ${core.seed}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: level.toDouble(),
                min: 1,
                max: 12,
                divisions: 11,
                label: '$level',
                onChanged: (v) => setLocal(() => level = v.round()),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: () => core.debugSpawn(level, 170, 120), child: Text('Spawn $level')),
                  TextButton(
                    onPressed: () {
                      core.debugSpawn(level, 130, 200);
                      core.debugSpawn(level, 210, 200);
                    },
                    child: const Text('Spawn pair'),
                  ),
                  TextButton(onPressed: core.debugClear, child: const Text('Clear board')),
                  TextButton(onPressed: core.forceGameOver, child: const Text('Game over')),
                  TextButton(onPressed: () => game.showStats = !game.showStats, child: const Text('FPS / entities')),
                  TextButton(
                    onPressed: () {
                      game.startRun(GameCore(balance: _model.balance, seed: 12345));
                      _runId = 'c-12345-${_model.now.millisecondsSinceEpoch}';
                    },
                    child: const Text('Seed 12345'),
                  ),
                  TextButton(onPressed: _model.resetAll, child: const Text('Reset save')),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      if (was == _Phase.playing && _phase == _Phase.paused) _setPhase(_Phase.playing);
    });
  }
}

/// The three stars of a result, popping in one after another.
class _BigStars extends StatelessWidget {
  const _BigStars({required this.stars});
  final int stars;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 3; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 260 + i * 180),
            curve: Interval(1 - 260 / (260 + i * 180), 1, curve: Curves.easeOutBack),
            builder: (context, v, _) => Transform.scale(
              scale: i <= stars ? 0.4 + 0.6 * v : 1,
              child: Padding(
                padding: EdgeInsets.only(left: 3, right: 3, top: i == 2 ? 0 : 10),
                child: Icon(
                  i <= stars ? Icons.star_rounded : Icons.star_border_rounded,
                  size: i == 2 ? 62 : 50,
                  color: i <= stars ? Palette.gold : Palette.faint,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.label, required this.on, required this.onChanged});
  final IconData icon;
  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!on),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? const Color(0x338CF0FF) : const Color(0x14FFFFFF),
            border: Border.all(color: on ? Palette.cyan : const Color(0x33FFFFFF), width: 1.4),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: on ? Palette.text : Palette.faint, size: 26),
              // Off is shown by a slash as well as by colour.
              if (!on) Transform.rotate(angle: -0.785, child: Container(width: 34, height: 2.4, color: Palette.rose)),
            ],
          ),
        ),
      ),
    );
  }
}

class _XpBar extends StatelessWidget {
  const _XpBar({required this.model, required this.gained});
  final AppModel model;
  final int gained;

  @override
  Widget build(BuildContext context) {
    final p = model.profile;
    final need = model.balance.xpForLevel(p.level);
    return Row(
      children: [
        Icon(Icons.bolt_rounded, size: 18, color: gained > 0 ? Palette.green : Palette.violet),
        Text('${p.level}', style: ts(14, weight: 800, color: gained > 0 ? Palette.green : Palette.violet)),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (p.xp / need).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: const Color(0x26FFFFFF),
                valueColor: const AlwaysStoppedAnimation(Palette.violet),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SlidingHand extends StatefulWidget {
  const _SlidingHand({required this.slide});
  final bool slide;

  @override
  State<_SlidingHand> createState() => _SlidingHandState();
}

class _SlidingHandState extends State<_SlidingHand> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: widget.slide ? Offset((v - 0.5) * 22, 0) : Offset(0, (v - 0.5) * -8),
          child: child,
        );
      },
      child: const Icon(Icons.touch_app_rounded, color: Palette.cyan, size: 28),
    );
  }
}
