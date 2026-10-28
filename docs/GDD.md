# Keystone Isle: Tiny Eco Sim — Game Design (concise)

## Pitch
A pocket-sized, offline, single-player isometric island you can hold in one hand.
Every small action ripples through a living ecosystem: **cut trees → soil erodes →
the river turns muddy → fish decline → the village runs short of food.** The game's
heart is *seeing and understanding* those chain reactions.

## Pillars
1. **Small actions, visible consequences.** Few verbs, deep systemic response.
2. **Readable causality.** Every consequence can be traced back through *recorded* causes
   ("Why did fish decline?").
3. **Calm and tiny.** One 32×32 island, short sessions, no fail-spam, no network, no ads.
4. **Fair and deterministic.** Same seed + same actions = same island history.

## Platforms & input
Android, iOS, Windows, macOS. Touch first (tap, one-finger pan, pinch zoom) with full
mouse/keyboard parity (click, drag, wheel, arrows, +/-). Large touch targets (≥ 60 px).

## Core loop
Inspect tiles → pick a tool (clear trees, plant trees, build farm) → watch days pass
(pause / 1× / 4×) → read event history & overlays → adjust.

## World
Seeded island, radial falloff. Land types: deep water, shallow water, beach, lowland,
grassland, forest, hills. Per-tile: elevation, soil moisture, vegetation, soil depth,
surface water, sediment.

## Systems (MVP)
- **Water:** rainfall (seasonal, seeded) → downhill surface flow → infiltration → evaporation.
- **Soil:** erosion where water flows over bare, sloped ground; sediment is carried to the sea.
- **Vegetation:** grows with moisture & soil; protects soil; grazed by herbivores.
- **Fish:** coastal stock, hurt by muddy (turbid) water.
- **Herbivores:** one population grazing grass.
- **Farm:** one crop type on lowland/grassland; needs moisture & soil; exposes soil.
- **Settlement:** one village with food & water demand; food from fish, hunting, farms.

## Information
Tile inspector, event history with causal explanations, overlays (moisture, vegetation,
soil depth, water/turbidity), "While you were away" summary.

## Scenario (tutorial)
"Feed the Village": keep the village alive and fed for a season. Win: reach day 200 with
≥ 8 villagers and at least one farm. Fail: village drops below 5 villagers.

## Out of scope (MVP)
Multiplayer, accounts, cloud saves, analytics, ads, IAP, procedural music.
