/// The only door between the game and advertising. Gameplay code talks to [AdManager] and
/// never imports the Google Mobile Ads SDK; swapping the network means replacing one file.
library;

import '../../core/ad_policy.dart';

abstract class AdManager {
  /// Asks for consent where required, then starts the SDK and preloads ads. Never throws and
  /// must not be awaited by anything the player is waiting for.
  Future<void> init();

  /// A rewarded ad is loaded and can be shown right now.
  bool get rewardedReady;

  /// Shows a rewarded ad. Completes with true only when the reward was earned; false when the
  /// ad was unavailable, failed or was closed early. Never throws.
  Future<bool> showRewarded(String placement);

  /// Shows an interstitial if the pacing rules allow one and an ad is loaded. Completes when
  /// the ad is closed (or immediately when nothing was shown). True = an ad was shown.
  Future<bool> maybeShowInterstitial({
    required int runsSince,
    required int totalRuns,
    required bool removeAds,
    required bool tutorialDone,
  });

  /// The user must be offered a way to change their consent choice (GDPR regions).
  bool get privacyOptionsRequired;
  Future<void> showPrivacyOptions();
}

/// Used in tests and whenever ads are switched off entirely: the game must run fine on this.
class NoAds implements AdManager {
  NoAds({this.rewardedAvailable = false, this.grantReward = true});

  bool rewardedAvailable;
  bool grantReward;
  int rewardedShown = 0;
  int interstitialsShown = 0;
  final InterstitialPacer pacer = InterstitialPacer();
  double now = 1000;

  @override
  Future<void> init() async {}

  @override
  bool get rewardedReady => rewardedAvailable;

  @override
  Future<bool> showRewarded(String placement) async {
    if (!rewardedAvailable) return false;
    rewardedShown++;
    pacer.noteRewardedShown(now);
    return grantReward;
  }

  @override
  Future<bool> maybeShowInterstitial({
    required int runsSince,
    required int totalRuns,
    required bool removeAds,
    required bool tutorialDone,
  }) async {
    if (!pacer.shouldShow(
      runsSince: runsSince,
      totalRuns: totalRuns,
      nowSec: now,
      removeAds: removeAds,
      tutorialDone: tutorialDone,
    )) {
      return false;
    }
    pacer.noteInterstitialShown(now);
    interstitialsShown++;
    return true;
  }

  @override
  bool get privacyOptionsRequired => false;

  @override
  Future<void> showPrivacyOptions() async {}
}
