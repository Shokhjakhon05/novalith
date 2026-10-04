# Verification matrix

Requirement -> how it was checked -> result. "CI" means the check runs in the GitHub Actions
workflow `ci.yml`; the run that verified the current code is linked at the bottom.

Legend: **Pass** = an automated check exists and is green. **Built** = implemented and
compiled, but its real behaviour needs a device or an external account. **Not checked** = no
evidence either way.

## Game

| Requirement | Checked by | Result |
|---|---|---|
| A + A -> B removes both sources, creates one body, scores once, one event | `game_core_test` "A + A -> B exactly once" | Pass |
| No double merge when three twins touch | `game_core_test` "three touching twins" | Pass |
| Chain reactions multiply the score; chain expires | `game_core_test` "chain reaction", "chain expires" | Pass |
| Big bang for two top-level bodies | `game_core_test`, `stress_test` | Pass |
| Adding level 13 needs no engine change | `game_core_test` "a 13th level" | Pass |
| Perfect drop rewarded | `game_core_test` "perfect drop" | Pass |
| Next piece always shown and is what gets dropped | `game_core_test` "dropped piece is the previewed piece"; HUD in `app_test` | Pass |
| Physics: no tunnelling, escape, overlap blow-up, NaN, jitter-forever | `stress_test` (1000 random games in CI, invariants on every step) | Pass |
| Deterministic for a seed | `game_core_test` "determinism", `stress_test` "identical on a re-run" | Pass |
| Fair spawner: weights, no long repeats, opening pair, recovery weighting, seeds | `spawner_test` (7 tests) | Pass |
| Safe spawn validation | `game_core_test` "safe spawn" | Pass |
| Overflow needs 2 s above the line; falling pieces do not count | `game_core_test` group "game over" | Pass |
| Game over -> new run in one tap | `app_test` "first launch" | Pass (timing on a device: Not checked) |
| Skill beats luck, short runs, early first merge | `balance_test`, `docs/BALANCE_REPORT.md` (1000 games per bot) | Pass |
| The loop feels satisfying; 60 FPS on a mid-range phone | - | **Not checked** (needs a device) |

## Retention

| Requirement | Checked by | Result |
|---|---|---|
| XP, levels, level rewards | `progression_test` "xp levels up" | Pass |
| Achievements are data-driven, unlock and pay once | `progression_test` | Pass |
| Daily challenge: same date -> same challenge and pieces; no adaptive weighting | `progression_test` group "daily challenge" | Pass |
| Daily targets are reachable but not trivial | `progression_test` "targets are reachable" (bot) | Pass |
| Personal best kept; never shown as a global rank | `progression_test`, UI shows "Your best" only | Pass |
| Daily reward: 7-day cycle, persisted streak, date tampering, time zones | `progression_test` group "daily reward", `app_test` | Pass |
| Shop: buy, own, equip; cosmetics only | `progression_test` group "shop", `app_test` | Pass |
| Collection of discovered evolutions | `app_test` "shop, collection..." | Pass |
| Economy: first purchase soon, full shop takes weeks | `progression_test` "economy" (bot simulation) | Pass |
| Onboarding by doing, persisted | `app_test` "first launch" | Pass |

## Monetization

| Requirement | Checked by | Result |
|---|---|---|
| One rewarded continue per run; state after continue is valid | `game_core_test`, `stress_test` "continue never leaves an impossible state", `app_test` | Pass |
| 2x coins once; idempotent against duplicate callbacks | `progression_test`, `app_test` | Pass |
| Failed / closed ad: no penalty, no freeze | `app_test` "failed or abandoned rewarded ad" | Pass |
| Interstitial: between runs only, every 3rd run, cooldown, not after rewarded, not in onboarding | `progression_test` "ads policy", `app_test` "interstitial" | Pass |
| Gameplay code does not import the ads SDK | Only `lib/services/ads/google_ads.dart` imports it (grep) | Pass |
| Test ad ids by default, production ids injected, no secrets in the repo | `lib/services/ads/ad_config.dart`, `android/app/build.gradle.kts`, CI secrets | Pass |
| Real rewarded / interstitial ads show and pay | - | **Built** (needs a device) |
| UMP consent form | - | **Built** (needs a device and an AdMob message) |
| "Remove ads" purchase | - | **Built** (needs the Play Console product) |

## Technical

| Requirement | Checked by | Result |
|---|---|---|
| Versioned save with migration chain | `profile_test` "migrations run in order", "failing or missing migration" | Pass |
| Corrupted data: detect, recover, keep what is valid, never crash | `profile_test` (incl. 3000 fuzzed saves), `app_test` "corrupted save" | Pass |
| Atomic save; interrupted save harmless; backup | `save_store_test` (8 tests) | Pass |
| Unfinished run survives the app being killed | `app_test` "pause, back button, and background" | Pass |
| Offline: no network needed for anything | all tests run with ads off; no network code in `lib/core`, `lib/game`, `lib/ui` | Pass |
| Lifecycle: pause, resume, background | `app_test` | Pass (audio focus on a device: Not checked) |
| Analytics behind an interface, all 16 events, replaceable | `lib/services/analytics.dart`; events asserted in `app_test` | Pass |
| 16 languages complete, same placeholders, instant switch, fallback to English | `l10n_test` (20 tests), `app_test` (16 layout tests + language switch) | Pass |
| No layout overflow on a 320x640 screen in any language | `app_test` per-language tests | Pass |
| Non-Latin scripts render with real glyphs | - | **Not checked** (test environment has no such fonts; a phone has) |
| Right-to-left layout for Arabic and Urdu | `app_test` (direction asserted) | Pass |
| Accessibility: non-colour indicators, toggles, large targets | level numbers option, slash on "off" toggles, 48 dp buttons | Pass by inspection |
| Bounded effects (particle pool, text cap) | `app_test` "a long bot-played run" | Pass |
| Stress: thousands of games, drops, merges, extreme chains, random boards | `stress_test` (7 tests) | Pass |
| No analyzer issues; formatted | CI "Static analysis", "Formatting" | Pass |

## Release

| Requirement | Checked by | Result |
|---|---|---|
| Reproducible CI: pinned Flutter 3.47.5, cached, clear failures, artifacts | `.github/workflows/ci.yml` | Pass |
| Release APK and App Bundle build | CI job "Release APK and App Bundle" | Pass |
| No debug tools in the release binary | CI step "No debug tooling in the release binary" | Pass |
| No placeholder assets or text | all art and audio generated; `l10n_test` rejects empty / TODO strings | Pass |
| No secrets committed | `.gitignore` (keystores, key.properties); ids via secrets | Pass |
| Application id, versioning, adaptive icon, splash, R8 | `android/` | Built (look of the icon and splash on a launcher: Not checked) |
| Privacy policy, Data safety, store listing | `docs/` | Written; must be published / entered by the owner |
| Runs on a real device | - | **Not checked** |

## CI run

Run **37183789697** on commit `7ef5453` - all three jobs green:
https://github.com/Shokhjakhon05/novalith/actions/runs/37183789697

| Step | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | Pass |
| `flutter analyze` | Pass, no issues |
| `flutter test` with `NOVALITH_GAMES=1000` | Pass |
| `flutter build apk --release` | Pass - 53.8 MB universal APK (three ABIs) |
| `flutter build appbundle --release` | Pass - 55.8 MB bundle, versionCode 6 |
| Debug panel strings absent from `libapp.so` | Pass |
| Emulator (Android 14, x86_64): install, launch, play, pause, background, resume | Pass - process alive, no fatal exception from the app |

Checked on the downloaded artifacts: package `com.novalith.game`; signed with the Novalith
upload key (not the debug key); the manifest carries the production AdMob app id and the binary
the two production ad unit ids; native libraries are aligned for 16 KB pages.

## The launch crash of 4 October 2026

The first APK crashed on a real phone before its first frame. An emulator run reproduced it:
`Failed to create an instance of androidx.work.impl.WorkDatabase` inside
`androidx.startup.InitializationProvider`. R8 had removed the constructor of the Room database
that WorkManager (pulled in by the ads SDK) creates by reflection at process start. Fixed with
keep rules in `android/app/proguard-rules.pro`. None of the earlier checks could see this -
unit and widget tests do not run the shrunk Android binary - so the pipeline now installs and
launches every built APK on an emulator.

Still **not checked**: a physical phone after the fix, real ads, the consent form, the purchase,
audio by ear, non-Latin fonts on a device.
