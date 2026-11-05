class_name Guide
extends Node
## Runs a guided sequence of steps (GuideSteps.TUTORIAL). A step shows a card that points at one
## thing and waits until the player has done what it asks; only then does the next step open.
## The guide decides when the clock may run, which tools / numbers are visible, and nudges a
## player who seems stuck. main.gd feeds it what happens (tools, builds, taps, ticks).

signal step_changed(i: int)
signal finished(skipped: bool)

var steps: Array = []
var i := -1
var main: Node
var _step_tick := 0           ## sim day the current step opened
var _hinted := false
var _start := {}              ## state captured when a step opens (harvests, villagers…)
var _unlocked := {"tools": [], "chips": [], "extras": []}


func active() -> bool:
	return i >= 0 and i < steps.size()


func current() -> Dictionary:
	return steps[i] if active() else {}


func start(s: Array, at := 0) -> void:
	steps = s
	_unlocked = {"tools": [Hud.Tool.INSPECT], "chips": [], "extras": []}
	for k in mini(at, s.size()):
		_merge(s[k].get("unlock", {}))
		if s[k].has("hint_unlock"):
			_merge(s[k]["hint_unlock"])
	_go(at)


func stop(skipped := false) -> void:
	if not active():
		return
	i = -1
	main.hud.hide_guide()
	finished.emit(skipped)


## True while the current step wants time to stand still (reading / doing a first action).
func holds_clock() -> bool:
	return active() and str(current().get("clock", "hold")) == "hold"


func to_dict() -> Dictionary:
	return {"i": i} if active() else {}


func _go(n: int) -> void:
	if n >= steps.size():
		stop(false)
		return
	i = n
	var st := current()
	_merge(st.get("unlock", {}))
	_apply_unlocks(n > 0)
	_step_tick = main.sim.world.tick
	_hinted = false
	_start = {"harvests": main.sim.world.harvests, "villagers": main.sim.world.villagers,
		"farms": main.sim.world.count_structures(WorldState.Structure.FARM)}
	if str(st.get("wait", "")) == "speed":
		main.set_speed(SimClock.Speed.PAUSED)  # so pressing Play is a real choice
	elif str(st.get("clock", "hold")) == "run" and main.clock.speed == SimClock.Speed.PAUSED:
		main.set_speed(SimClock.Speed.NORMAL)
	if str(st.get("camera", "")) == "village":
		main.focus_village()
	# the goals card stays a small pill until the step about goals (one thing to read at a time)
	main.hud.set_goals_collapsed(str(st.get("target", "")) != "ui:goals")
	main.hud.show_guide(st, n, steps.size(), main.camera.last_was_touch)
	step_changed.emit(n)
	_check()  # already done? (e.g. the farm tool was picked before this step opened)


func _merge(u: Dictionary) -> void:
	for k in ["tools", "chips", "extras"]:
		for v in u.get(k, []):
			if not (_unlocked[k] as Array).has(v):
				(_unlocked[k] as Array).append(v)


func _apply_unlocks(announce: bool) -> void:
	main.hud.set_available(_unlocked["tools"], _unlocked["chips"], _unlocked["extras"], false, announce)


## The player pressed the card's Next.
func next() -> void:
	if active() and str(current().get("wait", "")) == "next":
		_advance()


func _advance() -> void:
	AudioDirector.sfx("notify", 1.15, -6.0)
	var was_last := bool(current().get("last", false))
	if was_last:
		i = steps.size()
		main.hud.hide_guide()
		finished.emit(false)
		return
	_go(i + 1)


# ---------------------------------------------------------------- inputs from main

func on_tool(_t: int) -> void:
	_check()


func on_action(_a: int, _t: Vector2i) -> void:
	_check()


func on_select(_t: Vector2i) -> void:
	_check()


func on_speed(_s: int) -> void:
	_check()


func on_chip(key: String) -> void:
	if active() and str(current().get("wait", "")) == "chip:" + key:
		_advance()


func on_tick() -> void:
	if not active():
		return
	var st := current()
	if not _hinted and st.has("hint_after") and main.sim.world.tick - _step_tick >= int(st["hint_after"]):
		_hinted = true
		if st.has("hint_unlock"):
			_merge(st["hint_unlock"])
			_apply_unlocks(true)
		main.hud.guide_hint(str(st.get("hint", "")))
	_check()


func _check() -> void:
	if active() and _met(str(current().get("wait", "next"))):
		_advance()


func _met(w: String) -> bool:
	var ws: WorldState = main.sim.world
	match w:
		"next":
			return false
		"select_village":
			return main.selected.x >= 0 and ws.index(main.selected.x, main.selected.y) == ws.settlement_index
		"action:farm":
			return ws.count_structures(WorldState.Structure.FARM) > int(_start.get("farms", 0))
		"speed":
			return main.clock.speed != SimClock.Speed.PAUSED
		"harvest":
			return ws.harvests > int(_start.get("harvests", 0))
		"grow":
			return ws.villagers > int(_start.get("villagers", 0))
	if w.begins_with("tool:"):
		return main.hud.tool == int(w.trim_prefix("tool:"))
	return false
