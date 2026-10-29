# Simulation Rules

1 tick = 1 in-game day. Systems run in this fixed order every tick (`Simulation.step()`).
All constants live at the top of `scripts/simulation/simulation.gd`.

## 0. Terrain & drainage (`IslandGenerator._shape_drainage`)
- Raw noise elevation has many small pits, so runoff used to split into dozens of short parallel
  lines. After land types are assigned, hollows are filled (priority flood, a tiny randomised fall
  per tile so flats still drain in natural, non-straight paths), then valleys are incised 8 times by
  `0.012·(√catchment − 1)`, widened into soft valleys (2 passes, ×0.6 per tile) and capped at 0.12
  below the original ground, re-filling after each pass. Result: ~5–7 stream heads merging into one
  or two rivers per 32×32 island. Land types (coast, biomes) are unchanged; saves store elevation, so
  existing saves keep their terrain.
- The map draws a stream at catchment ≥ 12, a river (wider, darker channel) at ≥ 40; rain shows faint
  rills (catchment ≥ 8) only while it rains and only where they feed a stream within 5 tiles.

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
| Population | Every `POP_PERIOD` = 20 days: −1 if either EMA < 0.6 (`POPULATION_LOSS`, caused by the active shortages; skipped in Relaxed mode); if both EMAs > 0.95 and the store holds ≥ 3 food per villager, grows by `max(1, villagers / 8)` up to the housing cap (`POPULATION_GROWTH`, root cause "plenty of food and water"). At the cap it records `HOUSING_FULL` once instead. |

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

## 8. Labour, wood and building (M6)
- Labour regenerates `0.1` per villager per day up to `10 + villagers`; wood comes from clearing forest (`+4`, max 99).
- Costs `[labour, wood]`: clear 1/0, plant 1/0, farm 3/2, house 3/6, dam 6/10, restore 2/0, remove 1/0
  (Relaxed halves them; sandbox free-build zeroes them).
- Housing cap = `12 + 4 × houses`. Houses go within 2 tiles of the village or next to another house.

## 9. Dams
- Only on a stream (`upstream_area ≥ 12`, `DAM_MIN_AREA`; exactly the channels the map draws). A dam stores up to 2.0 water, releases 0.03/day once it holds some,
  loses 0.004/day to evaporation, and holds neighbouring soil moisture at ≥ 0.30 (irrigation).
- A dam on a river (`upstream_area ≥ 20`) blocks fish runs: fish capacity −12 % per river dam. Smaller streams
  let fish pass. The inspector says which ("River dam: blocks fish" / "Small stream: fish pass").

## 10. Floods (`_floods`)
- **River stage** of river tile r = `flow / √upstream_area`. Streams with catchment ≥ 12 have a
  **floodplain**: land tiles next to the river whose banks are at most 0.035 above it (`floodplain[i]` = that river
  tile, else −1).
- A floodplain tile floods when the stage reaches `0.22 + 0.15 × (bank rise / 0.035)` — low banks flood first.
  The inspector shows this as "Floodplain" / "High bank" with the river level in %; building a farm or house on
  the lowest banks (`flood_risk == 2`) shows a warning toast.
- Any built tile (not dams) also floods when ≥ 0.6 surface water pools on it.
- A flood (cooldown 15 days per tile) records `FLOOD` caused by heavy rain in the last few days and the most
  recent clearing/burn up to 6 steps upstream. An overbank flood spreads ≥ 0.35 water and leaves +0.03 topsoil (silt).
- Damage: an overbank flood halves a growing crop; a deep flood wipes it (`HARVEST_LOST` if > 25 % grown);
  houses / the village lose 15 % of the food store.
- Counterplay: dense vegetation holds back `10 % × cover` of each day's runoff (forests upstream lower the stage),
  dams store the peak, and building on high banks avoids the floodplain.

## 11. Wildfire (`_wildfire`)
- Only during a drought or the dry season. Each dense (veg ≥ 0.5), dry (moisture < 0.08) land tile without a
  building (farms allowed) ignites with chance `0.0015 × climate_fire` per day (× 0.3 outside droughts), using a
  per-tile hash so the weather RNG stream is untouched. One fire at a time (`WILDFIRE`).
- Fire burns 3 days per tile, cuts vegetation ×0.4 and moisture ×0.7 each day, destroys growing crops, spreads to
  neighbours with veg > 0.3 and moisture < 0.15 (45 %/day). Houses and the village are defended.
  Rain ≥ 0.02 puts it out. Burned forest becomes open land (veg ≤ 0.04) that then erodes. Ends with `FIRE_OUT`.

## 12. Keystone score
`100 × (0.2·plants + 0.2·soil + 0.15·water clarity + 0.15·fish + 0.1·wildlife + 0.2·village)`, each part in 0–1:
plants = mean land vegetation / 0.55, soil = mean depth / 0.75, water = 1 − (turbidity − 0.01)/0.05, fish / 100,
goats / 25, village = min(food EMA, water EMA).

## 13. Rare events (`_rare`, only when `world.rare_events` — daily / weekly / endless and sandbox)
- At most one per day, from a single deterministic roll `_chance(0, 101)`, and none within **30 days** of the
  previous one (`RARE_COOLDOWN`). Each hit increments `rare_hits` and is shown in the codex once seen.
  A hit only becomes *weathered* (`rare_weathered`, the scored count) when the run is still going
  with villagers alive exactly `RARE_COOLDOWN` (30) days later; a run that ends inside that window
  gets nothing for the event that broke it. (Save v4; v1–v3 saves count past hits except one still
  inside its cooldown.)
- **Locusts** — dry season or drought, chance 0.01/day. Every farm with crop > 5 % and **no forest within 2 tiles**
  loses its crop. Caused by the drought (or dry season). Counter: forest near farms; **frogs block swarms
  entirely**. Only the stripped farms point at the event in the inspector.
- **Algal bloom** — summer, chance 0.012/day, only if coastal turbidity > 0.025 **and** ≥ 3 farms. Fish × 0.65.
  Caused by the current muddy-coast event, if any. Counter: keep the coast clear (slope forest, restore bare land).
- **King tide** — wet season, chance 0.008/day. Beach/lowland tiles orthogonally next to water with **no forest
  within 1 tile**: vegetation × 0.5, moisture 1, farm crops wiped. Counter: coastal forest (a mangrove belt).

## 14. Species (`species_supported`, checked every 10 days)
Pure function of the current state; arrivals and departures are logged (`SPECIES_ARRIVED` / `SPECIES_LEFT`) and
`species_seen` accumulates for scoring and the codex.

| Species | Habitat rule | Effect while present |
|---|---|---|
| Bees | forest tiles ≥ 1/6 of land, and ≥ 1 farm | crop growth × 1.15 |
| Seabirds | fish ≥ 70 and coastal turbidity < 0.03 | +0.25 food/day to the village store |
| Frogs | ≥ 4 land tiles with surface water > 0.02 or reservoir > 0.05 | locust swarms cannot happen |
| Wolves | goats ≥ 22 and forest ≥ 1/4 of land | goats × (1 − 0.004) per day (less grazing) |

## 15. Seeded modes: endless escalation, census, scoring
- **Endless**: every 120 days `climate_storm × 1.08` (cap 3), `climate_fire × 1.08` (cap 4), `climate_rain × 0.95`
  (floor 0.45). At each year end the village needs `min(6 + 1 × year, 20)` villagers (year 0 = first census), else
  the run ends (FAILED, scored). Any mode also fails at ≤ `fail_villagers` villagers (daily/weekly 5, endless 4).
- **Daily / weekly**: survive 240 / 360 days with 2 / 3 mutators drawn deterministically from the id; a mutator
  is only eligible if its `from` date ≤ the island's date, so adding content never changes existing islands.
- **Score** (weights in `data/modes.json`): `1·days + 3·keystone + 30·(peak villagers − 10 start)
  + 5·harvests + 30·species seen + 20·rare events weathered (outlasted by 30 days) − 8·villagers lost`, × the product of the mutators' `score_mult`,
  floored at 0. Medal thresholds (bronze/silver/gold): daily 850/1100/1400, weekly
  1200/1500/1900, endless 1600/2300/3000, calibrated with `tools/balance.gd` so an untouched island earns none; relaxed runs score but earn no medal. The score
  is frozen when the run ends (won or failed).
