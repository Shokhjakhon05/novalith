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
  static const String rewardedUnitId = String.fromEnvironment(
    'REWARDED_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/5224354917',
  );

  static const String interstitialUnitId = String.fromEnvironment(
    'INTERSTITIAL_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );

  static bool get usingTestIds =>
      rewardedUnitId.startsWith('ca-app-pub-3940256099942544') ||
      interstitialUnitId.startsWith('ca-app-pub-3940256099942544');
}
