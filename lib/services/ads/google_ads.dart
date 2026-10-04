/// Google Mobile Ads implementation of [AdManager]. This is the only file (with its two
/// services below) that imports the SDK.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/ad_policy.dart';
import '../../core/balance.dart';
import '../analytics.dart';
import 'ad_config.dart';
import 'ad_manager.dart';

/// Loads and shows the reward ad. Works with either AdMob reward format (see [AdConfig]); the
/// rest of the game only sees "ready" and "show -> earned or not".
class RewardedAdService {
  RewardedAd? _rewarded;
  RewardedInterstitialAd? _rewardedInterstitial;
  bool _loading = false;
  int _failures = 0;
  Timer? _retry;

  bool get ready => _rewarded != null || _rewardedInterstitial != null;

  void load() {
    if (_loading || ready) return;
    _loading = true;
    void failed() {
      _loading = false;
      _scheduleRetry();
    }

    void loaded() {
      _loading = false;
      _failures = 0;
    }

    try {
      if (AdConfig.rewardedIsInterstitial) {
        RewardedInterstitialAd.load(
          adUnitId: AdConfig.rewardedUnitId,
          request: const AdRequest(),
          rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
            onAdLoaded: (ad) {
              _rewardedInterstitial = ad;
              loaded();
            },
            onAdFailedToLoad: (error) => failed(),
          ),
        ).catchError((_) => failed());
      } else {
        RewardedAd.load(
          adUnitId: AdConfig.rewardedUnitId,
          request: const AdRequest(),
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (ad) {
              _rewarded = ad;
              loaded();
            },
            onAdFailedToLoad: (error) => failed(),
          ),
        ).catchError((_) => failed());
      }
    } catch (_) {
      failed();
    }
  }

  void _scheduleRetry() {
    _failures++;
    _retry?.cancel();
    // 10 s, 20 s, 40 s ... capped at 5 minutes: never hammer the network.
    final seconds = (10 * (1 << (_failures - 1).clamp(0, 5))).clamp(10, 300);
    _retry = Timer(Duration(seconds: seconds), load);
  }

  /// Completes exactly once: true if the reward callback fired before the ad closed.
  Future<bool> show() {
    final rewarded = _rewarded;
    final interstitial = _rewardedInterstitial;
    if (rewarded == null && interstitial == null) return Future.value(false);
    _rewarded = null;
    _rewardedInterstitial = null;
    final done = Completer<bool>();
    var earned = false;
    void finish() {
      if (!done.isCompleted) done.complete(earned);
      load();
    }

    try {
      if (interstitial != null) {
        interstitial.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            finish();
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            finish();
          },
        );
        interstitial.show(onUserEarnedReward: (_, _) => earned = true).catchError((_) => finish());
      } else {
        rewarded!.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            finish();
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            finish();
          },
        );
        rewarded.show(onUserEarnedReward: (_, _) => earned = true).catchError((_) => finish());
      }
    } catch (_) {
      finish();
    }
    return done.future;
  }
}

class InterstitialAdService {
  InterstitialAd? _ad;
  bool _loading = false;
  int _failures = 0;
  Timer? _retry;

  bool get ready => _ad != null;

  void load() {
    if (_loading || _ad != null) return;
    _loading = true;
    try {
      InterstitialAd.load(
        adUnitId: AdConfig.interstitialUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _ad = ad;
            _loading = false;
            _failures = 0;
          },
          onAdFailedToLoad: (error) {
            _loading = false;
            _scheduleRetry();
          },
        ),
      ).catchError((_) {
        _loading = false;
        _scheduleRetry();
      });
    } catch (_) {
      _loading = false;
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _failures++;
    _retry?.cancel();
    final seconds = (15 * (1 << (_failures - 1).clamp(0, 5))).clamp(15, 300);
    _retry = Timer(Duration(seconds: seconds), load);
  }

  /// Completes when the ad is closed; false if nothing could be shown.
  Future<bool> show() {
    final ad = _ad;
    if (ad == null) return Future.value(false);
    _ad = null;
    final done = Completer<bool>();
    void finish(bool shown) {
      if (!done.isCompleted) done.complete(shown);
      load();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        finish(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        finish(false);
      },
    );
    try {
      ad.show().catchError((_) => finish(false));
    } catch (_) {
      finish(false);
    }
    return done.future;
  }
}

class GoogleAdManager implements AdManager {
  GoogleAdManager({required this.analytics, Balance balance = Balance.standard})
    : _pacer = InterstitialPacer(balance: balance);

  final Analytics analytics;
  final InterstitialPacer _pacer;
  final RewardedAdService _rewarded = RewardedAdService();
  final InterstitialAdService _interstitial = InterstitialAdService();
  final Stopwatch _clock = Stopwatch()..start();
  bool _started = false;
  bool _showing = false;
  bool _privacyOptions = false;

  double get _now => _clock.elapsedMilliseconds / 1000;

  @override
  Future<void> init() async {
    try {
      // Consent first (UMP). In regions without a consent requirement this is a no-op.
      final info = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => info.complete(),
        (error) => info.complete(),
      );
      await info.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      final form = Completer<void>();
      await ConsentForm.loadAndShowConsentFormIfRequired((error) => form.complete());
      await form.future.timeout(const Duration(minutes: 5), onTimeout: () {});
      _privacyOptions =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      if (await ConsentInformation.instance.canRequestAds()) await _start();
    } catch (e) {
      debugPrint('ads init failed: $e');
    }
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    await MobileAds.instance.initialize();
    _rewarded.load();
    _interstitial.load();
  }

  @override
  bool get rewardedReady => _started && _rewarded.ready && !_showing;

  @override
  Future<bool> showRewarded(String placement) async {
    if (!rewardedReady) {
      analytics.log('rewarded_failed', {'placement': placement, 'reason': 'not_ready'});
      return false;
    }
    _showing = true;
    analytics.log('rewarded_started', {'placement': placement});
    var earned = false;
    try {
      earned = await _rewarded.show();
    } catch (_) {
      earned = false;
    } finally {
      _showing = false;
    }
    _pacer.noteRewardedShown(_now);
    analytics.log(earned ? 'rewarded_completed' : 'rewarded_failed', {'placement': placement});
    return earned;
  }

  @override
  Future<bool> maybeShowInterstitial({
    required int runsSince,
    required int totalRuns,
    required bool removeAds,
    required bool tutorialDone,
  }) async {
    if (!_started || _showing || !_interstitial.ready) return false;
    if (!_pacer.shouldShow(
      runsSince: runsSince,
      totalRuns: totalRuns,
      nowSec: _now,
      removeAds: removeAds,
      tutorialDone: tutorialDone,
    )) {
      return false;
    }
    _showing = true;
    var shown = false;
    try {
      shown = await _interstitial.show();
    } catch (_) {
      shown = false;
    } finally {
      _showing = false;
    }
    if (shown) _pacer.noteInterstitialShown(_now);
    return shown;
  }

  @override
  bool get privacyOptionsRequired => _privacyOptions;

  @override
  Future<void> showPrivacyOptions() async {
    try {
      final done = Completer<void>();
      await ConsentForm.showPrivacyOptionsForm((error) => done.complete());
      await done.future.timeout(const Duration(minutes: 5), onTimeout: () {});
      if (await ConsentInformation.instance.canRequestAds()) await _start();
    } catch (e) {
      debugPrint('privacy options failed: $e');
    }
  }
}
