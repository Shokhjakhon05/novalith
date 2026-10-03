/// When an ad may be shown, decided without touching any ad SDK - so the rules are testable.
library;

import 'balance.dart';

/// Decides whether an interstitial may be shown between runs.
class InterstitialPacer {
  InterstitialPacer({this.balance = Balance.standard});

  final Balance balance;
  double _lastInterstitial = -1e9;
  double _lastRewarded = -1e9;

  void noteInterstitialShown(double nowSec) => _lastInterstitial = nowSec;
  void noteRewardedShown(double nowSec) => _lastRewarded = nowSec;

  /// [runsSince] = finished runs since the last interstitial, [totalRuns] = lifetime runs.
  bool shouldShow({
    required int runsSince,
    required int totalRuns,
    required double nowSec,
    required bool removeAds,
    required bool tutorialDone,
  }) {
    if (removeAds || !tutorialDone) return false;
    if (totalRuns <= balance.interstitialSkipFirstRuns) return false;
    if (runsSince < balance.interstitialEveryRuns) return false;
    if (nowSec - _lastInterstitial < balance.interstitialCooldownSec) return false;
    if (nowSec - _lastRewarded < balance.interstitialAfterRewardedSec) return false;
    return true;
  }
}

/// Makes a reward callback idempotent: each token pays out once, however many times the SDK or
/// an app-lifecycle replay delivers it.
class RewardGate {
  final Set<String> _paid = {};

  bool grant(String token) => token.isNotEmpty && _paid.add(token);
}
