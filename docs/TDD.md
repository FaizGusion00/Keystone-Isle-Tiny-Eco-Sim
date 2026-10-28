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

## Save / load (M5) — `SaveSystem`
- **Format:** one JSON file `user://keystone_save.json`, `version: 1`. Tile arrays are base64 of
  the raw Packed bytes; float scalars (fish, goats, food store, EMA…) are base64 float64 bytes,
  because Godot's JSON drops the last bit of a double and the post-load checksum would differ;
  RNG seed/state are decimal strings (64-bit safe). Also stores the scenario, event log and
  `meta` (`saved_at` unix time, clock speed).
- **Validation:** `from_dict` rejects unknown versions, missing fields, malformed base64 and arrays
  whose size doesn't match `width × height`, returning `null` instead of a half-built world.
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
- **Debug/screenshot runs** (any user args) don't touch the save unless `--restore` is passed;
  `--away=SECONDS` simulates suspend → time passing → resume.
- **Tests (`tests/test_save.gd`)**: save round trip, backup fallback on corruption, rejecting bad
  saves, `compute_ticks` (cap, paused), catch-up == normal ticks, killed-app restore + catch-up
  == uninterrupted play, away summary content, tutorial win/fail, and a scene-level test that
  instantiates `main.tscn`, sends PAUSED/RESUMED notifications, drains the batched catch-up via
  `_process`, then relaunches a second instance from the autosave.
- **Test runner** fails any test that logs an engine/script error (an `OS.add_logger` counter),
  so a crash mid-test can't pass silently.
