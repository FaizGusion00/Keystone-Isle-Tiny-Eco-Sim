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
- **Fixed system order** each tick: rainfall → water flow & erosion → soil water → vegetation →
  crops → herbivores → fish → settlement → event detection → scenario.
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

## Save / load (M5)
Versioned JSON (`version`), arrays as base64 raw bytes, RNG seed/state as strings (64-bit safe).
Atomic write: write `save.json.tmp` → re-read & parse to verify → move existing `save.json` to
`save.json.bak` → rename tmp → `save.json`. Load falls back to `.bak` if main is missing/corrupt.

## App-switch resilience & catch-up (M5)
See "Lifecycle" section (added in M5).
