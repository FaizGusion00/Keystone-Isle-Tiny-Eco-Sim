class_name Hud
extends CanvasLayer
## Mobile-first HUD built in code: top bar, tile inspector.

signal new_island_requested

var _root: Control
var _seed_label: Label
var _inspector: PanelContainer
var _insp_title: Label
var _insp_body: Label


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.make_theme()
	add_child(_root)
	_build_top_bar()
	_build_inspector()


func _build_top_bar() -> void:
	var bar := UiKit.panel()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	row.add_child(UiKit.label("Keystone Isle", 28))
	_seed_label = UiKit.label("Seed: -")
	_seed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_seed_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var new_btn := UiKit.button("New island", Vector2(170, 60))
	new_btn.pressed.connect(func() -> void: new_island_requested.emit())
	row.add_child(new_btn)


func _build_inspector() -> void:
	_inspector = UiKit.panel()
	_inspector.anchor_left = 1.0
	_inspector.anchor_right = 1.0
	_inspector.offset_left = -330
	_inspector.offset_right = -12
	_inspector.offset_top = 96
	_inspector.custom_minimum_size = Vector2(318, 0)
	_root.add_child(_inspector)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_inspector.add_child(col)
	_insp_title = UiKit.label("Tile inspector", 24)
	col.add_child(_insp_title)
	_insp_body = UiKit.label("Tap a tile to inspect it.")
	_insp_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_body.custom_minimum_size = Vector2(294, 0)
	col.add_child(_insp_body)


func set_seed(s: int) -> void:
	_seed_label.text = "Seed: %d" % s


func show_tile(ws: WorldState, t: Vector2i) -> void:
	if ws == null or not ws.in_bounds(t.x, t.y):
		_insp_title.text = "Tile inspector"
		_insp_body.text = "Tap a tile to inspect it."
		return
	var i := ws.index(t.x, t.y)
	_insp_title.text = "Tile (%d, %d)" % [t.x, t.y]
	_insp_body.text = "Land: %s\nElevation: %.2f\nSoil moisture: %d%%\nVegetation: %d%%" % [
		LandType.name_of(ws.land_type[i]), ws.elevation[i],
		roundi(ws.soil_moisture[i] * 100.0), roundi(ws.vegetation_cover[i] * 100.0)]
