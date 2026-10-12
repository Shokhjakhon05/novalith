// End-to-end widget tests: the real app, real screens and the real simulation, with the
// device-only services (audio, ads, store, disk) replaced by in-memory stand-ins.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/app/app_model.dart';
import 'package:novalith/core/bots.dart';
import 'package:novalith/core/campaign.dart';
import 'package:novalith/core/campaign_data.dart';
import 'package:novalith/core/daily.dart';
import 'package:novalith/core/game_core.dart';
import 'package:novalith/core/profile.dart';
import 'package:novalith/core/progression.dart';
import 'package:novalith/core/rng.dart';
import 'package:novalith/game/board_game.dart';
import 'package:novalith/l10n/l10n.dart';
import 'package:novalith/main.dart';
import 'package:novalith/services/ads/ad_manager.dart';
import 'package:novalith/services/analytics.dart';
import 'package:novalith/services/feedback.dart';
import 'package:novalith/services/purchases.dart';
import 'package:novalith/services/save_store.dart';
import 'package:novalith/ui/collection_screen.dart';
import 'package:novalith/ui/game_screen.dart';
import 'package:novalith/ui/goals_screen.dart';
import 'package:novalith/ui/map_screen.dart';
import 'package:novalith/ui/settings_screen.dart';
import 'package:novalith/ui/shop_screen.dart';
import 'package:novalith/ui/widgets.dart';

final String? shotDir = Platform.environment['NOVALITH_PREVIEW_DIR'];
final _shotKey = GlobalKey();
double shotPixelRatio = 2;

class Rig {
  Rig({MemorySaveStore? store, bool rewarded = false, bool grant = true, DateTime? now})
    : store = store ?? MemorySaveStore(),
      ads = NoAds(rewardedAvailable: rewarded, grantReward: grant) {
    model = AppModel(
      store: this.store,
      audio: audio,
      haptics: haptics,
      ads: ads,
      analytics: analytics,
      purchases: NoPurchases(),
      clock: () => this.now,
    );
    if (now != null) this.now = now;
  }

  final MemorySaveStore store;
  final NoAds ads;
  final SilentAudio audio = SilentAudio();
  final Haptics haptics = Haptics();
  final RecordingAnalytics analytics = RecordingAnalytics();
  late final AppModel model;
  DateTime now = DateTime(2026, 10, 4, 12);
}

Future<void> loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final loader = FontLoader(family)..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    await loader.load();
  }

  await load('Exo2', 'assets/fonts/Exo2.ttf');
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  await load('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

Future<void> launch(WidgetTester tester, Rig rig, {Size size = const Size(360, 780)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shotKey,
      child: NovalithApp(key: UniqueKey(), model: rig.model, startServices: false),
    ),
  );
  await frames(tester, 6);
}

Future<void> frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> seconds(WidgetTester tester, double s) => frames(tester, (s * 60).round());

Future<void> shot(WidgetTester tester, String name) async {
  if (shotDir == null) return;
  await tester.runAsync(() async {
    final boundary = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: shotPixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$shotDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

BoardGame board(WidgetTester tester) => tester.widget<GameWidget<BoardGame>>(find.byType(GameWidget<BoardGame>)).game!;

/// Closes the "how to play" card a first-time player gets before the first run.
Future<void> closeIntro(WidgetTester tester) async {
  final ok = find.byKey(const ValueKey('how-ok'));
  if (ok.evaluate().isEmpty) return;
  await tester.tap(ok);
  await frames(tester, 20);
}

Future<void> dropAt(WidgetTester tester, double x) async {
  await closeIntro(tester);
  final g = await tester.startGesture(Offset(x, 500));
  await tester.pump(const Duration(milliseconds: 16));
  await g.moveTo(Offset(x + 2, 500));
  await tester.pump(const Duration(milliseconds: 16));
  await g.up();
  await seconds(tester, 0.6);
}

/// Taps a label. A tap that starts a first-time player's game also closes the "how to play"
/// card, unless the test wants to look at it ([intro] = false).
Future<void> tapText(WidgetTester tester, String text, {bool intro = true}) async {
  await tester.tap(find.text(text).first);
  await frames(tester, 20);
  if (intro) await closeIntro(tester);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('first launch: menu, play, tutorial, merge, game over, instant replay', (tester) async {
    final rig = Rig();
    await launch(tester, rig);
    expect(find.text('NOVALITH'), findsOneWidget);
    expect(rig.model.loadStatus, LoadStatus.fresh);
    await shot(tester, 'menu');

    await tapText(tester, 'Endless');
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Slide to aim'), findsOneWidget, reason: 'contextual onboarding, no manual');

    final game = board(tester);
    await dropAt(tester, 100);
    expect(find.text('Match two to merge'), findsOneWidget);
    expect(game.core.drops, 1);

    // Keep dropping in one column: the guaranteed opening pair must merge.
    for (var i = 0; i < 6 && game.core.merges == 0; i++) {
      await dropAt(tester, 100);
    }
    expect(game.core.merges, greaterThan(0));
    expect(rig.model.profile.tutorialDone, isTrue);
    expect(find.text('Match two to merge'), findsNothing);
    expect(rig.audio.played.any((s) => s.startsWith('merge_')), isTrue, reason: 'merge has sound');
    expect(rig.haptics.fired, greaterThan(0), reason: 'drops and merges have haptics');

    for (var i = 0; i < 14; i++) {
      await dropAt(tester, 40.0 + (i * 67) % 280);
    }
    await shot(tester, 'game');
    expect(tester.takeException(), isNull);

    final scoreBefore = game.core.score;
    game.core.forceGameOver();
    await seconds(tester, 1.2);
    expect(find.text('Play again'), findsOneWidget, reason: 'no ad ready -> straight to the result');
    expect(rig.model.profile.runs, 1);
    expect(rig.model.profile.bestScore, scoreBefore);
    expect(rig.model.profile.activeRun, isNull);
    await shot(tester, 'results');

    // Game over -> new run in one tap.
    await tapText(tester, 'Play again');
    final next = board(tester);
    expect(next.core.over, isFalse);
    expect(next.core.drops, 0);
    expect(find.text('Play again'), findsNothing);
    await dropAt(tester, 200);
    expect(next.core.drops, 1);
    expect(rig.ads.interstitialsShown, 0, reason: 'no interstitial during the first runs');
    expect(tester.takeException(), isNull);
  });

  testWidgets('campaign: a new player goes from the menu through level 1 to level 2', (tester) async {
    final rig = Rig();
    await launch(tester, rig);
    expect(find.text('Level 1 of 20'), findsOneWidget, reason: 'the menu says where the player is');
    expect(find.text('WORLD 1 · ORIGIN'), findsOneWidget);

    await tapText(tester, 'PLAY');
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Slide to aim'), findsOneWidget, reason: 'the first level is also the tutorial');
    expect(find.text('Make 3 merges'), findsOneWidget, reason: 'the goal is on screen from the start');
    final game = board(tester);
    expect(game.core.dropLimit, campaignLevels.first.drops);

    // Play it for real: drop into one column until the goal is reached.
    for (var i = 0; i < campaignLevels.first.drops && !game.core.over; i++) {
      await dropAt(tester, 100 + (i % 3) * 30);
    }
    await seconds(tester, 2.5);
    expect(game.core.merges, greaterThanOrEqualTo(3));
    expect(game.core.endReason, EndReason.completed, reason: 'the level ends the moment the goal is met');
    expect(find.text('Level complete!'), findsOneWidget);
    expect(rig.model.profile.starsOf(101), greaterThan(0));
    expect(rig.model.profile.bestScore, 0, reason: 'the classic record belongs to the endless mode');
    expect(rig.analytics.events, containsAll(['campaign_level_started', 'campaign_level_completed', 'star_earned']));
    await shot(tester, 'level_result');

    await tapText(tester, 'Next level');
    final next = board(tester);
    expect(next.core.drops, 0);
    expect(next.core.dropLimit, campaignLevels[1].drops);
    expect(find.text('Create: Asteroid'), findsWidgets);

    // Leaving mid-level banks the attempt as a miss and goes back to the menu.
    await tester.binding.handlePopRoute();
    await frames(tester, 20);
    await tapText(tester, 'Home');
    await frames(tester, 20);
    expect(find.text('Level 2 of 20'), findsOneWidget);
    expect(find.text('RESUME'), findsOneWidget);
    expect(rig.model.profile.fails[102], 1);
    expect(Profile.decode(rig.store.text).profile.starsOf(101), greaterThan(0), reason: 'progress is on disk');
    expect(tester.takeException(), isNull);
  });

  testWidgets('map: current level in view, locked levels refuse, master opens after completion', (tester) async {
    final rig = Rig();
    final p = Profile()
      ..runs = 3
      ..rewardLastDate = 20261004
      ..rewardLastUtcMs = DateTime(2026, 10, 4, 12).toUtc().millisecondsSinceEpoch;
    for (final l in campaignLevels.take(23)) {
      p.levels[l.id] = LevelRecord(stars: 2, best: 500);
    }
    rig.store.text = p.encode();
    await launch(tester, rig);
    expect(find.text('WORLD 2 · NEBULA'), findsOneWidget);
    expect(find.text('Level 4 of 20'), findsOneWidget);

    await tester.tap(find.text('Level 4 of 20'));
    await frames(tester, 30);
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('level-204')), findsOneWidget, reason: 'opens on the current level');
    await shot(tester, 'map');

    // Level 2-6 is two steps ahead: locked.
    await tester.tap(find.byKey(const ValueKey('level-206')));
    await frames(tester, 20);
    expect(find.text('Complete the previous level first'), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);

    // A completed level shows its record and offers the master challenge.
    await tester.tap(find.byKey(const ValueKey('level-203')));
    await frames(tester, 30);
    expect(find.text('Master challenge'), findsOneWidget);
    await shot(tester, 'level_sheet');
    await tapText(tester, 'Master challenge');
    expect(find.byType(GameScreen), findsOneWidget);
    final game = board(tester);
    expect(game.core.dropLimit, levelDef(203)!.master.drops);
    game.core.merges = 15;
    game.core.complete();
    await seconds(tester, 1.2);
    expect(rig.model.profile.levels[203]!.master, isTrue);
    expect(rig.analytics.events, containsAll(['master_started', 'master_completed']));
    await tapText(tester, 'Map');
    await frames(tester, 20);
    expect(find.byType(MapScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('update from the pre-campaign version: progress kept, a thank-you gift, once', (tester) async {
    final rig = Rig();
    // A save exactly as version 1 wrote it.
    rig.store.text =
        '{"v":1,"coins":730,"xp":12,"level":4,"bestScore":8200,"owned":["theme_cosmos","bg_deep","theme_neon"],'
        '"theme":"theme_neon","background":"bg_deep","achievements":["merges_10","merges_100","evo_6"],'
        '"discovered":[2,3,4,5,6,7],"stats":{"runs":14,"totalMerges":420,"totalScore":50000,"maxChain":4,'
        '"maxLevel":7,"bigBangs":0,"perfects":30,"dailyCompleted":2},"daily":{"date":0,"best":0,"done":false},'
        '"reward":{"day":2,"streak":2,"lastDate":20261004,"lastUtcMs":${DateTime(2026, 10, 4, 12).toUtc().millisecondsSinceEpoch}},'
        '"settings":{"music":false,"sfx":true,"haptics":true,"showNumbers":false,"language":"en"},'
        '"tutorialDone":true,"removeAds":false,"lastRewardedRun":"x","lastDoubledRun":"","lastRunCoins":5,'
        '"runsSinceInterstitial":1,"activeRun":null}';
    await launch(tester, rig);
    final p = rig.model.profile;
    expect(rig.model.loadStatus, LoadStatus.ok);
    expect(p.bestScore, 8200);
    expect(p.theme, 'theme_neon');
    expect(p.achievements, containsAll(['merges_10', 'merges_100', 'evo_6']));
    expect(p.discovered, {2, 3, 4, 5, 6, 7});
    expect(p.music, isFalse);
    expect(find.text('Welcome back!'), findsOneWidget);
    final gift = p.gift;
    expect(gift, 50 + 30 + 8200 ~/ 400);
    await tapText(tester, 'Claim');
    expect(p.coins, 730 + gift);
    expect(p.gift, 0);
    expect(find.text('Welcome back!'), findsNothing);

    // After a restart the gift does not come back.
    await launch(tester, rig);
    expect(find.text('Welcome back!'), findsNothing);
    expect(rig.model.profile.coins, 730 + gift);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly goals and the archive: shown on the menu, paid once', (tester) async {
    final rig = Rig();
    final p = Profile()
      ..runs = 5
      ..rewardLastDate = 20261004
      ..rewardLastUtcMs = DateTime(2026, 10, 4, 12).toUtc().millisecondsSinceEpoch;
    syncCalendar(p, DateTime(2026, 10, 4, 12));
    final goal = weeklyGoals(p).first;
    p.weekProgress[goal.id] = goal.target;
    p.monthPoints = monthlyTarget;
    rig.store.text = p.encode();
    await launch(tester, rig);
    expect(rig.model.goalsClaimable, isTrue);
    await tapText(tester, 'Weekly goals');
    expect(find.byType(GoalsScreen), findsOneWidget);
    await shot(tester, 'goals');
    await tapText(tester, 'Claim');
    expect(rig.model.profile.coins, goal.coins);
    await tapText(tester, 'Claim');
    expect(rig.model.profile.coins, goal.coins + monthlyCoins);
    expect(rig.model.profile.owned, contains(monthlyTheme));
    expect(find.text('Claim'), findsNothing);
    expect(rig.model.claimWeeklyGoal(goal.id), 0);
    expect(rig.model.claimMonthlyReward(), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rewarded continue: once per run; reward and 2x coins are idempotent', (tester) async {
    final rig = Rig(rewarded: true);
    await launch(tester, rig);
    await tapText(tester, 'Endless');
    final game = board(tester);
    for (var i = 0; i < 8; i++) {
      await dropAt(tester, 60.0 + i * 30);
    }
    game.core.forceGameOver();
    await seconds(tester, 1.2);
    expect(find.text('Continue'), findsOneWidget);
    expect(rig.model.profile.runs, 0, reason: 'rewards wait until the run is really over');

    await tapText(tester, 'Continue');
    expect(rig.ads.rewardedShown, 1);
    expect(game.core.over, isFalse);
    expect(game.core.continuesUsed, 1);
    expect(find.text('Continue'), findsNothing);

    game.core.score = 5000;
    game.core.forceGameOver();
    await seconds(tester, 1.2);
    expect(find.text('Continue'), findsNothing, reason: 'one continue per run');
    expect(find.text('Double coins'), findsOneWidget);
    final coins = rig.model.profile.coins;
    final runCoins = rig.model.profile.lastRunCoins;
    expect(runCoins, greaterThan(0));

    await tapText(tester, 'Double coins');
    expect(rig.model.profile.coins, coins + runCoins);
    expect(find.text('Double coins'), findsNothing);
    // A replayed callback cannot pay twice.
    expect(rig.model.doubleCoins(rig.model.profile.lastRewardedRun), 0);
    expect(rig.model.profile.coins, coins + runCoins);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed or abandoned rewarded ad: no reward, no freeze, game goes on', (tester) async {
    final rig = Rig(rewarded: true, grant: false);
    await launch(tester, rig);
    await tapText(tester, 'Endless');
    final game = board(tester);
    await dropAt(tester, 100);
    game.core.forceGameOver();
    await seconds(tester, 1.2);
    await tapText(tester, 'Continue');
    expect(game.core.over, isTrue);
    expect(find.text('Play again'), findsOneWidget);
    expect(rig.model.profile.runs, 1);
    await frames(tester, 150);
    await tapText(tester, 'Play again');
    expect(board(tester).core.over, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continue prompt times out on its own', (tester) async {
    final rig = Rig(rewarded: true);
    await launch(tester, rig);
    await tapText(tester, 'Endless');
    board(tester).core.forceGameOver();
    await seconds(tester, 1.2);
    expect(find.text('Continue'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Continue'), findsNothing);
    expect(rig.model.profile.runs, 1);
    expect(rig.ads.rewardedShown, 0);
  });

  testWidgets('interstitial: only between runs, every third run, never after a rewarded ad', (tester) async {
    final rig = Rig();
    rig.store.text =
        (Profile()
              ..tutorialDone = true
              ..runs = 5
              ..rewardLastDate = 20261004
              ..rewardLastUtcMs = DateTime(2026, 10, 4, 12).toUtc().millisecondsSinceEpoch)
            .encode();
    await launch(tester, rig);
    await tapText(tester, 'Endless');
    for (var run = 1; run <= 3; run++) {
      board(tester).core.forceGameOver();
      await seconds(tester, 1.2);
      expect(rig.ads.interstitialsShown, 0, reason: 'nothing before the player asks for the next run');
      await tapText(tester, 'Play again');
      expect(rig.ads.interstitialsShown, run == 3 ? 1 : 0, reason: 'run $run');
    }
    expect(rig.model.profile.runsSinceInterstitial, 0);
    // Next one needs both three more runs and the cooldown.
    for (var run = 1; run <= 3; run++) {
      board(tester).core.forceGameOver();
      await seconds(tester, 1.2);
      await tapText(tester, 'Play again');
    }
    expect(rig.ads.interstitialsShown, 1, reason: 'cooldown not elapsed');
    rig.ads.now += 500;
    rig.ads.pacer.noteRewardedShown(rig.ads.now);
    board(tester).core.forceGameOver();
    await seconds(tester, 1.2);
    await tapText(tester, 'Play again');
    expect(rig.ads.interstitialsShown, 1, reason: 'never right after a rewarded ad');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pause, back button, and background keep the run; relaunch resumes it', (tester) async {
    final rig = Rig();
    await launch(tester, rig);
    await tapText(tester, 'Endless');
    final game = board(tester);
    for (var i = 0; i < 5; i++) {
      await dropAt(tester, 50.0 + i * 60);
    }
    final drops = game.core.drops;
    final score = game.core.score;

    // Rapid pause / resume.
    for (var i = 0; i < 6; i++) {
      await tester.binding.handlePopRoute();
      await frames(tester, 3);
    }
    expect(find.text('Paused'), findsNothing);
    await tester.binding.handlePopRoute();
    await frames(tester, 20);
    expect(find.text('Paused'), findsOneWidget);
    await shot(tester, 'pause');
    final time = game.core.time;
    await seconds(tester, 1);
    expect(game.core.time, time, reason: 'nothing moves while paused');
    // Taps on the board do nothing while paused.
    await tester.tapAt(const Offset(180, 700));
    expect(game.core.drops, drops);
    await tapText(tester, 'Resume');

    // App goes to the background in the middle of a run.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await frames(tester, 10);
    expect(find.text('Paused'), findsOneWidget);
    expect(rig.model.profile.activeRun, isNotNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await frames(tester, 10);

    // The process is killed: a new app instance over the same save file.
    final again = Rig(store: rig.store);
    await launch(tester, again);
    expect(find.text('Endless'), findsOneWidget);
    await tapText(tester, 'Endless');
    final restored = board(tester);
    expect(restored.core.drops, drops);
    expect(restored.core.score, score);
    expect(restored.core.bodies.length, game.core.bodies.length);
    expect(again.model.profile.activeRun, isNull, reason: 'a run can be resumed once, not duplicated');
    await dropAt(tester, 120);
    expect(restored.core.drops, drops + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spam tapping and multi-touch cannot break the cooldown or the state', (tester) async {
    final rig = Rig();
    await launch(tester, rig);
    await tapText(tester, 'Endless');
    final game = board(tester);
    for (var i = 0; i < 60; i++) {
      final a = await tester.startGesture(Offset(30.0 + (i * 37) % 300, 400));
      final b = await tester.startGesture(Offset(330.0 - (i * 53) % 300, 600));
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.core.drops, lessThanOrEqualTo((game.core.time / game.core.balance.dropCooldown).ceil() + 1));
    expect(game.core.drops, greaterThan(0));
    for (final o in game.core.bodies) {
      expect(o.x.isFinite && o.y.isFinite, isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily challenge: same pieces for the day, result banked, classic record untouched', (tester) async {
    final rig = Rig();
    await launch(tester, rig);
    await tapText(tester, 'Daily');
    final d = rig.model.todayChallenge;
    expect(find.text(dailyGoalText(rig.model, d)), findsOneWidget);
    await shot(tester, 'daily');
    await tapText(tester, 'Start');
    final game = board(tester);
    expect(game.core.dropLimit, d.dropLimit);
    expect(game.core.currentPiece, d.createRun().currentPiece);
    await dropAt(tester, 100);
    game.core
      ..score = 999999
      ..maxLevel = 12
      ..maxChain = 9;
    game.core.forceGameOver();
    await seconds(tester, 1.2);
    expect(find.text('Completed'), findsOneWidget);
    expect(rig.model.dailyDoneToday, isTrue);
    expect(rig.model.profile.bestScore, 0);
    expect(rig.analytics.events, containsAll(['daily_started', 'daily_completed', 'game_over']));
    await tapText(tester, 'Home');
    expect(find.text('NOVALITH'), findsOneWidget);
    // The next calendar day brings a fresh challenge.
    rig.now = rig.now.add(const Duration(days: 1));
    expect(rig.model.dailyDoneToday, isFalse);
    expect(rig.model.todayChallenge.seed, isNot(d.seed));
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily reward: offered to a returning player, claimed once, survives a date rollback', (tester) async {
    final rig = Rig();
    rig.store.text =
        (Profile()
              ..runs = 3
              ..tutorialDone = true)
            .encode();
    await launch(tester, rig);
    await frames(tester, 20);
    expect(find.text('Daily reward'), findsOneWidget);
    await shot(tester, 'reward');
    await tapText(tester, 'Claim');
    expect(rig.model.profile.coins, rig.model.balance.dailyRewardCoins[0]);
    expect(rig.model.rewardStatus.state, RewardState.claimed);
    // Device date moved back: nothing to claim, nothing lost.
    rig.now = DateTime(2026, 9, 1, 12);
    expect(rig.model.claimReward(), 0);
    expect(rig.model.rewardStatus.state, RewardState.clockBehind);
    expect(rig.model.profile.rewardStreak, 1);
    rig.now = DateTime(2026, 10, 5, 12);
    expect(rig.model.claimReward(), rig.model.balance.dailyRewardCoins[1]);
  });

  testWidgets('shop, collection, achievements and settings work and persist', (tester) async {
    final rig = Rig();
    rig.store.text =
        (Profile()
              ..coins = 1000
              ..runs = 4
              ..discovered = {2, 3, 4, 5, 6}
              ..totalMerges = 120
              ..rewardLastDate = 20261004
              ..rewardLastUtcMs = DateTime(2026, 10, 4, 12).toUtc().millisecondsSinceEpoch)
            .encode();
    await launch(tester, rig);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);

    nav.push(MaterialPageRoute<void>(builder: (_) => const ShopScreen()));
    await frames(tester, 30);
    await shot(tester, 'shop');
    await tapText(tester, '400');
    expect(rig.model.profile.owned, contains('theme_neon'));
    expect(rig.model.profile.coins, 600);
    expect(rig.model.profile.theme, 'theme_neon', reason: 'a bought item is put on at once');
    expect(rig.analytics.events, contains('item_unlocked'));
    await tapText(tester, 'Backgrounds');
    await tapText(tester, formatNumber(1500));
    expect(rig.model.profile.owned.contains('bg_emerald'), isFalse, reason: 'not enough coins');
    expect(rig.model.profile.coins, 600);
    nav.pop();
    await frames(tester, 30);

    nav.push(MaterialPageRoute<void>(builder: (_) => const CollectionScreen()));
    await frames(tester, 30);
    expect(find.text('Gas Giant'), findsOneWidget);
    expect(find.text('Galaxy'), findsNothing, reason: 'undiscovered levels stay hidden');
    await shot(tester, 'collection');
    nav.pop();
    await frames(tester, 30);

    nav.push(MaterialPageRoute<void>(builder: (_) => const AchievementsScreen()));
    await frames(tester, 30);
    expect(find.text('Make 100 merges'), findsOneWidget);
    await shot(tester, 'achievements');
    nav.pop();
    await frames(tester, 30);

    nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await frames(tester, 30);
    await shot(tester, 'settings');
    await tapText(tester, 'Music');
    expect(rig.model.profile.music, isFalse);
    expect(rig.audio.musicOn, isFalse);
    await tapText(tester, 'Vibration');
    expect(rig.haptics.enabled, isFalse);
    await tapText(tester, 'Language');
    await tapText(tester, 'Русский');
    expect(find.text('Настройки'), findsOneWidget, reason: 'language switches instantly');
    expect(find.text('Settings'), findsNothing);

    // Everything above reached the save file.
    final reloaded = Profile.decode(rig.store.text).profile;
    expect(reloaded.language, 'ru');
    expect(reloaded.music, isFalse);
    expect(reloaded.haptics, isFalse);
    expect(reloaded.theme, 'theme_neon');
    expect(tester.takeException(), isNull);
  });

  for (final lang in languages) {
    testWidgets('${lang.code}: menu, game, result and settings lay out without overflow', (tester) async {
      final rig = Rig(rewarded: true);
      rig.store.text =
          (Profile()
                ..language = lang.code
                ..tutorialDone = false
                ..bestScore = 123456
                ..coins = 98765
                ..rewardLastDate = 20261004
                ..rewardLastUtcMs = DateTime(2026, 10, 4, 12).toUtc().millisecondsSinceEpoch)
              .encode();
      // A small phone: the hardest case for long translations.
      await launch(tester, rig, size: const Size(320, 640));
      expect(
        Directionality.of(tester.element(find.byType(Scaffold).first)),
        lang.rtl ? TextDirection.rtl : TextDirection.ltr,
      );
      final l = L10n(lang);
      expect(find.text(l.t('play').toUpperCase()), findsOneWidget);
      if (lang.code == 'ru' || lang.code == 'ar' || lang.code == 'zh') await shot(tester, 'menu_${lang.code}');

      await tapText(tester, l.t('endless'), intro: false);
      expect(find.text(l.t('how_title')), findsOneWidget);
      expect(find.text(l.t('how_3')), findsOneWidget);
      if (lang.code == 'ru' || lang.code == 'ar' || lang.code == 'de') await shot(tester, 'how_${lang.code}');
      await closeIntro(tester);
      expect(find.text(l.t('tut_aim')), findsOneWidget);
      final game = board(tester);
      await dropAt(tester, 100);
      await tester.binding.handlePopRoute();
      await frames(tester, 20);
      expect(find.text(l.t('paused')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await frames(tester, 20);
      game.core
        ..score = 54321
        ..merges = 300
        ..maxLevel = 9
        ..maxChain = 5;
      game.core.createdLevels.addAll([6, 7, 8, 9]);
      game.core.forceGameOver();
      await seconds(tester, 1.2);
      expect(find.text(l.t('continue_ad')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await frames(tester, 30);
      expect(find.text(l.t('play_again')), findsOneWidget);
      if (lang.code == 'ru' || lang.code == 'ar') await shot(tester, 'results_${lang.code}');
      await tapText(tester, l.t('home'));

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      for (final screen in const <Widget>[
        ShopScreen(),
        CollectionScreen(),
        AchievementsScreen(),
        SettingsScreen(),
        MapScreen(),
        GoalsScreen(),
      ]) {
        nav.push(MaterialPageRoute<void>(builder: (_) => screen));
        await frames(tester, 20);
        nav.pop();
        await frames(tester, 30);
      }
      await tapText(tester, l.t('daily'));
      expect(find.text(dailyGoalText(rig.model, rig.model.todayChallenge)), findsOneWidget);
      await tester.tapAt(const Offset(10, 40));
      await frames(tester, 30);

      // A campaign level and its result, in this language, on the same small phone.
      nav.push(MaterialPageRoute<void>(builder: (_) => GameScreen(level: campaignLevels.first)));
      await frames(tester, 30);
      final level = board(tester);
      level.core
        ..merges = 3
        ..score = 40;
      level.core.complete();
      await seconds(tester, 1.2);
      expect(find.text(l.t('level_complete')), findsOneWidget);
      expect(find.text(l.t('next_level')), findsOneWidget);
      if (lang.code == 'ru' || lang.code == 'ar') await shot(tester, 'level_result_${lang.code}');
      expect(tester.takeException(), isNull, reason: 'layout overflow or error in ${lang.code}');
    });
  }

  testWidgets('a long bot-played run renders every frame without errors (and yields screenshots)', (tester) async {
    final rig = Rig();
    rig.store.text =
        (Profile()
              ..tutorialDone = true
              ..bestScore = 6000
              ..rewardLastDate = 20261004
              ..rewardLastUtcMs = DateTime(2026, 10, 4, 12).toUtc().millisecondsSinceEpoch)
            .encode();
    await launch(tester, rig);
    await tapText(tester, 'Endless');
    final game = board(tester);
    final rng = SeededRng(7);
    var shotMerge = false;
    var shotDanger = false;
    var frame = 0;
    while (!game.core.over && frame < 20000) {
      if (game.core.canDrop && frame % 40 == 0) {
        // Play well for a while, then carelessly, so the run also shows danger and ends.
        final x = game.core.drops < 70 ? greedyBot(game.core, rng) : 170.0;
        game.aimX = x;
        game.release();
      }
      final merges = game.core.merges;
      await tester.pump(const Duration(milliseconds: 16));
      frame++;
      if (!shotMerge && game.core.merges > merges && game.core.maxLevel >= 7) {
        await frames(tester, 4);
        await shot(tester, 'game_merge');
        shotMerge = true;
      }
      if (!shotDanger && game.core.overflow > 0.5) {
        await shot(tester, 'game_danger');
        shotDanger = true;
      }
    }
    expect(game.core.over, isTrue);
    expect(game.core.drops, greaterThan(40));
    expect(game.activeParticles, lessThanOrEqualTo(420), reason: 'particle pool is bounded');
    await seconds(tester, 1.2);
    expect(find.text('Play again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Store screenshots: the real screens rendered at 1080x1920. Only produced on request.
  for (final code in ['en', 'ru']) {
    testWidgets('store screenshots ($code)', (tester) async {
      if (Platform.environment['NOVALITH_STORE_SHOTS'] != '1') return;
      GameScreen.debugTools = false;
      shotPixelRatio = 3;
      addTearDown(() {
        GameScreen.debugTools = true;
        shotPixelRatio = 2;
      });
      final rig = Rig();
      rig.store.text =
          (Profile()
                ..language = code
                ..tutorialDone = true
                ..coins = 2450
                ..level = 7
                ..xp = 180
                ..bestScore = 6200
                ..runs = 42
                ..totalMerges = 2310
                ..maxChain = 5
                ..maxLevel = 9
                ..discovered = {2, 3, 4, 5, 6, 7, 8, 9}
                ..achievements = {
                  'merges_10',
                  'merges_100',
                  'merges_1000',
                  'first_chain',
                  'chain_5',
                  'evo_6',
                  'evo_8',
                  'score_5k',
                  'runs_10',
                }
                ..owned = {'theme_cosmos', 'bg_deep', 'theme_neon', 'bg_nebula', 'bg_dawn'}
                ..rewardLastDate = 20261004
                ..rewardLastUtcMs = DateTime(2026, 10, 4, 12).toUtc().millisecondsSinceEpoch)
              .encode();
      await launch(tester, rig, size: const Size(360, 640));
      final l = rig.model.l10n;
      await tester.runAsync(
        () => precacheImage(const AssetImage('assets/brand/logo.png'), tester.element(find.byType(Scaffold).first)),
      );
      await frames(tester, 10);
      await shot(tester, 'store_${code}_3_menu');

      await tapText(tester, l.t('endless'));
      final game = board(tester);
      final rng = SeededRng(11);
      var combo = false;
      var big = false;
      var frame = 0;
      while (!game.core.over && frame < 30000) {
        if (game.core.canDrop && frame % 40 == 0) {
          game.aimX = game.core.drops < 95 ? greedyBot(game.core, rng) : 170.0;
          game.release();
        }
        final before = game.core.merges;
        await tester.pump(const Duration(milliseconds: 16));
        frame++;
        final merged = game.core.merges > before;
        if (!combo && merged && game.core.chain >= 3 && game.core.maxLevel >= 6) {
          await frames(tester, 5);
          await shot(tester, 'store_${code}_1_combo');
          combo = true;
        }
        if (!big && merged && game.core.maxLevel >= 8 && game.core.bodies.length > 12) {
          await frames(tester, 4);
          await shot(tester, 'store_${code}_2_evolve');
          big = true;
        }
      }
      game.core.score = game.core.score < 6400 ? 7380 : game.core.score;
      await seconds(tester, 1.4);
      await frames(tester, 50);
      await shot(tester, 'store_${code}_4_record');
      await tapText(tester, l.t('home'));

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => const CollectionScreen()));
      await frames(tester, 40);
      await shot(tester, 'store_${code}_5_collection');
      nav.pop();
      await frames(tester, 40);
      nav.push(MaterialPageRoute<void>(builder: (_) => const ShopScreen()));
      await frames(tester, 40);
      await shot(tester, 'store_${code}_6_shop');
      nav.pop();
      await frames(tester, 40);
      await tapText(tester, l.t('daily'));
      await frames(tester, 30);
      await shot(tester, 'store_${code}_7_daily');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('corrupted save on disk: the app still starts and stays usable', (tester) async {
    final rig = Rig();
    rig.store.text = '{"v":1,"coins":"NaN","stats":[1,2,3],"activeRun":{"bodies":"x"},"settings":7';
    await launch(tester, rig);
    expect(find.text('NOVALITH'), findsOneWidget);
    expect(rig.model.loadStatus, LoadStatus.recovered);
    rig.store.text = '{"v":1,"coins":50,"activeRun":{"bodies":"x"},"level":"high"}';
    final again = Rig(store: rig.store);
    await launch(tester, again);
    expect(again.model.profile.coins, 50, reason: 'valid fields are preserved');
    await tapText(tester, 'Endless');
    expect(board(tester).core.drops, 0, reason: 'a broken run snapshot becomes a fresh run');
    await dropAt(tester, 150);
    expect(tester.takeException(), isNull);
  });
}
