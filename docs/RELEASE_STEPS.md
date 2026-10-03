# What is left before publishing

Everything in the repository is done and builds in CI. These steps need accounts, money or a
person, so they were left for the owner.

1. **Real-device check** - `docs/DEVICE_CHECKLIST.md` (15 minutes).
2. **Name / package** - confirm "Novalith" and `com.novalith.game`. The package cannot be
   changed after the first upload. No trademark search was done.
3. **AdMob** - create the app and two ad units (Rewarded, Interstitial) at apps.admob.com. Put
   the ids into repository secrets: `ADMOB_APP_ID`, `REWARDED_AD_UNIT_ID`,
   `INTERSTITIAL_AD_UNIT_ID`. In AdMob -> Privacy & messaging, create and publish the European
   regulations (GDPR) message; without it the consent form has nothing to show. Add the app to
   `app-ads.txt` on the developer website.
4. **Upload key** - generate a keystore (do not reuse another app's key unless you mean to) and
   store it in the secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
   `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Keep a private backup of the keystore.
5. **Build** - `gh workflow run ci.yml`, download `novalith-release-aab`.
6. **Play Console** - create the app; upload the AAB to a closed test track.
   - Store listing: `docs/store/LISTING.md` (16 languages), `play_icon_512.png`,
     `feature_graphic_1024x500.png`, screenshots from the phone.
   - Privacy policy: publish `docs/PRIVACY_POLICY.md` at a public URL (the other apps use a
     `*-privacy` GitHub Pages repository) and paste the link.
   - Data safety: `docs/DATA_SAFETY.md`. Ads: yes. Content rating questionnaire. Target age 13+.
   - In-app product: a managed product with id `remove_ads` (Monetize -> Products). Until it
     exists and is active, the "Remove ads" button simply stays hidden.
7. **Closed testing** - a personal developer account created after November 2023 needs
   12 testers for 14 days before production access can be requested.
8. **Production** - promote the tested build.

## Worth tuning after the first players (all in `lib/core/balance.dart`)

| Parameter | Now | Watch for |
|---|---|---|
| `levels[].radius` | 17 .. 100 | Runs too short or too long (target: 1.5-4 minutes) |
| `spawnWeights` | 35/30/20/10/5 | Board clogging with small pieces |
| `overflowTime` | 2.0 s | Deaths that feel unfair (raise) or runs that never end (lower) |
| `friction`, `contactDamping` | 0.12, 0.965 | Pile feels too sticky or too slippery |
| `comboWindow`, `comboMultipliers` | 1.0 s; 1,2,3,5,6,8 | Combos too rare to notice or too easy |
| `perfectBonusFactor` | 2.0 | Whether players notice and chase PERFECT |
| `pointsPerCoin`, shop prices | 200; 300 .. 6000 | First purchase should take about 5 runs; the full shop about 3-4 weeks |
| `interstitialEveryRuns`, `interstitialCooldownSec` | 3; 120 s | Reviews that mention ads |
| `continueGrace`, `continueClearMaxLevel` | 3 s; level 3 | Whether a continue actually saves the run |
| Daily targets (`lib/core/daily.dart`) | bot-calibrated | Completion rate; aim for roughly half of the attempts |
