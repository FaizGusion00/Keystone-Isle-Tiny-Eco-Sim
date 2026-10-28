# Simulation Rules

1 tick = 1 in-game day. Systems run in this fixed order every tick (`Simulation.step()`).
All constants live at the top of `scripts/simulation/simulation.gd`.

## 1. Rainfall (`_rainfall`)
- Season: `s = sin(tick · 2π / 120)` (120-day year).
- Rain chance `0.38 + 0.22·s`; amount `U(0.010, 0.050) · (1 + 0.5·max(s,0))` (seeded RNG, always 2 draws/tick).
- Each land tile receives `amount · (1 + 0.6·elevation)` surface water (orographic boost).
- `dry_streak` counts consecutive dry days.

## 2. Water flow & erosion (`_water_flow_and_erosion`, two-buffer)
- Static drainage: each tile's `down` = lowest 4-neighbour by terrain elevation (computed once);
  `upstream_area` = number of tiles draining through it (rivers).
- Land tile with a downstream neighbour moves `85%` of its water there. A pit (no lower
  neighbour) spills to the lowest neighbour by *water head* `elevation + water`, moving at most
  half the head difference — ponds fill, then overflow.
- **Erosion:** `detach = 0.25 · move · slope · (1 − vegetation)²`, `slope = clamp(Δelev·12, 0, 1) + 0.1`,
  limited by `soil_depth`. Detached soil joins the tile's suspended sediment.
- Sediment moves in proportion to water moved; 25% of what stays deposits back into soil.
- Sea tiles: incoming water drains away; sediment keeps 80%, spreads 10% to sea neighbours
  (decays ~10%/tick) — a muddy plume. `coastal_turbidity` = mean sediment over shallow water.
- Reads only current `surface_water`/`sediment`, writes `_water_next`/`_sed_next`, then swaps.

## 3. Soil water (`_soil_water`)
- Infiltration `min(water, 0.25·(1−moisture)·(0.4 + 0.6·soil_depth))` (eroded soil holds less).
- Surface water evaporates 10%/tick. Soil moisture loses `2%·(1 − 0.5·veg)` plus `0.003·veg` plant use.

## 4. Vegetation (`_vegetation`)
- Logistic growth to a land-type cap (forest 1.0, grassland 0.7, lowland 0.6, hills 0.45, beach 0.12):
  `0.032 · moistureFactor · soilFactor · (v + 0.008) · (1 − v/cap)`;
  `moistureFactor = clamp((m − 0.08)/0.3)`, `soilFactor = clamp(soil/0.6, 0.1, 1)`.
- Drought (`moisture < 0.08`): −0.004/tick dieback.

## Player actions (between ticks)
- **Clear trees** (forest only): tile becomes lowland/grassland (by elevation), vegetation 0.06.
- **Plant trees** (lowland, grassland, hills): tile becomes forest, vegetation ≥ 0.25.

## 5. Events & causes (`_detect_events`, M3)
Events live in `EventLog` (ring buffer, 512 entries, parallel Packed arrays — no allocation
while recording). Each event stores up to 3 **cause ids**: the events the rule actually read
when it fired. Explanations (`EventLog.explain`) only walk these links; an event with no
recorded cause says **"No recorded cause."** and roots say *your action* / *weather*.

| Event | Fires when | Recorded causes |
|---|---|---|
| Trees cleared / planted | player action | — (root: your action) |
| Heavy rain | daily rain ≥ 0.055 | — (root: weather) |
| Drought / drought ended | 12 dry days in a row / first rain after | — (root: weather) |
| Soil erosion (tile) | decaying soil-loss sum (`×0.97`/day) ≥ 0.08 | the tile's `land_cause` if it is a *Trees cleared* event; heavy rain within 3 days |
| Coastal water turned muddy | coastal turbidity ≥ 0.045 (and not already muddy) | up to 3 latest erosion events (≤ 40 days old) that themselves have causes; else the latest erosion events |
| Coastal water cleared | turbidity < 0.030 while muddy (hysteresis) | the muddy event |

Per-tile `last_event` feeds the inspector's **Why?** button; `land_cause` remembers the
action that last changed the tile's land.

## Overlays
Normal, Moisture, Plants (vegetation), Soil (depth), Water & mud (flow + sediment).
