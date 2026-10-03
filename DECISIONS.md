# Decisions

Short record of the choices made where the brief left room, and why.

| # | Decision | Why |
|---|---|---|
| 1 | **Name: Novalith** ("nova" + "lith", star-stone), subtitle "Cosmic Merge". Package `com.novalith.game`. | Short, pronounceable in all target languages, no game with this name turned up in a web search. No trademark search was done - that needs a human. |
| 2 | **Own circle solver instead of Forge2D/Box2D.** Verlet integration with position constraints, fixed 1/120 s step. | Every body is a circle. A purpose-built solver is fully deterministic, has no native code, stacks without jitter, and is small enough to test exhaustively. |
| 3 | **Radii smaller than the brief's starting table** (17..100 instead of 13..114) and compressed at the top. | With the original table two top-level bodies cannot physically fit in the container, so the big bang would be impossible. |
| 4 | **Score for a merge is tetrahedral** (`n(n+1)(n+2)/6`) instead of triangular. | Makes high evolutions clearly worth more; widened the skilled/unskilled gap to the target. |
| 5 | **A combo chain belongs to one drop** (releasing the next piece resets it), window 1.0 s. | With a pure time window, steady dropping kept the chain alive forever and x8 multipliers were routine. |
| 6 | **Contact friction** added to the solver. | Without it piles flowed like marbles and random play merged almost as well as careful play. |
| 7 | **Sub-pixel deterministic offset on each drop.** | Pieces dropped on the exact same spot balanced in a perfect tower up to the line. |
| 8 | **Opening pair within the first 3 pieces** (brief: 6). | First merge by the third or fourth drop. |
| 9 | **Daily challenge: adaptive spawning off, limited drops, three goal types.** Only the piece sequence is fixed by the date; physics depends on the player. | Same day = same pieces for everyone, as required. |
| 10 | **Daily reward: a gap of up to 2 calendar days keeps the streak; a new claim needs 6 real hours; clock set back = nothing claimable, streak untouched.** | Time-zone travel can make two honest consecutive claims look two days apart; date tricks must not pay. |
| 11 | **Rewarded continue only in classic mode.** | A daily attempt must be comparable between players. |
| 12 | **Rewards are applied when the run really ends** (after the continue offer), guarded by a run id; 2x coins doubles only the run's own coins. | "Exactly once" for coins, XP, achievements and doubling. |
| 13 | **Localisation by plain Dart maps**, not gen-l10n. | Instant language switch, no generated code, and one test checks that all 16 languages have every key and the same placeholders. |
| 14 | **16 languages**: English, Chinese, Hindi, Spanish, French, Arabic, Bengali, Portuguese, Russian, Urdu, Indonesian, German, Japanese, Turkish, Vietnamese + Uzbek. | The most widely spoken languages that Google Play can serve, plus the owner's own. Nigerian Pidgin, Marathi and Telugu have more speakers than Turkish/Vietnamese but no or weaker store support. |
| 15 | **Text is drawn with Exo 2 (Latin, Cyrillic) and the system font for every other script.** | One 300 KB font instead of bundling CJK/Arabic/Indic fonts (tens of MB). |
| 16 | **Analytics ships as a no-op.** The interface and all events exist; no SDK is linked. | No data collection to declare, nothing that can fail. Plugging in a backend is one class. |
| 17 | **CI is started by hand** (`workflow_dispatch`). | The owner's Actions minutes are limited; a full run plays thousands of bot games and builds twice. |
| 18 | **Cosmetics: two categories** (body themes, backgrounds), 12 items. Trails and merge effects were dropped. | Scope cut in favour of core polish, as the brief allows. |
| 19 | **"Remove ads" removes interstitials only.** | Rewarded ads are the player's own choice and give them something. |
| 20 | **The record is always visible in the HUD as a progress bar.** | The cheapest honest "one more run" hook: you see how close you are. |
