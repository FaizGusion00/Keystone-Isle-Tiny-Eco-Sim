class_name Hud
extends CanvasLayer
## Mobile-first HUD built in code: top bar (title, seed, day, time controls, new island),
## tile inspector, bottom tool bar, toast messages.

signal new_island_requested
signal speed_requested(speed: int)
signal tool_selected(tool: int)

enum Tool { INSPECT, CLEAR_TREES, PLANT_TREES }
const TOOL_LABELS := ["Inspect", "Clear trees", "Plant trees"]

var root: Control
var _seed_label: Label
var _day_label: Label
var _speed_buttons: Array[Button] = []
var _tool_buttons: Array[Button] = []
var _inspector: PanelContainer
var _insp_title: Label
var _insp_body: Label
var _toast: Label
var _toast_timer: Timer
var tool: int = Tool.INSPECT


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.make_theme()
	add_child(root)
	_build_top_bar()
	_build_inspector()
	_build_tool_bar()
	_build_toast()


func _build_top_bar() -> void:
	var bar := UiKit.panel()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	row.add_child(UiKit.label("Keystone Isle", 28))
	_seed_label = UiKit.label("Seed: -")
	_seed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_seed_label)
	_day_label = UiKit.label("Day 0")
	_day_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_day_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var group := ButtonGroup.new()
	for s in [["Pause", SimClock.Speed.PAUSED], ["1x", SimClock.Speed.NORMAL], ["4x", SimClock.Speed.FAST]]:
		var b := UiKit.button(s[0], Vector2(84, 60))
		b.toggle_mode = true
		b.button_group = group
		var sp: int = s[1]
		b.pressed.connect(func() -> void: speed_requested.emit(sp))
		row.add_child(b)
		_speed_buttons.append(b)
	var new_btn := UiKit.button("New island", Vector2(160, 60))
	new_btn.pressed.connect(func() -> void: new_island_requested.emit())
	row.add_child(new_btn)
	top_bar_row = row


var top_bar_row: HBoxContainer


func _build_inspector() -> void:
	_inspector = UiKit.panel()
	_inspector.anchor_left = 1.0
	_inspector.anchor_right = 1.0
	_inspector.offset_left = -340
	_inspector.offset_right = -12
	_inspector.offset_top = 96
	_inspector.custom_minimum_size = Vector2(328, 0)
	root.add_child(_inspector)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_inspector.add_child(col)
	_insp_title = UiKit.label("Tile inspector", 24)
	col.add_child(_insp_title)
	_insp_body = UiKit.label("Tap a tile to inspect it.")
	_insp_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_body.custom_minimum_size = Vector2(304, 0)
	col.add_child(_insp_body)
	inspector_column = col


var inspector_column: VBoxContainer


func _build_tool_bar() -> void:
	var bar := UiKit.panel()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -88
	bar.offset_bottom = -8
	bar.offset_left = 8
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var group := ButtonGroup.new()
	for t in TOOL_LABELS.size():
		var b := UiKit.button(TOOL_LABELS[t], Vector2(150, 64))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t == Tool.INSPECT
		var tt := t
		b.pressed.connect(func() -> void:
			tool = tt
			tool_selected.emit(tt))
		row.add_child(b)
		_tool_buttons.append(b)
	tool_bar_row = row


var tool_bar_row: HBoxContainer


func _build_toast() -> void:
	_toast = UiKit.label("", 24)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 100
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func() -> void: _toast.text = "")
	add_child(_toast_timer)


func toast(msg: String, seconds: float = 2.5) -> void:
	_toast.text = msg
	_toast_timer.start(seconds)


func set_seed(s: int) -> void:
	_seed_label.text = "Seed: %d" % s


func set_speed(s: int) -> void:
	for k in _speed_buttons.size():
		_speed_buttons[k].set_pressed_no_signal(k == s)


func set_day(day: int) -> void:
	_day_label.text = "Day %d" % day


func show_tile(sim: Simulation, t: Vector2i) -> void:
	var ws := sim.world if sim != null else null
	if ws == null or not ws.in_bounds(t.x, t.y):
		_insp_title.text = "Tile inspector"
		_insp_body.text = "Tap a tile to inspect it."
		return
	_insp_title.text = "Tile (%d, %d)" % [t.x, t.y]
	_insp_body.text = tile_text(sim, t)


## Inspector text; later milestones extend this.
func tile_text(sim: Simulation, t: Vector2i) -> String:
	var ws := sim.world
	var i := ws.index(t.x, t.y)
	return "Land: %s\nElevation: %.2f\nSoil moisture: %d%%\nVegetation: %d%%\nSoil depth: %d%%\nSurface water: %.3f\nSediment: %.3f" % [
		LandType.name_of(ws.land_type[i]), ws.elevation[i],
		roundi(ws.soil_moisture[i] * 100.0), roundi(ws.vegetation_cover[i] * 100.0),
		roundi(ws.soil_depth[i] * 100.0), ws.surface_water[i], ws.sediment[i]]
