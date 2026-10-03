# Progress

Milestone log. Each milestone lists what was built and what its gate actually checked.

## M1 - Core (done)

Pure-Dart simulation in `lib/core/`: Verlet circle physics on a fixed 1/120 s step, atomic
merges, chain reactions, big bang, perfect drop, overflow with countdown, one rewarded continue,
fair seeded spawner, run snapshots.

Gate: `test/core/game_core_test.dart`, `spawner_test.dart`, `stress_test.dart` - merge exactly
once, determinism, no NaN / escape / runaway entities over thousands of automated games.

## M2 - Feel (done)

Procedural art for 12 bodies in 6 themes and 6 backgrounds (`lib/game/sprites.dart`), the Flame
board with particles, rings, floating score, squash, shake, slow motion before overflow, rising
merge notes, haptics; HUD with the record always in sight; contextual three-step onboarding;
result card; pause.

Gate: bot metrics in `docs/BALANCE_REPORT.md`; end-to-end widget tests in `test/app_test.dart`;
release APK builds in CI.

## M3 - Reliability and money (done)

Versioned save with a migration chain, per-field recovery, atomic file writes and a backup;
unfinished run restored after the app is killed (autosave every 5 drops and on background).
`AdManager` abstraction with Google implementation (UMP consent, rewarded, interstitial with
pacing rules), "Remove ads" purchase, analytics interface with a no-op default.

Gate: `profile_test.dart` (corruption, fuzzing, migrations), `save_store_test.dart` (interrupted
save, backup), `progression_test.dart` (idempotent rewards, ad pacing), `app_test.dart` (failed
ad, duplicate callback, relaunch).

## M4 - Reasons to return (done)

Daily challenge from the date (3 goal types, fixed pieces), 7-day reward with clock-tamper and
time-zone rules, 21 data-driven achievements, XP and levels, shop with 12 cosmetics, collection.

Gate: `progression_test.dart` (same date = same challenge, economy simulation: first purchase
within 8 runs, full shop takes more than 3 weeks), `app_test.dart`.

## M5 - Release (done, as far as a repository can go)

Adaptive icon, splash, `com.novalith.game`, R8, optional upload-key signing from CI secrets,
APK + AAB artifacts, check that debug tooling is absent from the release binary. Privacy policy,
Data safety answers, store listing in 16 languages, store graphics.

Gate: CI run green end to end (see `docs/VERIFICATION.md` for the run link).

## Not done / open

- Nobody has played it on a phone or heard the audio: `docs/DEVICE_CHECKLIST.md`.
- Translations were not reviewed by native speakers.
- Trails and merge-effect cosmetics were cut (see `DECISIONS.md` #18).
- Publishing steps that need accounts: `docs/RELEASE_STEPS.md`.
