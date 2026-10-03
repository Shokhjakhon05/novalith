/// The one object the UI talks to: owns the profile, the language and the optional services,
/// and persists every change.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/balance.dart';
import '../core/daily.dart';
import '../core/game_core.dart';
import '../core/profile.dart';
import '../core/progression.dart';
import '../l10n/l10n.dart';
import '../services/ads/ad_manager.dart';
import '../services/analytics.dart';
import '../services/feedback.dart';
import '../services/purchases.dart';
import '../services/save_store.dart';

class AppModel extends ChangeNotifier {
  AppModel({
    required this.store,
    required this.audio,
    required this.haptics,
    required this.ads,
    required this.analytics,
    required this.purchases,
    this.balance = Balance.standard,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SaveStore store;
  final AudioService audio;
  final Haptics haptics;
  final AdManager ads;
  final Analytics analytics;
  final PurchaseService purchases;
  final Balance balance;
  final DateTime Function() _clock;

  Profile profile = Profile();
  LoadStatus loadStatus = LoadStatus.fresh;
  L10n l10n = L10n(languages.first);
  String _deviceLocale = 'en';
  bool loaded = false;

  DateTime get now => _clock();

  /// Loads the save and wires the settings into the services. Never throws.
  Future<void> load(String deviceLocale) async {
    _deviceLocale = deviceLocale;
    final result = await store.load();
    profile = result.profile;
    loadStatus = result.status;
    grantLevelItems(profile);
    _applySettings();
    purchases.onRemoveAdsOwned = _onRemoveAdsOwned;
    loaded = true;
    notifyListeners();
  }

  void _applySettings() {
    l10n = L10n(resolveLanguage(profile.language, _deviceLocale));
    audio.sfxOn = profile.sfx;
    audio.setMusic(profile.music);
    haptics.enabled = profile.haptics;
  }

  String t(String key, [Map<String, Object> args = const {}]) => l10n.t(key, args);

  bool get rtl => l10n.language.rtl;

  String evoName(int level) => t('evo_${balance.level(level).key}');

  Future<void> save() => store.save(profile);

  void _changed() {
    notifyListeners();
    unawaited(save());
  }

  // --- Settings ---

  void setMusic(bool on) {
    profile.music = on;
    audio.setMusic(on);
    _changed();
  }

  void setSfx(bool on) {
    profile.sfx = on;
    audio.sfxOn = on;
    _changed();
  }

  void setHaptics(bool on) {
    profile.haptics = on;
    haptics.enabled = on;
    _changed();
  }

  void setShowNumbers(bool on) {
    profile.showNumbers = on;
    _changed();
  }

  /// Empty code = follow the device. Takes effect immediately.
  void setLanguage(String code) {
    profile.language = code;
    l10n = L10n(resolveLanguage(code, _deviceLocale));
    _changed();
  }

  void completeTutorial() {
    if (profile.tutorialDone) return;
    profile.tutorialDone = true;
    _changed();
  }

  void _onRemoveAdsOwned() {
    if (profile.removeAds) return;
    profile.removeAds = true;
    _changed();
  }

  // --- Shop ---

  BuyResult buy(String id) {
    final result = buyItem(profile, id);
    if (result == BuyResult.ok) {
      analytics.log('item_unlocked', {'item': id});
      audio.play(Sfx.unlock);
      equipItem(profile, id);
      _changed();
    }
    return result;
  }

  void equip(String id) {
    if (equipItem(profile, id)) _changed();
  }

  // --- Daily ---

  DailyChallenge get todayChallenge => DailyChallenge.forDate(dateKeyOf(now));

  bool get dailyDoneToday => profile.dailyDate == dateKeyOf(now) && profile.dailyDone;

  int get dailyBestToday => profile.dailyDate == dateKeyOf(now) ? profile.dailyBest : 0;

  DailyRewardStatus get rewardStatus => dailyRewardStatus(profile, now, now.toUtc(), balance: balance);

  int claimReward() {
    final coins = claimDailyReward(profile, now, now.toUtc(), balance: balance);
    if (coins > 0) {
      audio.play(Sfx.coin);
      _changed();
    }
    return coins;
  }

  // --- Runs ---

  /// Keeps an unfinished classic run so the player can come back to it after the app is closed.
  void storeActiveRun(GameCore core) {
    profile.activeRun = core.over ? null : core.toJson();
    unawaited(save());
  }

  /// Takes the stored run out of the profile (it is either resumed now or gone).
  GameCore? takeActiveRun() {
    final raw = profile.activeRun;
    if (raw == null) return null;
    profile.activeRun = null;
    return GameCore.fromJson(raw, balance: balance);
  }

  RunOutcome? finishRun(GameCore core, String runId, {DailyChallenge? daily}) {
    final outcome = applyRun(profile, core, runId: runId, daily: daily, balance: balance);
    if (outcome == null) return null;
    profile.activeRun = null;
    analytics.log('game_over', {'score': core.score, 'drops': core.drops, 'daily': daily != null});
    if (outcome.dailyCompletedNow) analytics.log('daily_completed');
    _changed();
    return outcome;
  }

  int doubleCoins(String runId) {
    final coins = doubleRunCoins(profile, runId);
    if (coins > 0) {
      analytics.log('double_reward_used');
      audio.play(Sfx.coin);
      _changed();
    }
    return coins;
  }

  void noteInterstitialShown() {
    profile.runsSinceInterstitial = 0;
    unawaited(save());
  }

  /// Debug tool: wipes all progress.
  Future<void> resetAll() async {
    await store.reset();
    profile = Profile();
    _applySettings();
    notifyListeners();
  }
}

/// Makes the [AppModel] available to the widget tree and rebuilds dependants on change.
class AppScope extends InheritedNotifier<AppModel> {
  const AppScope({super.key, required AppModel model, required super.child}) : super(notifier: model);

  static AppModel of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// For callbacks: reads the model without subscribing to rebuilds.
  static AppModel read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
