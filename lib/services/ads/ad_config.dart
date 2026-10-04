/// Ad unit ids. The defaults are Google's public test units, so a build made without any
/// configuration can never show (or click) real ads. Production ids are injected at build time:
///
///   flutter build appbundle \
///     --dart-define=REWARDED_AD_UNIT_ID=ca-app-pub-xxx/yyy \
///     --dart-define=INTERSTITIAL_AD_UNIT_ID=ca-app-pub-xxx/zzz
///
/// The AdMob *app* id is injected the same way through the ADMOB_APP_ID Gradle property
/// (see android/app/build.gradle.kts).
library;

class AdConfig {
  /// AdMob has two different reward formats and a unit of one cannot be loaded as the other:
  /// "rewarded_interstitial" (the unit created for Novalith) or "rewarded".
  static const String rewardedFormat = String.fromEnvironment(
    'REWARDED_AD_FORMAT',
    defaultValue: 'rewarded_interstitial',
  );

  static bool get rewardedIsInterstitial => rewardedFormat != 'rewarded';

  static const String _rewardedOverride = String.fromEnvironment('REWARDED_AD_UNIT_ID');

  /// Google's test unit for whichever reward format is configured.
  static String get rewardedUnitId => _rewardedOverride.isNotEmpty
      ? _rewardedOverride
      : (rewardedIsInterstitial ? 'ca-app-pub-3940256099942544/5354046379' : 'ca-app-pub-3940256099942544/5224354917');

  static const String interstitialUnitId = String.fromEnvironment(
    'INTERSTITIAL_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );

  static bool get usingTestIds =>
      rewardedUnitId.startsWith('ca-app-pub-3940256099942544') ||
      interstitialUnitId.startsWith('ca-app-pub-3940256099942544');
}
