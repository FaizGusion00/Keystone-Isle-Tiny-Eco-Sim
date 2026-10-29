# Logic audit — Keystone Isle v1.0

What was checked, what was wrong, how it was fixed and which test now guards it. For fix 10 the guard was
confirmed to fail against the previous `simulation.gd`; the other guards were added with their fixes but were
not re-run against the old code for this document. Run the suite with
`godot --headless --path . -s tests/run_tests.gd` (114 tests at the time of writing).

## Method
- Read every system in `scripts/simulation/` against `docs/SIMULATION_RULES.md` and the in-game text
  (codex, species, inspector rows, tutorial), looking for rules the UI states but the code does not do, or the
  other way round.
- Walked the state machine around time: suspend/resume, save/load, catch-up, scenario end, menus that hold the
  clock.
- Checked determinism and data evolution: what changes for existing saves / seeded islands when content is added.
- Merge / conflict logic for future cloud saves (`Progress.merge`, `SaveSystem.resolve_conflict`).
- Exit path: leaked objects / resources reported by Godot at quit.

## Findings and fixes

| # | Area | Problem | Fix | Guard |
|---|---|---|---|---|
| 1 | Floods (f560064) | Rivers never overtopped their banks: only pooled surface water flooded, so "forests upstream reduce floods" was not true in play. | Static floodplains (bank ≤ 0.035 above a river with catchment ≥ 12), stage = flow/√catchment, overbank threshold by bank height. | `test_river_overbank_floods_floodplain_farms` |
| 2 | Floods (f560064) | Floods had only downsides; no reason to farm river banks. | Overbank floods leave +0.03 topsoil (silt). | same |
| 3 | Runoff (f560064) | Vegetation did not slow runoff, so the forest→flood link was cosmetic. | Dense vegetation holds back 10 % × cover of each day's runoff. | `test_forest_slows_runoff` |
| 4 | Catch-up (6563fdb) | Coming back to a *won* island you kept playing stopped catch-up after one tick (it stopped when status ≠ RUNNING). | Stop only when the status *changes* during catch-up (`start_status`). | `test_catch_up_keeps_running_after_a_won_island` |
| 5 | Catch-up (6563fdb) | Time away was simulated even when the game was left on a pause/menu screen. | Save meta records `held`; resume with a held clock = paused; restore skips catch-up for held saves. | `test_menu_or_pause_screen_freezes_time_away` |
| 6 | Achievements (6563fdb) | Several achievements at once (typically after catch-up) overwrote each other's toast; the cooldown leaked across islands. | Queued award banners, cooldown reset in `set_simulation`. | `test_achievement_banners_queue_one_at_a_time` |
| 7 | Inspector (6563fdb) | Dam / flood inspector rows did not reflect the rules (river dam vs small stream for fish, floodplain risk). | Rows now read the same values the simulation uses; building on a low bank shows a warning toast. | `test_dam_and_flood_rows_are_accurate` |
| 8 | Merge | `Progress.merge` kept the medal of whichever entry had the higher score, so a better medal earned with a lower score (e.g. thresholds retuned between devices) was lost. | Medal = max of both, independent of score; merge is order-independent. | `test_progress_v2_migration_runs_levels_and_merge` |
| 9 | Live content | Adding a mutator to `data/mutators.json` would re-roll every existing daily/weekly island, including runs in saves. | Mutators carry a `from` date (YYYYMMDD); only those with `from` ≤ the island's date are eligible. Validated by ContentDB. | `test_new_mutators_never_change_existing_islands` |
| 10 | Rare events | Locusts marked *every* farm with an empty crop as "stripped by locusts", including fields that were just planted/harvested — the inspector blamed the swarm wrongly. | Only the farms actually stripped point at the event. | `test_locusts_spare_farms_near_forest_and_frogs_stop_them` |
| 11 | Text vs rules | Algal-bloom codex said "don't over-farm one valley" (the rule counts farms island-wide) and did not mention the 3-farm condition; frogs' habitat omitted the 4-tile minimum. | Codex / species text rewritten to match the code. | review |
| 12 | Content data | A mutator, species or rare event could reference an icon that does not exist (blank button). | `ContentDB.validate` checks icons exist in `assets/icons`. | `test_content_files_validate` |
| 13 | Exit | Godot reported leaked Ogg playback instances at quit (intermittent, worse under load). | All quit paths go through `quit_game()`: stop audio, wait one frame plus a real-time settle (0.3 s; 1 s for screenshot runs), then quit. Window close is intercepted. | screenshot pipeline greps logs for leaks |
| 14 | Balance | Seeded-mode scores were dominated by passive terms (starting villagers, island health): an untouched island earned bronze on 9/12 dailies and silver on 2/12, and a scripted steward barely beat it. | Score rewards village *growth* over the start (30/villager), harvests 5, keystone 3; medals recalibrated with `tools/balance.gd` (idle: 0 medals in 30 runs; steward: mostly bronze/silver). | `test_scores_and_medals` (an idle island earns no medal) |

## Known gaps (not fixed, by decision or out of scope)
- **XP farming**: XP is granted for every completed run, so replaying a seeded island repeatedly earns XP.
  Harmless offline (no leaderboard). Before any online feature: grant score XP only for a new personal best per id.
- **Daily uses the device's local date**: players in different time zones see the same island at different
  moments, and changing the clock unlocks future dailies. Acceptable offline; an online version should take the
  date from the server (see LIVEOPS.md).
- **No replay verification**: scores are not backed by an action log, so they cannot be verified. Required before
  any shared leaderboard (TDD "Online-ready").
- **Exit-leak fix is timing-based**: the settle delay removed the leak in 8/8 runs at 1 s (3/8 leaked at 0.25 s)
  under parallel load; it is a heuristic, not a guarantee. Leaks at exit are harmless to players (the OS frees
  them) but noisy in logs.
- **`rare_survived` score term counts rare events that hit**, not ones that were survived in any stronger sense;
  the run ending afterwards still keeps the points.
- Grazing in a tick uses the goat count before wolf predation that same tick (≤ 0.4 % difference).
