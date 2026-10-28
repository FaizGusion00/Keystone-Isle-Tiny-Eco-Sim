class_name CatchUp
extends RefCounted
## Deterministic "while you were away" catch-up.
## Elapsed real time × the ticks-per-second of the speed the player left the game at gives a
## tick count, capped at MAX_TICKS. The ticks are the same Simulation.step() calls the clock
## makes, so N catch-up ticks == N normal ticks (tested). They run in batches across frames so
## the UI stays responsive. Paused games never catch up.

const MAX_TICKS := 360       ## at most one in-game year per absence
const BATCH := 40            ## ticks per frame (~30 ms at 32×32)
const SUMMARY_MIN_TICKS := 10

var sim: Simulation
var remaining := 0
var total := 0
var start_tick := 0
var before := {}


static func compute_ticks(elapsed_seconds: float, speed: int, cap: int = MAX_TICKS) -> int:
	if speed == SimClock.Speed.PAUSED or elapsed_seconds <= 0.0 or is_nan(elapsed_seconds):
		return 0
	return mini(int(floor(elapsed_seconds * SimClock.TICKS_PER_SECOND[speed])), cap)


func begin(s: Simulation, ticks: int) -> void:
	sim = s
	remaining = maxi(ticks, 0)
	total = remaining
	start_tick = s.world.tick
	before = {"villagers": s.world.villagers, "food": s.world.food_store, "fish": s.world.fish, "goats": s.world.goats}


func active() -> bool:
	return remaining > 0


## Runs up to `batch` ticks; returns true when finished. Stops early if the scenario ends.
func process_batch(batch: int = BATCH) -> bool:
	var n := mini(batch, remaining)
	for k in n:
		sim.step()
		remaining -= 1
		if sim.scenario != null and sim.scenario.status != Scenario.Status.RUNNING:
			remaining = 0
			break
	return remaining == 0


func run_all() -> void:
	while not process_batch():
		pass


## Text for the "While you were away" popup, built only from the event log + counters.
func summary() -> String:
	var ws := sim.world
	var days := ws.tick - start_tick
	var lines := PackedStringArray()
	lines.append("%d days passed." % days)
	lines.append("Villagers %d → %d   Food %d → %d   Fish %d → %d" % [
		before["villagers"], ws.villagers, roundi(before["food"]), roundi(ws.food_store),
		roundi(before["fish"]), roundi(ws.fish)])
	var notable := PackedStringArray()
	var minor := {}
	for id in sim.events.since_tick(start_tick):
		var t := sim.events.type_of(id)
		if t == EventLog.Type.EROSION or t == EventLog.Type.HEAVY_RAIN:
			minor[t] = int(minor.get(t, 0)) + 1
		else:
			notable.append(sim.events.describe(id))
	if notable.is_empty() and minor.is_empty():
		lines.append("Nothing notable happened.")
	for k in mini(notable.size(), 8):
		lines.append("• " + notable[notable.size() - 1 - k])  # newest first
	if notable.size() > 8:
		lines.append("• …and %d more (see History)" % (notable.size() - 8))
	for t in minor:
		lines.append("• %d × %s" % [minor[t], EventLog.TYPE_NAMES[t]])
	return "\n".join(lines)
