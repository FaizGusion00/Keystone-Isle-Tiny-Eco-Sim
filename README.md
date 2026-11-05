# Keystone Isle: Tiny Eco Sim

An offline, single-player, 2D isometric **miniature-island ecosystem sandbox**. Small actions
cause chain reactions: *cut trees → erosion → muddy river → fish decline → food shortage.*
Targets Android, iOS, Windows and macOS with touch **and** mouse/keyboard. No backend, network,
analytics or ads.

- Design: [`docs/GDD.md`](docs/GDD.md) · Architecture: [`docs/TDD.md`](docs/TDD.md) ·
  Rules: [`docs/SIMULATION_RULES.md`](docs/SIMULATION_RULES.md)

## Engine
**Godot 4.7.2-stable** (standard build, GDScript; not .NET). Download:
<https://github.com/godotengine/godot/releases/tag/4.7.2-stable>.
Renderer: **Compatibility** (see TDD for why).

## Run
```bash
godot --path . --import        # first time only (builds .godot/ cache)
godot --path .                 # play
godot --path . --editor        # open editor
```
**Version 1.0.0.** The very first launch asks for the language once, then opens the guided
first island right on the map. Later launches open a title screen that only lists what is open
so far: Continue / Start · Campaign (6 islands) · Daily · Weekly · Endless and New world (after
island 1) · Challenges (after island 2) · Load (when a slot is saved) · Journal · Settings · Help.

First island (guided, "do it yourself"): tap the village → see the food → pick Farm → build on a
green tile → press Play → watch the crop → first harvest → tap People for the growth checklist →
second farm → the village grows → goals → History. Each step waits for the action; time only
runs on "watch" steps; it can be skipped, and it resumes on the same step after a restart.
Tools and top-bar numbers open step by step (island 1: Inspect + Farm; island 2 adds Clear,
Plant, House, Remove; later islands everything).

Controls (touch and mouse/keyboard):
- Tap/click a tile to inspect it (slide-in inspector with stats and "Why?" cause chains);
  drag to pan; pinch / mouse wheel / trackpad / `+` `-` / on-screen +− to zoom; arrow keys pan.
- Bottom toolbar: Inspect · Clear · Plant · Farm · House · Dam · Restore · Remove (keys `1`–`8`),
  each with its cost under it (hand = labor, tree = wood). With a build tool picked, every tile
  where it works is tinted (green OK, amber can't afford, blue floodplain) and a hint bar says
  where it works. Mouse: a ghost of the build + a cost/reason tag follow the cursor. Touch: farms,
  houses, dams and removals preview on the first tap and build on the second. After a big build
  the tool drops back to Inspect (hold Shift to keep it). Side buttons: Layers (`L`), History (`H`).
- Top bar: day/season chip, Pause / Play (1 day per second) / 2× / 4× (`Space` toggles pause),
  menu (`Esc` = pause / back). Tap any number for a plain-words card - People shows exactly why
  the village is or isn't growing (fed > 95 %, water > 95 %, 3 food stored per person, free homes,
  next check in N days).
- The goals card lists the goals, the extra stars and how you lose. Toasts put bad news first,
  at most two at a time. Zoomed out, a "Village · N" pin marks the village.
- Map changes animate (build/plant grow in, cleared trees fall, crops and cottages pop); all
  motion respects Settings → Reduce motion.

Settings (saved to `user://settings.cfg`): master / music / effects / sea & rain volume,
interface size (S/M/L/XL), colour-blind-safe layers, reduce motion, haptics, tutorial tips,
language (English · Bahasa Melayu, switches live). Layout adapts to phone portrait, phone
landscape and desktop.

Translation: English text is the key, `i18n/ms.json` holds Bahasa Melayu. Static labels translate
themselves (Godot auto-translate); text built from a template uses `I18n.t("Day %d") % day` /
`I18n.f(...)`. `tests/test_i18n.gd` fails on any untranslated template, table entry or on-screen
text (`godot --headless --path . -s tools/i18n_misses.gd -- --lang=ms` lists what to translate).

The game autosaves (every 30 days and whenever the app is backgrounded/closed) and Continue
resumes where you left off, catching up the time you were away (capped at 360 days) with a
"While you were away" summary.

## Tests
```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_tests.gd             # all tests, exit code 1 on failure
godot --headless --path . -s tests/run_tests.gd -- --filter=iso   # subset
godot --headless --path . --quit-after 300                  # smoke-run main scene
```
Screenshots (needs a display or `xvfb-run`):
```bash
tools/screenshots.sh /tmp/shots     # full landscape 1280x720 + portrait 720x1280 set (26 PNGs)
xvfb-run -a godot --path . -- --select=14,12 --screenshot=/tmp/shot.png
xvfb-run -a godot --path . -- --scenario=floodplain --farms-at=11,12 --until=FLOOD --no-results \
    --focus=event --select=event --screenshot=/tmp/flood.png
```
Debug args (after `--`): `--seed --zoom --clear-rect=x0,y0,x1,y1 --farms=N --farms-at=x,y;x,y
--dams=N --ticks=N --until=EVENT_TYPE --away=SECONDS --speed=0|1|2 --overlay=0..4 --history[=TYPE]
--focus=village|dam|event|x,y --select=village|dam|event|x,y --scenario=ID --tutorial --restore
--no-results --screen=menu|campaign|challenges|new_world|settings|pause|load|save|achievements|results_won|results_failed
--coach --reduce-motion --colorblind --screenshot=PATH --frames=N --lang=en|ms --guide=STEP
--tool=farm|house|… --hover=x,y|best --chip=villagers|food|… --act=clear|farm|house|plant --perf=FRAMES`.
Don't combine `--seed` with `--scenario`.
Runs with debug args don't read/write the save unless `--restore` is given.

## Folders & naming
```
scenes/world  scenes/ui           .tscn scenes (snake_case files)
scripts/core                      composition root, clock, save/IO, settings, progress, audio, debug hooks
scripts/world                     tile data, generation, iso math, map rendering, camera
scripts/simulation                tick systems, events, scenarios (no nodes)
scripts/ui                        theme/widgets (ui_kit), HUD, menu screens (all built in code)
assets/                           fonts (OFL), icons (ISC), art atlas + audio (CC0, generated by tools/) — see assets/LICENSES.md
tools/                            asset generators (art, audio), screenshots.sh
tests/                            headless tests: test_*.gd, methods test_*
docs/                             GDD / TDD / rules
```
- Files `snake_case.gd`; classes `PascalCase` via `class_name`; constants `UPPER_SNAKE`;
  private members `_leading_underscore`; signals past-tense or `*_requested`.
- Tabs for indentation, static typing everywhere practical.

## Export
`export_presets.cfg` has Android, iOS, Windows Desktop and macOS presets with **no secrets**.
Install export templates for 4.7.2 (Editor → Manage Export Templates), then e.g.
`godot --headless --export-release "Windows Desktop" build/windows/KeystoneIsle.exe`.
- Android release signing: set `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
  `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` env vars.
- iOS: set your Team ID in the iOS preset locally (don't commit it); needs Xcode on macOS.
- macOS: preset uses ad-hoc signing; for distribution set an identity + notarization locally.
