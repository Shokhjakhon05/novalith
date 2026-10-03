# Final product review

After implementation the game was reviewed from five angles, then deliberately attacked. This
is what was found, how serious it was and what was done. "Fixed" means fixed and covered by a
test that failed before the fix; "open" means it cannot be settled without a phone or a person.

## Five reviews

**Game design - is the core loop satisfying?** The loop is aim, drop, impact, merge, chain,
evolve, manage space. The numbers say skill matters (a careful bot scores 2.76x a random one)
and runs are short (a careless run is about 80 drops, a little over a minute). Whether it
*feels* good in the hand is not something a test can say - open.

**UX - can a new player understand it immediately?** No text screens. Three hints appear in
context (slide, release, match two) and each disappears the moment the player does the thing.
The first three pieces always contain a pair. The tutorial test passes on a 320x640 screen in
all 16 languages.

**Retention - why play again tomorrow?** In ten seconds: a merge. In five minutes: the record,
which is always on screen as a filling bar, and "N to your record" on the result card. Daily:
a new challenge with the same pieces for everyone, and a 7-day reward. Long term: 12 evolutions
to discover, 21 achievements, 12 cosmetics. No energy, no timers, no notifications.

**Monetization - are ads useful rather than annoying?** Rewarded ads are offered only when one
is actually loaded and only for something the player wants (one continue, double coins).
Interstitials: never in the first two runs, never during play or onboarding, every third run at
most, at least 120 s apart, never within 60 s of a rewarded ad. "Remove ads" switches them off.

**Engineering - what can still crash, lag or rot?** The game rules are pure Dart and covered by unit,
property and stress tests; every optional subsystem sits behind an interface with guarded calls.
The untested part is the thin layer that talks to real plugins (Google ads, billing, audio),
which only a device can exercise - open.

## Weaknesses found

| # | Weakness | Why it matters | Severity | Status |
|---|---|---|---|---|
| 1 | Nobody has played it on a phone | Feel, input latency and frame rate are the product | High | **Open** - `DEVICE_CHECKLIST.md` |
| 2 | Real ad, consent and billing flows ran only against stand-ins | The Google implementation is compiled but not exercised | High | **Open** - checklist, test ads |
| 3 | Audio was synthesised without being heard | A harsh sound ruins "premium" instantly | Medium | **Open** - checklist; cheap to regenerate |
| 4 | Translations not reviewed by native speakers | Odd phrasing in 13 of 16 languages is likely somewhere | Medium | **Open** |
| 5 | Combo multiplier was trivial: steady dropping kept a chain alive, x8 was routine | Reward without skill; scores meaningless | High | Fixed - a chain belongs to one drop |
| 6 | Pieces dropped on one spot balanced in a perfect tower to the line | Looks broken; kills a tap-tap-tap beginner | High | Fixed - sub-pixel offset per drop |
| 7 | Daily reward dialog popped up over a game in progress | Interrupts play | High | Fixed - only on the menu |
| 8 | Result buttons were off-screen on small phones | "Play again" must never need scrolling | High | Fixed - buttons pinned, details scroll |
| 9 | Two top-level bodies could not fit in the container | The big bang was impossible | High | Fixed - radii compressed |
| 10 | Skill gap was 1.6-1.9x with frictionless physics | Luck decided runs | High | Fixed - friction, score curve, perfect bonus |
| 11 | Numbers reordered in Arabic and Urdu ("680 1") | Wrong scores shown | Medium | Fixed - no-break separator |
| 12 | Long labels overflowed the HUD in Arabic, Urdu, Hindi, Portuguese | Broken layout | Medium | Fixed |
| 13 | Danger warning could fire repeatedly around the threshold | Nagging sound and vibration | Low | Fixed - hysteresis |
| 14 | A run was saved only when the app went to background | A killed process lost the run | Medium | Fixed - autosave every 5 drops |
| 15 | Multi-stop gradients crashed sprite baking | Would have crashed on first launch | High | Fixed - caught by the render test |
| 16 | Run ids could collide when the clock did not advance | Second run would be paid nothing | Medium | Fixed - session counter |
| 17 | The big bang is far away: bots never passed level 10 of 12 | The headline moment may be seen by almost nobody | Medium | **Open** - tune radii after real data |
| 18 | Progress lives only on the device | Reinstall loses everything unless Android backup restores it | Low | Open by design (no backend) |
| 19 | Empty band between HUD and board on tall phones | Wasted space | Low | Reduced (wider board) |

## Red-team attempts

| Attack | Result | Where |
|---|---|---|
| Spam tapping, two fingers at once | Drops paced only by the cooldown; state stays valid | `app_test` "spam tapping", `stress_test` "input spam" |
| NaN / infinite / huge coordinates | Clamped; no NaN anywhere | `stress_test` "input spam" |
| Rapid pause / resume, back button mashing | Pause toggles cleanly, nothing moves while paused | `app_test` "pause, back button" |
| App to background mid-run | Paused, run stored | same |
| Process killed, relaunch | "Resume" restores drops, score and bodies; the run cannot be duplicated | same |
| Closed in the middle of a save | Previous save intact; temp file ignored | `save_store_test` |
| Corrupted / truncated / fuzzed save (3000 mutations) | Never throws; valid fields kept | `profile_test`, `app_test` "corrupted save" |
| Broken run snapshot | Refused, fresh run starts | `game_core_test`, `app_test` |
| Ad closed early / failed / unavailable | No reward, no freeze, play continues | `app_test` "failed or abandoned" |
| Reward callback delivered twice | Paid once | `progression_test`, `app_test` |
| Continue requested twice in one run | Second refused | `game_core_test`, `app_test` |
| Thousands of merges, maximum evolution, repeated big bangs | Consistent, score never negative | `stress_test` |
| Board stuffed with 140 overlapping twins | Settles; entity count falls | `stress_test` "extreme chain" |
| Random impossible board states | Simulated without NaN or escape | `stress_test` |
| No internet | Game unaffected; ad buttons simply absent | every `app_test` (ads off) |
| First launch / returning user | Both paths tested | `app_test` |
| Unsupported device language | Falls back to English | `l10n_test` |
| Device date moved back / forward, time-zone hop | No reward farming, honest streak kept | `progression_test`, `app_test` |
