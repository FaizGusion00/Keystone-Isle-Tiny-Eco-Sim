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

## 6. Life & settlement (M4)

Tick order (after vegetation and event detection): **crops → wildlife → settlement**.

| System | Rule |
|---|---|
| Village | Placed at generation on the lowland/grassland tile with the most farmable land within 3 tiles (+bonus if water within 2). Starts with 10 villagers, 20 food, 80 fish, 25 goats. |
| Farm (`BUILD_FARM`) | Lowland/grassland, no structure, within 5 tiles (Chebyshev) of the village; forest must be cleared first. Records `FARM_BUILT`. |
| Crops | +1/30 per day × moisture factor `clamp((m-0.10)/0.25)` × soil factor `clamp(depth/0.5, 0.2, 1)`. At 100 %: harvest `8 × soil factor` food, topsoil −0.02. Farm cover = 0.12 + 0.5·crop (fields erode). |
| Crop failure | Moisture < 0.10 for 10 consecutive days kills a growing crop → `CROP_FAILURE`, caused by the active `DROUGHT` (if any; otherwise no cause). |
| Fish | Logistic, r = 0.04, capacity `100 × (1 − clamp((turbidity − 0.015)/0.06, 0, 0.85))`. Muddy water shrinks the habitat. |
| Goats | Logistic, r = 0.03, capacity 0.15 × total pasture vegetation (lowland/grassland/hills); grazing removes `goats × 0.004` cover spread over pasture. |
| Village food | Catch `min(fish·0.02, villagers·0.06)` + hunt `min(goats·0.01, villagers·0.03)` → store (max 150). Need 0.1/villager/day; `food_ema` = EMA of fraction met. |
| Village water | Supply = Σ within 3 tiles of (flow + 0.5·surface water + 0.02·max(moisture−0.2, 0)); need 0.05/villager; `water_ema` = EMA of min(supply/need, 1). |
| Population | Every 30 days: −1 if either EMA < 0.6 (`POPULATION_LOSS`, caused by the active shortages); +1 if both > 0.95 and store ≥ 3 days per villager (`POPULATION_GROWTH`, root cause "plenty of food and water"). |

Life events (all hysteresis, so they fire once per episode):

| Event | Enter / exit | Recorded causes |
|---|---|---|
| `FISH_DECLINE` | fish < 45 / > 65 | active `MUDDY_WATER` (only while the coast is muddy), `POPULATION_GROWTH` within 60 days |
| `HERBIVORE_DECLINE` | goats < 12 / > 18 | active `DROUGHT`, `POPULATION_GROWTH` within 60 days |
| `FOOD_SHORTAGE` | food_ema < 0.7 / > 0.9 | active fish decline, crop failure within 60 days, active goat decline, growth within 60 days (first 3) |
| `WATER_SHORTAGE` | water_ema < 0.7 / > 0.9 | active `DROUGHT` |

Without farms the village is roughly stable (≈75 % fed, no growth); farms are the route to growth. Clearing the forest
reproduces the headline chain within ~75 days: *Trees cleared → Soil erosion → Muddy water → Fish declining → Food
shortage → Villagers left* (see `tests/test_life.gd::test_full_chain_clearing_to_hunger`).

## 7. Tutorial scenario "Feed the Village" (M5, `Scenario`)
Fixed seed 12345. **Win:** ≥ 12 villagers with ≥ 1 farm built, before day 240.
**Fail:** villagers drop to 6 or fewer, or day 240 passes. Evaluated after every tick (also during
catch-up). The fail popup includes the recorded cause chain of the latest population loss /
shortage, e.g. *Villagers left ← Food shortage ← Fish declining ← Muddy water ← Erosion ←
Trees cleared*. Scenario state is part of the save and the checksum.
