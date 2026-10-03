/// The play screen: board, HUD, onboarding hints, pause, rewarded continue and the result card.
library;

import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/ad_policy.dart';
import '../core/daily.dart';
import '../core/game_core.dart';
import '../core/progression.dart';
import '../game/board_game.dart';
import '../services/feedback.dart';
import 'widgets.dart';

enum _Phase { playing, paused, continuePrompt, results }

String achievementText(AppModel m, Achievement a) => switch (a.stat) {
  Stat.totalMerges => m.t('ach_merges', {'n': formatNumber(a.target)}),
  Stat.maxChain => m.t('ach_chain', {'n': a.target}),
  Stat.maxLevel => m.t('ach_evo', {'name': m.evoName(a.target)}),
  Stat.bestScore => m.t('ach_score', {'n': formatNumber(a.target)}),
  Stat.runs => m.t('ach_runs', {'n': a.target}),
  Stat.dailyCompleted => m.t('ach_daily', {'n': a.target}),
  Stat.bigBangs => m.t('ach_bigbang'),
  Stat.perfects => m.t('ach_perfect', {'n': a.target}),
};

String dailyGoalText(AppModel m, DailyChallenge d) => switch (d.type) {
  DailyType.score => m.t('goal_score', {'n': formatNumber(d.target), 'd': d.dropLimit}),
  DailyType.evolution => m.t('goal_evo', {'name': m.evoName(d.target), 'd': d.dropLimit}),
  DailyType.chain => m.t('goal_chain', {'n': d.target, 'd': d.dropLimit}),
};

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.daily});

  /// Null = classic endless mode.
  final DailyChallenge? daily;

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
      _game = BoardGame(core: _newCore(resume: true), model: _model)
        ..onEvent = _onEvent
        ..onRunEnded = _onRunEnded;
      game.startRun(game.core);
      _tutorial = _model.profile.tutorialDone ? 3 : 0;
    }
  }

  GameCore _newCore({bool resume = false}) {
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
    if (widget.daily == null && _phase != _Phase.results && !game.core.over) {
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
    if (widget.daily == null && core.canContinue && _model.ads.rewardedReady) {
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
    final outcome = _model.finishRun(game.core, _runId, daily: widget.daily);
    _model.completeTutorial();
    if (outcome != null) {
      _outcome = outcome;
      _doubled = 0;
      if (outcome.record && outcome.previousBest > 0) _model.audio.play(Sfx.record);
    }
    _setPhase(_Phase.results);
  }

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
    if (_phase != _Phase.results) _model.finishRun(game.core, _runId, daily: widget.daily);
    await _interstitialIfDue();
    _busy = false;
    if (!mounted) return;
    _outcome = null;
    game.startRun(_newCore());
    _setPhase(_Phase.playing);
  }

  Future<void> _goHome() async {
    if (_busy) return;
    if (_phase == _Phase.results) {
      _busy = true;
      await _interstitialIfDue();
      _busy = false;
    } else if (widget.daily != null) {
      // A daily attempt cannot be resumed later: bank what was achieved.
      _model.finishRun(game.core, _runId, daily: widget.daily);
    } else {
      _stashRun();
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _onBack() {
    switch (_phase) {
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
            if (_phase == _Phase.paused) _overlay(_pausePanel()),
            if (_phase == _Phase.continuePrompt) _overlay(_continuePanel()),
            if (_phase == _Phase.results) _overlay(_resultsPanel()),
          ],
        ),
      ),
    );
  }

  Widget _hud() {
    final daily = widget.daily;
    final best = daily == null ? _model.profile.bestScore : _model.dailyBestToday;
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
              if (kDebugMode) ...[
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
          if (daily != null)
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
            GameButton(label: _model.t('home'), icon: Icons.home_rounded, onTap: _goHome),
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
          if (o != null)
            Flexible(
              child: SingleChildScrollView(
                child: Column(
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
                              child: Text(
                                '${_model.t('unlocked')}: ${_model.t(item.id)}',
                                style: ts(13.5, weight: 600),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
        Text(
          model.t('level_n', {'n': p.level}),
          style: ts(13, weight: 700, color: gained > 0 ? Palette.green : Palette.dim),
        ),
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
