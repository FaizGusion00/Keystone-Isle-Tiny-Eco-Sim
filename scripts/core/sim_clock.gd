class_name SimClock
extends Node
## Fixed-tick driver decoupled from rendering. Real time only decides HOW MANY ticks run;
## the simulation itself never sees delta.

signal ticked(count: int)

## NORMAL = 1x, X2 = 2x, FAST = 4x. (v1 saves stored FAST as 2; SaveSystem.migrate_speed maps it.)
enum Speed { PAUSED, NORMAL, X2, FAST }
const TICKS_PER_SECOND := [0.0, 2.0, 4.0, 8.0]
const SPEED_LABELS := ["Pause", "1x", "2x", "4x"]
const MAX_TICKS_PER_FRAME := 8

var sim: Simulation
var speed: int = Speed.NORMAL
var _accum := 0.0
var blocked := false  ## true while suspended (app in background) or catching up


func ticks_per_second() -> float:
	return TICKS_PER_SECOND[speed]


func set_speed(s: int) -> void:
	speed = s
	_accum = 0.0


func _process(delta: float) -> void:
	if sim == null or speed == Speed.PAUSED or not can_tick():
		return
	_accum += minf(delta, 0.5) * ticks_per_second()
	var n := 0
	while _accum >= 1.0 and n < MAX_TICKS_PER_FRAME:
		sim.step()
		_accum -= 1.0
		n += 1
	_accum = minf(_accum, float(MAX_TICKS_PER_FRAME))
	if n > 0:
		ticked.emit(n)


func can_tick() -> bool:
	return not blocked
