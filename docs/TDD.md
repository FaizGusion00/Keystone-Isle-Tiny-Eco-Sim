# Keystone Isle — Technical Design

## Engine & renderer
- **Godot 4.7.2-stable** (pinned; `config/features` = `4.7`), GDScript only, no plugins.
- **Renderer: Compatibility (OpenGL ES 3 / ANGLE-Metal on Apple).** The game is flat 2D
  polygons; it needs none of Forward+/Mobile's features. Compatibility has the widest device
  reach (older/low-end Android GPUs where Vulkan is missing or buggy), the lowest startup and
  memory cost, runs on iOS/macOS via ANGLE→Metal, and on Windows via OpenGL/ANGLE. It also runs
  under `xvfb` on CI for screenshots. Forward+ is desktop-only and Mobile (Vulkan/Metal) would
  exclude a slice of Android devices for no visual gain.
- Stretch: `canvas_items` + `expand`, base 1280×720, sensor-landscape on phones.
  `low_processor_mode` on: the engine only redraws when a canvas item changes.

## Layering
```
scripts/world       pure data + math     WorldState, LandType, Iso, IslandGenerator
                    visuals              WorldView, WorldChunk, TileHighlight, CameraController
scripts/simulation  pure logic           Simulation (+ systems), EventLog, Scenario
scripts/core        composition / IO     main.gd, SimClock, SaveSystem, CatchUp, DebugTools
scripts/ui          presentation         Hud, UiKit
```
Simulation code never touches nodes; visuals never mutate simulation data. Data flows
`Simulation → WorldState → WorldView.refresh()`; input flows `Camera/HUD → main → Simulation.apply_action()`.

## Tile data (WorldState)
Struct-of-arrays, one `Packed*Array` per field, index `i = y * width + x`:
`elevation`, `land_type` (byte), `soil_moisture`, `vegetation_cover` (M1) and later
`surface_water`, `sediment`, `soil_depth`, `flow`, `structure` (byte), `crop_growth`,
`erosion_accum`, `last_event` (int32). Packed arrays are contiguous, cheap to hash, and
serialize as raw bytes (exact float round-trip).

## Isometric math (Iso)
2:1 diamonds, 64×32. `center(x,y) = ((x−y)·32, (x+y)·16)`. Picking inverts the transform
(`tx = (fy+fx)/2, ty = (fy−fx)/2` with `fx = px/32, fy = py/16`) and rounds — this is exact
diamond picking (no bounding-box error). Screen→world uses the viewport canvas transform.

## Rendering
**Ground surface.** Land is one continuous surface, not stacked blocks: each tile corner gets a
height (`BASE_H + RELIEF × smoothed elevation`, averaged over the up-to-four land tiles sharing
it; any corner touching water sits at `BASE_H`), so neighbouring tops share vertices and meet
without seams or stair steps. Each corner also carries a slope-light factor, so relief reads
through smooth Gouraud shading. Vertical banks are drawn only at the shore. Water tiles in a
notch between two land neighbours draw a low half-tile bank (`_corner_fill`), turning saw-tooth
diagonal coasts into straight shorelines. Streams are quadratic-Bézier ribbons from each inflow
edge through the (slightly meandering) tile centre to the outflow edge, on the sloped surface,
with a soft bank and glint; they fall over the shore bank as a small waterfall.

The map is split into 8×8-tile `WorldChunk` nodes. `WorldView.refresh()` recomputes each tile's
quantized color into a `PackedColorArray`, compares its RGBA32 key to the cached key, and calls
`queue_redraw()` only on chunks containing changed tiles. Godot caches canvas commands, so a
static island costs ~0 per frame. Refresh runs after sim ticks / overlay changes, never per frame.

## Simulation: tick-based & deterministic
- **Fixed tick** (1 tick = 1 day). `SimClock` accumulates real time × ticks-per-second
  (paused 0, normal 2, fast 8) and runs whole ticks; the tick function never sees `delta`.
  Rendering is decoupled: at most `MAX_TICKS_PER_FRAME` ticks per frame, remaining debt carries over.
- **Seeded RNG:** one `RandomNumberGenerator` owned by `Simulation`, seeded from the island
  seed; its `state` is saved. No `randf()` globals, no `Time` in sim code.
- **Fixed system order** each tick (`Simulation.step`): rainfall → water flow & erosion →
  soil water → vegetation → event detection (erosion / muddy water / drought / fish) → crops →
  wildlife (fish, goats) → settlement (demand, shortages, life events; population every 30 ticks)
  → scenario evaluation.
- **Two-buffer updates:** water + sediment flow read the *current* buffers and write the *next*
  buffers, then swap references. Result is independent of iteration order.
- **No frame-time dependence:** identical results at 1×, 4×, during catch-up, or headless.
- Player actions are applied between ticks and recorded as events.

## Performance rules
- Tick loops are allocation-free: they iterate local aliases of the Packed arrays (Godot 4
  packed arrays alias on assignment; local access is ~5× faster than `obj.arr[i]`), use only
  scalar locals, and reuse the pre-allocated second buffers.
- Events are allocated only when something notable happens (rare).
- `tests/test_perf.gd` benchmarks ms/tick for 32×32 and 64×64 headless.

## Events & explanations (M3)
`EventLog` stores `{id, tick, type, x, y, value, causes[]}` (ring buffer). Causes are filled
**only** from state the sim actually tracked at the moment the event fired (e.g. a tile's
`last_event` id, the active muddy-water event). Explanations walk those recorded links;
if an event has no recorded cause, the UI says so instead of guessing.

## Save / load (M5, format v4) — `SaveSystem`
- **Files:** `user://saves/autosave.json` plus three manual slots (`slot_N.json`). The v1 single
  file `user://keystone_save.json` is moved into the autosave slot on first launch
  (`migrate_v1_file`).
- **Format (`version: 4`; v4 added `rare_weathered`):** tile arrays are base64 of the raw Packed bytes; float scalars (fish,
  goats, food store, EMA…) are base64 float64 bytes, because Godot's JSON drops the last bit of a
  double and the post-load checksum would differ; RNG seed/state are decimal strings (64-bit
  safe). Also stores the scenario, event log, `meta` (`saved_at`, clock speed, held flag, slot
  summary) and the **identity block** `save{id, created_at, revision, app_version,
  content_version, platform}` (see "Online-ready" below).
- **Migration:** every format change bumps `VERSION`; `from_dict` accepts 1…VERSION and fills new
  fields with neutral defaults (v1 speeds are remapped, v1/v2 saves get a fresh identity with
  revision 0, rare events off; v1–v3 derive `rare_weathered` from `rare_hits` minus a hit still inside its
  30-day cooldown). A real v2 file is kept as a test fixture
  (`tests/fixtures/save_v2.json`) and must keep loading.
- **Validation:** `from_dict` rejects unknown/newer versions, missing fields, malformed base64 and
  arrays whose size doesn't match `width × height`, returning `null` instead of a half-built world.
- **Atomic write:** write `…json.tmp` → re-read and parse it to verify → move the existing
  `…json` to `…json.bak` → rename tmp → `…json`. A crash at any step leaves a valid main or
  backup file. `load_game` falls back to `.bak` when the main file is missing/corrupt (the HUD
  then says "restored the backup").
- **Round trip is exact:** `state_checksum()` before save == after load (tested), and continuing
  to tick a loaded game gives the same result as never saving.

## Lifecycle: app-switch resilience & catch-up (M5)
Mobile OSes may suspend or kill a backgrounded app without warning, so the game assumes every
background transition could be the last thing it sees.

| Trigger | Action |
|---|---|
| `NOTIFICATION_APPLICATION_PAUSED` (Android/iOS background), `…FOCUS_OUT` (desktop alt-tab), `NOTIFICATION_WM_CLOSE_REQUEST` | `Main.suspend()`: block the clock (no ticks while away), finish any running catch-up, **atomic autosave immediately**, record `_suspended_at` (unix time) |
| `NOTIFICATION_APPLICATION_RESUMED`, `…FOCUS_IN` | `Main.resume()`: unblock, schedule catch-up for the elapsed time |
| Next launch (also after the OS killed the app) | `restore_from_disk()` loads the autosave (or `.bak`), restores the speed, schedules catch-up from `meta.saved_at` |
| Every 30 ticks of play, after a catch-up, new island / tutorial | autosave |

- **Catch-up (`CatchUp`)**: `ticks = floor(elapsed_seconds × ticks_per_second(speed))`, capped at
  `MAX_TICKS = 360` (one in-game year), and **0 when the game was paused** (paused islands
  don't age). Ticks are the normal `Simulation.step()` — no "fast-forward" approximation — so
  catch-up is bit-identical to playing (tested for several N and batch sizes). They run in
  batches of `BATCH = 40` per frame (≈30 ms at the shipped 32×32 map; ≈120 ms at 64×64, so lower it for bigger maps) so the UI stays responsive; the clock stays
  blocked until done. Catch-up stops early if the scenario is won/lost.
- **"While you were away"** popup (only if ≥ 10 days passed) is built *only* from the event log
  since the catch-up started: days passed, villagers/food/fish before → after, up to 8 notable
  events newest-first, and routine ones (erosion, heavy rain) as counts. A win/fail popup raised
  during catch-up queues behind it.
- **Desktop:** FOCUS_OUT counts as "away", so alt-tabbing saves and freezes the island; the
  catch-up on return reproduces the ticks you would have had (capped).
- **Clock trust:** only wall-clock *differences* are used and negative elapsed time gives 0 ticks,
  so moving the device clock backwards can't rewind; forwards is bounded by the cap.
- **Daily/weekly dates:** ids come from the local calendar date. `Progress.date_seen` keeps the
  newest date the profile has seen (merged by max; migrated from v2 bests). Forward changes
  (midnight, time zones, DST, a clock set ahead) simply advance it. A date more than one day
  before `date_seen` (clock wound back, or a reset clock < 2024) is *off-clock*: the island for
  the clock's date is still offered and playable, the Modes screen and results say so, and the
  score is kept locally but not passed to `PlatformServices.submit_score`. A run already started
  keeps its island id across midnight and save/load. An online build should take the date from
  the server instead (`ScenarioCatalog.daily_id(date)` already accepts one).
- **Debug/screenshot runs** (any user args) don't touch the save unless `--restore` is passed;
  `--away=SECONDS` simulates suspend → time passing → resume.
- **Tests (`tests/test_save.gd`)**: save round trip, backup fallback on corruption, rejecting bad
  saves, `compute_ticks` (cap, paused), catch-up == normal ticks, killed-app restore + catch-up
  == uninterrupted play, away summary content, tutorial win/fail, and a scene-level test that
  instantiates `main.tscn`, sends PAUSED/RESUMED notifications, drains the batched catch-up via
  `_process`, then relaunches a second instance from the autosave.
- **Test runner** fails any test that logs an engine/script error (an `OS.add_logger` counter),
  so a crash mid-test can't pass silently.

## UI layer (M8) — `UiKit`, `Hud`, `Screens`
- **`UiKit`** builds one `Theme` in code (palette, StyleBoxFlat panels/buttons, Inter/Fraunces
  fonts, icon tinting) plus widget helpers (chips, icon buttons, toggles, sliders, cards). UI
  scale = `content_scale_factor` × settings `ui_scale`; `UiKit.reduce_motion` gates tweens.
- **`Hud`** owns the in-game overlay. `relayout()` picks *portrait* (w < h), *compact landscape*
  (short height) or *desktop* and positions top chips, toolbar, inspector (side panel or bottom
  sheet), history drawer, goals card and the toast stack so they never overlap. Event icons come
  from `Hud.event_icon(type)`; the inspector's tile rows are pure data (`tile_rows`) and tested.
- **`Screens`** is a modal stack (menu, campaign, challenges, modes (Daily/Weekly/Endless),
  new_world, settings, pause, load/save, journal (profile · codex · achievements), help, results). Any open screen holds the `SimClock`; Esc/Back pops.
- Coach marks are a scripted list of anchors over HUD nodes, shown once (settings flag).

## Audio, settings, progress (M9)
- **`AudioDirector`**: buses Master/Music/SFX/Ambience; looping music + sea ambience, rain
  ambience cross-faded by current rainfall; one-shot cues for UI and actions, rate-limited.
  All sounds are generated by `tools/audio/make_audio.py` (CC0).
- **`GameSettings`** (`user://settings.cfg`) validates types on load and clamps UI scale.
  Haptics use `Input.vibrate_handheld` only when enabled and on mobile.
- **`Progress`** (`user://progress.json`, v2, atomic tmp+rename) stores campaign stars,
  personal bests + medals per seeded island, achievements, XP/level/prestige, codex discoveries
  and the chosen banner. v1 files are migrated on load.
- **Debug & screenshots**: `DebugTools` parses user args (see README); `tools/screenshots.sh`
  renders the landscape, portrait and 1920×1080 desktop screenshot sets under xvfb and greps each
  log for script errors and exit-time leaks.
- **Clean exit:** every quit path (`quit_game`, desktop window close via
  `set_auto_accept_quit(false)`) stops all audio players and drops their streams, then
  `Main.drain_audio()` waits for *evidence* that the mixer released the playbacks instead of a
  fixed delay: it polls `AudioServer.get_time_since_last_mix()` each frame (a drop proves a mix
  pass ran), waits for two passes after the stop (pass 1 fades the stopped playbacks out, pass 2
  marks them for deletion) and then two more frames for the main thread to free them. A 3 s guard
  only applies if no audio thread is mixing at all (then nothing is pending). Typical drain:
  150–280 ms under 8 parallel loaded runs, 0/8 leaks (was 3/8 with a 0.25 s timer). `--log-exit`
  prints the drain stats; `test_exit_waits_for_the_mixer_not_a_timer` covers it.

## Seeded modes & content data (v3)
- **Content lives in `data/*.json`** (`mutators`, `species`, `codex`, `cosmetics`, `modes`), read
  through `ContentDB` (cached) and checked by `ContentDB.validate()` in the test suite. See
  `docs/LIVEOPS.md` for the pipeline.
- **Generated scenarios** have ids instead of hand-written definitions: `daily_YYYYMMDD` (local
  calendar date), `weekly_<Monday>` and `endless_<seed>`. `ScenarioCatalog.generated_def(id)`
  derives the world seed (FNV-1a `stable_hash` of the id, identical on every platform) and the
  mutators from the id alone, so a run can be rebuilt anywhere from its id and a save only
  needs to store the id.
- **Mutators** apply multipliers/offsets to start resources and climate knobs; their score
  multipliers stack into the run's `score_mult`. Score = weighted sum of days, keystone, peak
  villagers, harvests, species seen, rare events survived and villagers lost (weights in
  `modes.json`); medals are three ascending thresholds per mode.
- **Endless** escalates weather each year and runs a census at the end of every 120-day year
  (`census_start + census_step × year`, capped at `census_max`).
- **Rare events & species** are deterministic (hash-based chance, 30-day cooldown) and opt-in for
  sandbox worlds. Each rare event has a documented counterplay (codex text = sim rule).

## Online-ready (offline today)
The shipping build has **no network code and no accounts**. Everything a later online phase
needs sits behind one seam so it can be added without touching gameplay:

- **`PlatformServices`** (`scripts/platform/`): sign-in state, `player_id`, `submit_score(board,
  score)` (board = scenario id, e.g. `daily_20261030`), `unlock_achievement`, `cloud_push/
  cloud_pull(kind, data)` with results via signals. Contract: non-blocking, safe while offline,
  never on the sim thread. `Main.services` is an `OfflinePlatformServices` that only records
  calls (tests check it stays inert and that a finished
  daily run's score reaches it). A future `GpgsPlatformServices` /
  `GameCenterPlatformServices` would be chosen at startup per OS.
- **Mergeable progress:** `Progress.merge(other)` uses only unions and maxima (stars, bests,
  medals, achievements, codex, (prestige, xp) lexicographically), so merging is order-independent
  and no device loses progress; the banner follows the newer `updated_at`. Each profile has a
  random `profile_id` (never the platform id).
- **Save conflicts:** every save carries `save{id, revision, created_at, …}`. Same lineage →
  higher revision wins (ties: later `saved_at`); different lineages → later wins and the UI
  should offer to keep the other as a slot (`SaveSystem.resolve_conflict`, tested).
- **Daily/weekly fairness:** ids derive seeds deterministically, so a leaderboard only needs the
  id; the sim is deterministic per seed, so a server could later re-verify a submitted run by
  replaying its action log (not recorded yet — a known gap).
