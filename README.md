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
Controls: tap/click a tile to inspect · drag to pan · pinch / mouse wheel / `+`/`-` to zoom ·
arrow keys to pan.

## Tests
```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_tests.gd             # all tests, exit code 1 on failure
godot --headless --path . -s tests/run_tests.gd -- --filter=iso   # subset
godot --headless --path . --quit-after 300                  # smoke-run main scene
```
Screenshot (needs a display or `xvfb-run`):
```bash
xvfb-run -a godot --path . -- --select=14,12 --screenshot=/tmp/shot.png
```

## Folders & naming
```
scenes/world  scenes/ui           .tscn scenes (snake_case files)
scripts/core                      composition root, clock, save/IO, debug hooks
scripts/world                     tile data, generation, iso math, map rendering, camera
scripts/simulation                tick systems, events, scenarios (no nodes)
scripts/ui                        HUD (built in code)
assets/                           art/audio (placeholders are drawn in code for now)
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
