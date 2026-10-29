# Keystone Isle — Content pipeline & post-launch roadmap

The game is fully offline. "Live ops" here means **content shipped in app updates** plus
calendar-seeded modes (Daily / Weekly) that feel fresh every day without any server. This doc
describes how to add content safely and what to ship after launch.

## 1. What is data, what is code

| Content | Where | Data-only? | Notes |
|---|---|---|---|
| Mutators (Daily/Weekly modifiers) | `data/mutators.json` | **Yes** | keys: `id, title, icon, blurb, score_mult, mul{}, add{}, set{}, from?` |
| Mode tuning (days, size, medals, census, XP, score weights) | `data/modes.json` | **Yes** | see "Retuning" rules below |
| Banners (cosmetics) | `data/cosmetics.json` | **Yes** | unlock by `level`, `medals`, `prestige` or `species` |
| Species codex text | `data/species.json` | Text yes, rule no | habitat rule in `Simulation.species_supported()`; effects (pollination, eggs, wolves, frogs) in the sim step and `_rare()` |
| Rare-event codex text + counterplay | `data/codex.json` | Text yes, rule no | trigger + damage live in `Simulation._rare()`; the codex `counter` text must describe the real rule |
| Campaign islands & challenges | `ScenarioCatalog.CAMPAIGN / CHALLENGES` | Code (GDScript dicts) | objectives use existing kinds (villagers, houses, keystone, survive, …) |
| Achievements | `scripts/simulation/achievements.gd` | Code | |
| Icons | `assets/icons/*.svg` | Asset | Lucide (ISC) only, white; see `assets/LICENSES.md` |

Mutator keys (`mul`, `add`, `set`) are limited to: `food, wood, labor, fish, goats, villagers,
climate_rain, climate_storm, climate_fire, degrade`.

## 2. Pipeline: adding content

1. **Edit the JSON** (or the GDScript table for campaign/achievements).
2. **Validate:** `ContentDB.validate()` runs in the test suite and rejects: duplicate/missing
   mutator ids, unknown mutator keys, `score_mult <= 0`, malformed `from` dates, medals that are not
   three ascending thresholds, species bits that are not unique powers of two, codex entries for
   event types the sim doesn't have, bad banner colours, and icons missing from `assets/icons`.
3. **Run the tests** (`godot --headless --path . -s tests/run_tests.gd`). Content tests also check
   seeded-mode determinism, scoring/medals, endless census, Progress merge and the perf bar with
   rare events on (test budget 4 ms/tick at 32×32 and 16 ms at 64×64; measured ≈0.9 ms and
   ≈3.7 ms on the build box — keep it near those numbers, not just under the budget).
4. **Balance check (score / medal changes):** `godot --headless --path . -s tools/balance.gd` plays 10
   daily, weekly and endless islands twice — untouched ("idle") and with a simple scripted steward
   (farms, a house when food allows, restoring bare land) — and prints scores and medals. Rule of
   thumb used for 1.0: **idle never earns bronze**, the scripted steward lands mostly bronze/silver,
   gold needs better play than the script (dams, forest management, more houses). Measured for 1.0:
   daily idle 523–782 vs steward 728–1271 (medals 850/1100/1400); weekly idle 712–1122 vs steward
   1159–2107 (1200/1500/1900); endless idle 1049–1384 vs steward 2038–2526 (1600/2300/3000).
   `tools/smoke.gd` plays every mode for 150 days through the real game scene and checks
   save → reload → same checksum, catch-up after time away, and that a paused game stays frozen.
5. **Look at it:** `tools/screenshots.sh` renders every screen at landscape, portrait and desktop
   and prints script errors / exit leaks; check the Modes, Journal and Codex screens.
6. **Bump `SaveSystem.CONTENT_VERSION`** only if existing saves would *mean* something different
   (e.g. a renamed mutator id). Pure additions don't need it. Format changes bump
   `SaveSystem.VERSION` / `Progress.VERSION` and add a migration + fixture test.
7. Ship in an app update; note the change in the store "What's new".

### Golden rules (determinism & fairness)
- **Never remove, reorder or edit a shipped mutator** — Daily/Weekly islands are regenerated from
  their id, so that would change islands people already played or saved. Append new ones at the
  end with `"from": "YYYYMMDD"` set **after the update is expected to be widely installed**
  (≈ 2 weeks after release); the pool for an island only includes mutators whose `from` ≤ its
  date (tested: a future-dated mutator leaves earlier islands unchanged).
- **The daily id uses the device's local calendar date**, so two players in different time zones
  can be on different islands for a few hours. Fine offline; an online leaderboard would key on
  UTC (change in `ScenarioCatalog.daily_id`). Clock changes are handled by `Progress.observe_date`
  (TDD "Daily/weekly dates"): winding the clock back more than a day marks runs off-clock (playable,
  never submitted); setting it ahead lets a player see a future island early, which only an
  online server date can prevent.
- **XP is improvement-only** (`Progress.record_run`): a seeded island pays score XP only for points
  above your best on that id and medal XP only for new medal tiers; campaign maps pay star XP for
  new stars and score XP on the first win. Keep it that way when adding XP sources, or replays
  become a farm. Fresh endless seeds are new islands and pay in full.
- **Retuning** score weights or medal thresholds changes the meaning of existing bests. Do it only
  at a "season" boundary (see roadmap), and say so in the patch notes. Medals already earned are
  kept (bests store the medal; merge keeps the max).
- **New sim rules** (species, rare events) must stay deterministic: use the hash-based `_chance(i, salt)` with a new salt,
  never `randf()`; keep the 30-day `RARE_COOLDOWN`; give every threat a counterplay the player can
  see in the codex and the Why/History chain (event `causes` filled only from tracked state).
- **Perf bar:** any new per-tick rule must keep `test_rare_event_modes_keep_the_perf_bar` green.

## 3. Post-launch roadmap (suggested)

Cadence: one small content update every ~6 weeks, one "season" every ~3 months.

| When | Update | Content | Engineering |
|---|---|---|---|
| Launch | 1.0 | 6 campaign islands, 4 challenges, Daily/Weekly/Endless, 10 mutators, 3 rare events, 4 species, 6 banners | — |
| +6 wks | 1.1 "Tides" | +4 mutators (dated), +2 banners, 2 challenges built on king tides | Replay of the last Daily (seed share code) |
| +12 wks | 1.2 "Season 1" | New rare event (e.g. coral bleaching ↔ seabirds/fish), new species (mangroves/crabs) with codex | Season = retune window for medals; per-season best list in Journal |
| +18 wks | 1.3 "Archipelago" | 3 campaign islands on bigger maps (48×48), new biome preset | Batch size tuning for 64×64 catch-up; Endless leaderboard prep |
| +24 wks | 2.0 "Online (optional)" | Weekly leaderboards, cloud save | Implement `PlatformServices` for Google Play Games / Game Center; cloud sync uses `Progress.merge` and `SaveSystem.resolve_conflict`; daily id → UTC; record action logs so scores can be replay-verified |

Evergreen, data-only drops between updates: new banners (level/medal/prestige gates) and
mutators dated weeks ahead, so Dailies keep changing without an update.

### Metrics to watch (once telemetry is allowed — not in the offline build)
Daily completion rate and medal distribution per mutator (retune thresholds if gold > 25 % or
bronze < 40 %), Endless median years survived, prestige rate, codex completion.
