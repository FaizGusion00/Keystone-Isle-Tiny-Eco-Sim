class_name Hud
extends CanvasLayer
## In-game HUD, built in code from UiKit pieces:
##   top-left day/season chip · resource chips + island-health meter · speed segment + menu
##   objectives card · slide-in tile inspector (bottom sheet in portrait) · icon toolbar with
##   costs · overlay legend · history drawer with why-chains · toast stack · modal popup ·
##   coach-mark tutorial. Re-lays itself out for landscape/portrait, safe areas and UI scale.

signal new_island_requested
signal tutorial_requested
signal speed_requested(speed: int)
signal tool_selected(tool: int)
signal overlay_requested
signal events_requested
signal why_requested(event_id: int)
signal menu_requested
signal tile_closed
signal coach_finished

enum Tool { INSPECT, CLEAR_TREES, PLANT_TREES, BUILD_FARM, BUILD_HOUSE, BUILD_DAM, RESTORE_LAND, DEMOLISH }
const TOOL_LABELS := ["Inspect", "Clear", "Plant", "Farm", "House", "Dam", "Restore", "Remove"]
const TOOL_ICONS := ["search", "axe", "sprout", "wheat", "house", "brick-wall", "shovel", "trash-2"]
const TOOL_ACTIONS := [0, 1, 2, 3, 4, 5, 6, 7] ## Tool index == Simulation.Action value
const TOOL_TIPS := [
	"Inspect a tile: see soil, water, plants and what happened there.",
	"Clear trees for wood. Bare slopes erode in heavy rain!",
	"Plant trees: holds soil and water, cleans streams.",
	"Build a farm near the village. Needs moist soil.",
	"Build a house next to the village: room for more villagers.",
	"Build a dam on a stream: stores water, irrigates farms, but blocks fish runs.",
	"Restore damaged or burnt land.",
	"Remove a building (refunds half its wood).",
]
const SEASON_ICONS := ["sprout", "cloud-rain", "sun", "thermometer"]
const KIND_ICONS := ["hand", "cloud-sun", "mountain", "fish", "users", "flame"]
## Per-event-type icons; anything missing falls back to its kind's icon.
const TYPE_ICONS := {
	EventLog.Type.TREES_CLEARED: "axe", EventLog.Type.TREES_PLANTED: "sprout", EventLog.Type.FARM_BUILT: "wheat",
	EventLog.Type.HEAVY_RAIN: "cloud-rain", EventLog.Type.DROUGHT: "sun", EventLog.Type.DROUGHT_ENDED: "cloud-drizzle",
	EventLog.Type.EROSION: "mountain", EventLog.Type.MUDDY_WATER: "droplets", EventLog.Type.WATER_CLEARED: "droplet",
	EventLog.Type.FISH_DECLINE: "fish", EventLog.Type.HERBIVORE_DECLINE: "rabbit", EventLog.Type.CROP_FAILURE: "wheat",
	EventLog.Type.HARVEST_LOST: "wheat", EventLog.Type.FOOD_SHORTAGE: "beef", EventLog.Type.WATER_SHORTAGE: "droplet",
	EventLog.Type.LAND_CLEARED: "shovel", EventLog.Type.HOUSE_BUILT: "house", EventLog.Type.DAM_BUILT: "brick-wall",
	EventLog.Type.LAND_RESTORED: "leaf", EventLog.Type.STRUCTURE_REMOVED: "trash-2",
	EventLog.Type.DRY_SEASON: "sun", EventLog.Type.WET_SEASON: "cloud-rain",
	EventLog.Type.WILDFIRE: "flame", EventLog.Type.FIRE_OUT: "cloud-drizzle", EventLog.Type.FLOOD: "waves",
	EventLog.Type.HOUSING_FULL: "home",
	EventLog.Type.LOCUSTS: "bug", EventLog.Type.ALGAL_BLOOM: "waves", EventLog.Type.KING_TIDE: "anchor",
	EventLog.Type.SPECIES_ARRIVED: "bird", EventLog.Type.SPECIES_LEFT: "bird",
}


static func event_icon(t: int) -> String:
	if TYPE_ICONS.has(t):
		return str(TYPE_ICONS[t])
	var kind := EventLog.kind_of_type(t)
	return str(KIND_ICONS[kind]) if kind >= 0 and kind < KIND_ICONS.size() else "info"
const KIND_COLORS := [Color("2f7d6d"), Color("4a8fb8"), Color("9a7650"), Color("5f9e45"), Color("8a5fb0"), Color("d0603f")]

var root: Control
var tool: int = Tool.INSPECT
var ui_scale := 1.0
var portrait := false
var safe := Vector4.ZERO
var reduce_motion := false
var _sim: Simulation

# top-left / chips / speed
var _day_card: PanelContainer
var _day_label: Label
var _season_label: Label
var _season_icon: TextureRect
var _seed := 0
var _chips_flow: HFlowContainer
var _chips := {}           ## key -> {panel, value, icon}
var _keystone_bar: ProgressBar
var _keystone_value: Label
var _speed_card: PanelContainer
var _speed_buttons: Array[Button] = []
var top_bar_row: Control
var status_panel: Control
var status_label: Label    ## hidden plain-text mirror of the chips (tests/debug)

# objectives
var _obj_card: PanelContainer
var _obj_title: Label
var _obj_rows: VBoxContainer
var _obj_footer: Label
var _obj_collapsed := false
var _obj_chev: Button
var objective_label: Label ## plain-text mirror (one line)

# inspector
var _inspector: PanelContainer
var _insp_badge: PanelContainer
var _insp_title: Label
var _insp_sub: Label
var _insp_rows: VBoxContainer
var _insp_event_box: PanelContainer
var _insp_event: Label
var _why_btn: Button
var _insp_event_id := -1
var _insp_tile := Vector2i(-1, -1)
var inspector_column: VBoxContainer

# toolbar
var _toolbar: PanelContainer
var _side: PanelContainer
var _tool_sep: ColorRect
var _tool_scroll: ScrollContainer
var _tool_buttons: Array[Button] = []
var _tool_cost: Array[Label] = []
var _tool_icon: Array[TextureRect] = []
var _tool_name: Array[Label] = []
var tool_bar_row: HBoxContainer
var overlay_button: Button
var events_button: Button
var _overlay_index := 0

# legend
var _legend: PanelContainer
var _legend_title: Label
var _legend_grad: TextureRect

# history
var events_panel: PanelContainer
var _events_list: VBoxContainer
var _chain: VBoxContainer
var _chain_scroll: ScrollContainer
var _explain_lines := PackedStringArray()
var _event_log: EventLog
var _minor_toggle: Button
var _tool_more: Button
var _tool_page := 0
var _tool_pages := 1
var _tool_per := 99
const TOOL_W := 74.0
const TOOL_MIN_W := 60.0
var _hist_list_pane: VBoxContainer
var _hist_detail_pane: VBoxContainer
var _hist_back: Button
var _hist_why_icon: TextureRect
var _hist_two_col := false
var _hist_detail := false
var _selected_event := -1
const MINOR_TYPES := [EventLog.Type.EROSION]

# toasts
var _toasts: VBoxContainer
var _last_toast := ""
# award banner: achievements / unlocks / level-ups, shown one at a time (never stacked)
var _award: PanelContainer
var _award_icon: PanelContainer
var _award_title: Label
var _award_sub: Label
var _award_queue: Array[PackedStringArray] = []
var _award_busy := false

# popup
var popup: PanelContainer
var _scrim: ColorRect
var _popup_title: Label
var _popup_icon: PanelContainer
var _popup_body: Label
var _popup_queue: Array[PackedStringArray] = []

# coach marks
var _coach: Control
var _coach_ring: Panel
var _coach_card: PanelContainer
var _coach_text: Label
var _coach_step_label: Label
var _coach_next: Button
var _coach_steps: Array = []
var _coach_i := -1


func _ready() -> void:
	root = Control.new()
	root.name = "HudRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.make_theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(root)
	_build_day()
	_build_chips()
	_build_speed()
	_build_objectives()
	_build_inspector()
	_build_tool_bar()
	_build_legend()
	_build_events_panel()
	_build_toasts()
	_build_award()
	_build_popup()
	_build_coach()
	for owned in [_inspector, _legend, events_panel, popup, _coach_card, _side]:
		if owned != null:
			owned.set_meta("layout_owned", true)
	get_viewport().size_changed.connect(relayout)
	relayout()


# ================================================================== layout

func set_ui_scale(s: float) -> void:
	ui_scale = clampf(s, 0.75, 1.5)
	relayout()


func relayout() -> void:
	if root == null:
		return
	safe = UiKit.safe_insets(get_viewport())
	var sz := UiKit.fit_root(self, root, ui_scale)
	portrait = sz.x < sz.y
	_layout(sz)
	call_deferred("_layout", sz)  # again once containers know their minimum sizes


func _layout(sz: Vector2) -> void:
	var m := 14.0
	var l := m + safe.x
	var t := m + safe.y
	var r := sz.x - m - safe.z
	var b := sz.y - m - safe.w
	var w := r - l
	# --- toolbar (bottom); in portrait the Layers/History buttons move to a side stack
	var side_col := _side.get_child(0) as VBoxContainer
	var want_side := portrait
	if want_side != (overlay_button.get_parent() == side_col):
		for btn in [overlay_button, events_button]:
			btn.get_parent().remove_child(btn)
			if want_side:
				side_col.add_child(btn)
			else:
				tool_bar_row.add_child(btn)
	_tool_sep.visible = not want_side
	_side.visible = want_side and not events_panel.visible
	_fit_tools(w - 20.0)
	_tool_scroll.custom_minimum_size = Vector2(0, 0)
	var tb_min := tool_bar_row.get_combined_minimum_size()
	var tb_w := minf(tb_min.x + 4.0, w - 16.0)
	_tool_scroll.custom_minimum_size = Vector2(tb_w, tb_min.y)
	_toolbar.reset_size()
	_toolbar.position = Vector2(l + (w - _toolbar.size.x) * 0.5, b - _toolbar.size.y)
	var bottom_y := _toolbar.position.y - 10.0
	# --- top row: day chip | chips | speed
	_day_card.reset_size()
	_speed_card.reset_size()
	_day_card.position = Vector2(l, t)
	_speed_card.position = Vector2(r - _speed_card.size.x, t)
	var chips_w: float
	var chips_y: float
	if portrait:
		chips_w = w
		chips_y = t + maxf(_day_card.size.y, _speed_card.size.y) + 8.0
		_chips_flow.position = Vector2(l, chips_y)
	else:
		var left_edge := l + _day_card.size.x + 10.0
		chips_w = r - _speed_card.size.x - 10.0 - left_edge
		chips_y = t
		_chips_flow.position = Vector2(left_edge, t)
	_chips_flow.custom_minimum_size = Vector2(chips_w, 0)
	_chips_flow.size = Vector2(chips_w, 0)
	_chips_flow.alignment = FlowContainer.ALIGNMENT_CENTER if not portrait else FlowContainer.ALIGNMENT_BEGIN
	_chips_flow.reset_size()
	var chips_h := _chips_flow.get_combined_minimum_size().y
	var top_bottom := maxf(chips_y + chips_h, t + maxf(_day_card.size.y, _speed_card.size.y)) + 10.0
	# --- objectives card (top-left below)
	var obj_w := minf(372.0, w) if not portrait else w
	_obj_card.custom_minimum_size = Vector2(obj_w, 0)
	_obj_card.reset_size()
	_obj_card.position = Vector2(l, top_bottom)
	if _sim != null and _sim.scenario != null:
		_obj_card.visible = not events_panel.visible
	# --- inspector
	var insp_w := w if portrait else minf(360.0, w * 0.4)
	_insp_event.custom_minimum_size.x = insp_w - 70.0  # wrap width known up front (no tall first pass)
	if portrait:
		_inspector.custom_minimum_size = Vector2(w, 0)
		_inspector.reset_size()
		_inspector.position = Vector2(l, bottom_y - _inspector.size.y)
	else:
		_inspector.custom_minimum_size = Vector2(minf(360.0, w * 0.4), 0)
		_inspector.reset_size()
		_inspector.position = Vector2(r - _inspector.size.x, top_bottom)
	if want_side:
		_side.reset_size()
		var side_bottom := _inspector.position.y - 8.0 if _inspector.visible else bottom_y
		_side.position = Vector2(r - _side.size.x, side_bottom - _side.size.y)
	# --- legend (bottom-left above the toolbar)
	_legend.reset_size()
	if portrait and _inspector.visible:
		_legend.position = Vector2(l, _inspector.position.y - _legend.size.y - 8.0)
	else:
		_legend.position = Vector2(l, bottom_y - _legend.size.y)
	# --- history drawer
	var hx := l
	var hy := top_bottom
	var two := not portrait and w >= 900.0
	var hw := w if portrait else (minf(980.0, w * 0.74) if two else minf(560.0, w))
	if two != _hist_two_col:
		_hist_two_col = two
		_apply_hist_mode()
	events_panel.position = Vector2(hx, hy)
	events_panel.custom_minimum_size = Vector2(hw, 0)
	events_panel.size = Vector2(hw, maxf(240.0, bottom_y - hy))
	# --- toasts under the top row, centred in whatever space the side panels leave free
	var tl := l
	var tr := r
	if not portrait:
		if events_panel.visible:
			tl = hx + hw + 12.0
		elif _obj_card.visible:
			tl = maxf(tl, _obj_card.position.x + _obj_card.size.x + 12.0)
		if _inspector.visible:
			tr = _inspector.position.x - 12.0
	var tw := minf(520.0, maxf(200.0, tr - tl))
	_toasts.custom_minimum_size.x = tw
	_toasts.size.x = tw
	# a phone-portrait history drawer already lists every event, so toasts stay out of its way
	_toasts.visible = not (portrait and events_panel.visible)
	var toast_y := top_bottom + 4.0
	if portrait and _obj_card.visible:
		toast_y = _obj_card.position.y + _obj_card.size.y + 8.0  # full-width goals card owns the top
	_toasts.position = Vector2(tl + (tr - tl - tw) * 0.5, toast_y)
	# --- popup + scrim
	_scrim.position = Vector2.ZERO
	_scrim.size = sz
	popup.custom_minimum_size = Vector2(minf(580.0, w), 0)
	_popup_body.custom_minimum_size = Vector2(minf(580.0, w) - 40.0, 0)
	popup.reset_size()
	popup.position = (sz - popup.size) * 0.5
	_coach.size = sz
	_place_award()
	if _coach_i >= 0:
		_place_coach()


func _flow_chip(key: String, icon_name: String, tip: String) -> void:
	var p := UiKit.card("Chip")
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := UiKit.hbox(6)
	p.add_child(row)
	var ic := UiKit.icon(icon_name, 20, UiKit.TEAL_DARK)
	row.add_child(ic)
	var v := UiKit.label("0", 0, "Value")
	row.add_child(v)
	_chips_flow.add_child(p)
	_chips[key] = {"panel": p, "value": v, "icon": ic}


# ================================================================== top bar

func _build_day() -> void:
	_day_card = UiKit.card("Chip")
	root.add_child(_day_card)
	var row := UiKit.hbox(10)
	_day_card.add_child(row)
	_season_icon = UiKit.icon("sprout", 26, UiKit.TEAL)
	row.add_child(_season_icon)
	var col := UiKit.vbox(0)
	row.add_child(col)
	_day_label = UiKit.label("Day 0", 0, "Subheading")
	col.add_child(_day_label)
	_season_label = UiKit.label("Spring", 0, "Caption")
	_season_label.add_theme_font_size_override("font_size", 13)
	col.add_child(_season_label)


func _build_chips() -> void:
	_chips_flow = HFlowContainer.new()
	_chips_flow.add_theme_constant_override("h_separation", 6)
	_chips_flow.add_theme_constant_override("v_separation", 6)
	_chips_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chips_flow)
	top_bar_row = _chips_flow
	status_panel = _chips_flow
	_flow_chip("villagers", "users", "Villagers / homes available")
	_flow_chip("food", "wheat", "Food stored")
	_flow_chip("water", "droplet", "Fresh water: share of the village's need met")
	_flow_chip("fish", "fish", "Fish in coastal waters (need clear water)")
	_flow_chip("goats", "rabbit", "Wild goats (need grass and forest)")
	_flow_chip("labor", "hammer", "Labor: spent by tools, regrows each day")
	_flow_chip("wood", "axe", "Wood: from clearing forest, spent on buildings")
	# island health meter
	var p := UiKit.card("Chip")
	p.tooltip_text = "Island health: plants, soil, water, fish, wildlife and village together"
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := UiKit.hbox(8)
	p.add_child(row)
	row.add_child(UiKit.icon("heart-pulse", 20, UiKit.CORAL))
	_keystone_bar = UiKit.meter(0.5, UiKit.LEAF, 10, 84)
	row.add_child(_keystone_bar)
	_keystone_value = UiKit.label("50", 0, "Value")
	row.add_child(_keystone_value)
	_chips_flow.add_child(p)
	_chips["keystone"] = {"panel": p, "value": _keystone_value, "icon": null}
	status_label = UiKit.label("")
	status_label.visible = false
	root.add_child(status_label)


func _build_speed() -> void:
	_speed_card = UiKit.card("Chip")
	root.add_child(_speed_card)
	var row := UiKit.hbox(6)
	_speed_card.add_child(row)
	var seg := UiKit.card("Segmented")
	row.add_child(seg)
	var srow := UiKit.hbox(2)
	seg.add_child(srow)
	var group := ButtonGroup.new()
	var icons := ["pause", "play", "chevrons-right", "fast-forward"]
	var tips := ["Pause", "Normal speed", "Fast (2×)", "Fastest (4×)"]
	for k in 4:
		var b := UiKit.button("", Vector2(50, 48), icons[k], "Segment")
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = tips[k]
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var sp := k
		b.pressed.connect(func() -> void: speed_requested.emit(sp))
		srow.add_child(b)
		_speed_buttons.append(b)
	var menu := UiKit.icon_button("menu", "Menu")
	menu.custom_minimum_size = Vector2(52, 52)
	menu.pressed.connect(func() -> void: menu_requested.emit())
	row.add_child(menu)


func set_seed(s: int) -> void:
	_seed = s


func seed_value() -> int:
	return _seed


func set_speed(s: int) -> void:
	for k in _speed_buttons.size():
		_speed_buttons[k].set_pressed_no_signal(k == s)


func set_day(day: int) -> void:
	_day_label.text = "Day %d" % day
	var season := Simulation.season_of(day)
	_season_label.text = Simulation.SEASON_NAMES[season]
	_season_icon.texture = UiKit.icon_tex(SEASON_ICONS[season])


func set_status(ws: WorldState) -> void:
	var cap := ws.housing_capacity()
	_chip("villagers", "%d/%d" % [ws.villagers, cap], ws.housing_event >= 0)
	_chip("food", "%d" % roundi(ws.food_store), ws.food_event >= 0)
	_chip("water", "%d%%" % roundi(ws.water_ema * 100.0), ws.water_event >= 0)
	_chip("fish", "%d" % roundi(ws.fish), ws.fish_event >= 0)
	_chip("goats", "%d" % roundi(ws.goats), ws.goats_event >= 0)
	var lab_cap := Simulation.LABOR_CAP_BASE + ws.villagers
	_chip("labor", "%d" % floori(ws.labor) if ws.free_build == false else "∞", false)
	_chip("wood", "%d" % floori(ws.wood) if ws.free_build == false else "∞", false)
	_chips["labor"]["panel"].tooltip_text = "Labor: %d of %d. Spent by tools, regrows each day." % [floori(ws.labor), roundi(lab_cap)]
	var k := clampf(ws.keystone / 100.0, 0.0, 1.0)
	_keystone_bar.value = k
	_keystone_value.text = "%d" % roundi(ws.keystone)
	UiKit.set_meter_color(_keystone_bar, UiKit.CORAL if k < 0.4 else (UiKit.AMBER if k < 0.7 else UiKit.LEAF))
	# weather on the day chip
	if ws.rain_today >= Simulation.HEAVY_RAIN:
		_season_icon.texture = UiKit.icon_tex("cloud-lightning")
		_season_label.text = Simulation.SEASON_NAMES[Simulation.season_of(ws.tick)] + " · Storm"
	elif ws.rain_today > 0.0:
		_season_icon.texture = UiKit.icon_tex("cloud-drizzle")
		_season_label.text = Simulation.SEASON_NAMES[Simulation.season_of(ws.tick)] + " · Rain"
	elif ws.fires_burning > 0:
		_season_icon.texture = UiKit.icon_tex("flame")
		_season_label.text = Simulation.SEASON_NAMES[Simulation.season_of(ws.tick)] + " · Wildfire!"
	status_label.text = "Villagers %d   Food %d   Fish %d   Goats %d   Water %d%%   Health %d" % [
		ws.villagers, roundi(ws.food_store), roundi(ws.fish), roundi(ws.goats), roundi(ws.water_ema * 100.0), roundi(ws.keystone)]
	_update_costs(ws)


func _chip(key: String, text: String, warn: bool) -> void:
	var c: Dictionary = _chips[key]
	(c["value"] as Label).text = text
	var p := c["panel"] as PanelContainer
	var want := "ChipWarn" if warn else "Chip"
	if p.theme_type_variation != want:
		p.theme_type_variation = want
		if warn:
			UiKit.pop(p, 0.3)
	var ic := c["icon"] as TextureRect
	if ic != null:
		ic.self_modulate = UiKit.CORAL if warn else UiKit.TEAL_DARK


func status_text() -> String:
	return status_label.text


# ================================================================== objectives

func _build_objectives() -> void:
	_obj_card = UiKit.card()
	_obj_card.visible = false
	root.add_child(_obj_card)
	var col := UiKit.vbox(8)
	_obj_card.add_child(col)
	var head := UiKit.hbox(8)
	col.add_child(head)
	head.add_child(UiKit.icon("flag-triangle-right", 22, UiKit.AMBER))
	_obj_title = UiKit.label("Goals", 19, "Heading")
	_obj_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_obj_title)
	_obj_chev = UiKit.icon_button("chevron-down", "Show/hide goals")
	_obj_chev.custom_minimum_size = Vector2(44, 44)
	_obj_chev.pressed.connect(func() -> void:
		_obj_collapsed = not _obj_collapsed
		_obj_rows.visible = not _obj_collapsed
		_obj_footer.visible = not _obj_collapsed and _obj_footer.text != ""
		_obj_chev.icon = UiKit.icon_tex("chevron-right" if _obj_collapsed else "chevron-down")
		relayout())
	head.add_child(_obj_chev)
	_obj_rows = UiKit.vbox(6)
	col.add_child(_obj_rows)
	_obj_footer = UiKit.label("", 0, "Caption")
	col.add_child(_obj_footer)
	objective_label = UiKit.label("")
	objective_label.visible = false
	root.add_child(objective_label)


## Plain one-line objective (kept for callers without a scenario).
func set_objective(text: String) -> void:
	objective_label.text = text


## Full checklist for the running scenario (call after each tick).
func update_objectives(sim: Simulation) -> void:
	_sim = sim
	var sc := sim.scenario if sim != null else null
	if sc == null:
		_obj_card.visible = false
		return
	objective_label.text = sc.objective_text(sim.world)
	var objs := sc.objectives()
	_obj_card.visible = not events_panel.visible  # the history drawer covers the same corner
	_obj_title.text = sc.title()
	if sc.is_sandbox():
		objs = []
	if _obj_rows.get_child_count() != objs.size():
		for c in _obj_rows.get_children():
			c.queue_free()
			_obj_rows.remove_child(c)
		for k in objs.size():
			var row := UiKit.hbox(8)
			row.add_child(UiKit.icon("circle", 20, UiKit.INK_FAINT))
			var lab := UiKit.label("", 16)
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(lab)
			var val := UiKit.label("", 0, "Badge")
			val.add_theme_font_size_override("font_size", 14)
			row.add_child(val)
			_obj_rows.add_child(row)
	for k in objs.size():
		var o: Dictionary = objs[k]
		var row := _obj_rows.get_child(k) as HBoxContainer
		var ok := sc.objective_done(k, sim.world)
		var ic := row.get_child(0) as TextureRect
		ic.texture = UiKit.icon_tex("circle-check" if ok else "circle")
		ic.self_modulate = UiKit.LEAF if ok else UiKit.INK_FAINT
		(row.get_child(1) as Label).text = Scenario.label(o)
		(row.get_child(1) as Label).modulate = Color(1, 1, 1, 0.55) if ok else Color.WHITE
		(row.get_child(2) as Label).text = Scenario.progress_text(o, sim.world, sc)
	var foot := ""
	if sc.is_sandbox():
		foot = "Free play · no goals or deadline"
	elif sc.status == Scenario.Status.WON:
		foot = "Complete · %d of 3 stars" % sc.stars
	elif sc.status == Scenario.Status.FAILED:
		foot = "Failed · " + sc.reason
	elif sc.deadline() > 0:
		foot = "%d days left" % maxi(0, sc.deadline() - sc.days_elapsed(sim.world))
	_obj_footer.text = foot
	_obj_footer.visible = foot != "" and not _obj_collapsed


# ================================================================== inspector

func _build_inspector() -> void:
	_inspector = UiKit.card()
	_inspector.visible = false
	root.add_child(_inspector)
	var col := UiKit.vbox(10)
	_inspector.add_child(col)
	inspector_column = col
	var head := UiKit.hbox(10)
	col.add_child(head)
	_insp_badge = UiKit.icon_badge("search")
	head.add_child(_insp_badge)
	var tcol := UiKit.vbox(0)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tcol)
	_insp_title = UiKit.label("Tile inspector", 22, "Heading")
	tcol.add_child(_insp_title)
	_insp_sub = UiKit.label("", 0, "Caption")
	tcol.add_child(_insp_sub)
	var close := UiKit.icon_button("x", "Close")
	close.custom_minimum_size = Vector2(48, 48)
	close.pressed.connect(func() -> void: tile_closed.emit())
	head.add_child(close)
	_insp_rows = UiKit.vbox(8)
	col.add_child(_insp_rows)
	_insp_event_box = UiKit.card("InsetWarm")
	col.add_child(_insp_event_box)
	var ecol := UiKit.vbox(8)
	_insp_event_box.add_child(ecol)
	var eh := UiKit.hbox(6)
	eh.add_child(UiKit.icon("history", 18, UiKit.AMBER.darkened(0.3)))
	eh.add_child(UiKit.label("Latest here", 0, "Caption"))
	ecol.add_child(eh)
	_insp_event = UiKit.wrap_label("", "", 0)
	_insp_event.add_theme_font_size_override("font_size", 16)
	ecol.add_child(_insp_event)
	_why_btn = UiKit.primary("Why did this happen?", "circle-help")
	_why_btn.pressed.connect(func() -> void: why_requested.emit(_insp_event_id))
	ecol.add_child(_why_btn)


func inspector_visible() -> bool:
	return _inspector.visible


func show_tile(sim: Simulation, t: Vector2i) -> void:
	_sim = sim
	var ws := sim.world if sim != null else null
	if ws == null or not ws.in_bounds(t.x, t.y):
		if _inspector.visible:
			_slide_out(_inspector)
		_insp_tile = Vector2i(-1, -1)
		return
	var fresh := t != _insp_tile or not _inspector.visible
	_insp_tile = t
	var i := ws.index(t.x, t.y)
	var info := tile_header(sim, t)
	_insp_title.text = info[0]
	_insp_sub.text = "%s · tile %d, %d" % [info[1], t.x, t.y]
	(_insp_badge.get_child(0) as TextureRect).texture = UiKit.icon_tex(info[2])
	var rows := tile_rows(sim, t)
	while _insp_rows.get_child_count() < rows.size():
		_insp_rows.add_child(_stat_row())
	for k in _insp_rows.get_child_count():
		var row := _insp_rows.get_child(k) as HBoxContainer
		row.visible = k < rows.size()
		if k >= rows.size():
			continue
		var d: Array = rows[k]
		(row.get_child(0) as TextureRect).texture = UiKit.icon_tex(d[0])
		(row.get_child(1) as Label).text = d[1]
		var bar := row.get_child(2) as ProgressBar
		bar.modulate.a = 1.0 if float(d[3]) >= 0.0 else 0.0  # keep the column so values stay right-aligned
		bar.value = clampf(float(d[3]), 0.0, 1.0)
		UiKit.set_meter_color(bar, d[4] if d.size() > 4 else UiKit.TEAL)
		(row.get_child(3) as Label).text = d[2]
	_insp_event_id = ws.last_event[i]
	var has_ev := sim.events.has(_insp_event_id)
	_insp_event_box.visible = has_ev
	if has_ev:
		_insp_event.text = sim.events.describe(_insp_event_id)
	if fresh:
		_inspector.visible = true
		relayout()
		_slide_in(_inspector)


func _stat_row() -> HBoxContainer:
	var row := UiKit.hbox(8)
	row.add_child(UiKit.icon("circle", 18, UiKit.INK_SOFT))
	var name := UiKit.label("", 16)
	name.custom_minimum_size.x = 110
	row.add_child(name)
	var bar := UiKit.meter(0.0, UiKit.TEAL, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var val := UiKit.label("", 0, "Value")
	val.add_theme_font_size_override("font_size", 16)
	val.custom_minimum_size.x = 52
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return row


## [title, land name, icon]
func tile_header(sim: Simulation, t: Vector2i) -> Array:
	var ws := sim.world
	var i := ws.index(t.x, t.y)
	var land := LandType.name_of(ws.land_type[i])
	match ws.structure[i]:
		WorldState.Structure.SETTLEMENT: return ["Village", land, "users"]
		WorldState.Structure.FARM: return ["Farm", land, "wheat"]
		WorldState.Structure.HOUSE: return ["House", land, "house"]
		WorldState.Structure.DAM: return ["Dam", land, "brick-wall"]
	if ws.fire[i] > 0:
		return ["On fire!", land, "flame"]
	var icon := "leaf"
	match ws.land_type[i]:
		LandType.FOREST: icon = "trees"
		LandType.HILLS: icon = "mountain"
		LandType.BEACH: icon = "sun"
		LandType.SHALLOW_WATER, LandType.DEEP_WATER: icon = "waves"
		LandType.LOWLAND: icon = "sprout"
	return [land, "Land", icon]


## Inspector rows: [icon, name, value text, fraction (−1 = no bar), bar colour]
func tile_rows(sim: Simulation, t: Vector2i) -> Array:
	var ws := sim.world
	var i := ws.index(t.x, t.y)
	var rows := []
	var sw := ws.surface_water[i]
	if ws.structure[i] != WorldState.Structure.NONE and ws.structure[i] != WorldState.Structure.DAM \
			and (sw >= 0.2 or ws.tick - ws.flood_tick[i] < 6):
		rows.append(["waves", "Flood water", "%d cm" % roundi(sw * 100.0), clampf(sw / Simulation.FLOOD_DEPTH, 0.0, 1.0), UiKit.CORAL])
	match ws.structure[i]:
		WorldState.Structure.SETTLEMENT:
			var cap := ws.housing_capacity()
			rows.append(["users", "Villagers", "%d/%d" % [ws.villagers, cap], float(ws.villagers) / maxf(1.0, cap), UiKit.TEAL])
			rows.append(["wheat", "Fed", "%d%%" % roundi(ws.food_ema * 100.0), ws.food_ema, UiKit.AMBER])
			rows.append(["droplet", "Water", "%d%%" % roundi(ws.water_ema * 100.0), ws.water_ema, UiKit.SKY])
			rows.append(["beef", "Food stored", "%d" % roundi(ws.food_store), -1.0])
			rows.append(["fish", "Fish", "%d" % roundi(ws.fish), -1.0])
			_flood_row(sim, i, rows)
			rows.append(["sprout", "Farms · harvests", "%d · %d" % [ws.count_structures(WorldState.Structure.FARM), ws.harvests], -1.0])
			return rows
		WorldState.Structure.FARM:
			_flood_row(sim, i, rows)
			rows.append(["wheat", "Crop growth", "%d%%" % roundi(ws.crop_growth[i] * 100.0), ws.crop_growth[i], UiKit.AMBER])
			rows.append(["droplet", "Soil moisture", "%d%%" % roundi(ws.soil_moisture[i] * 100.0), ws.soil_moisture[i],
				UiKit.CORAL if ws.crop_stress[i] > 0 else UiKit.SKY])
			rows.append(["mountain", "Soil depth", "%d%%" % roundi(ws.soil_depth[i] * 100.0), ws.soil_depth[i], Color("9a7650")])
			if ws.crop_stress[i] > 0:
				rows.append(["triangle-alert", "Too dry for", "%d days" % ws.crop_stress[i], -1.0])
			return rows
		WorldState.Structure.DAM:
			rows.append(["waves", "Water held", "%d%%" % roundi(clampf(ws.reservoir[i], 0.0, 1.0) * 100.0), clampf(ws.reservoir[i], 0.0, 1.0), UiKit.SKY])
			if sim.dam_blocks_fish(t.x, t.y):
				rows.append(["fish", "River dam", "blocks fish", -1.0])
			else:
				rows.append(["fish", "Small stream", "fish pass", -1.0])
			return rows
	if LandType.is_water(ws.land_type[i]):
		var mud := clampf(ws.sediment[i] / 0.08, 0.0, 1.0)
		rows.append(["waves", "Mud in water", "%d%%" % roundi(mud * 100.0), mud, Color("9c7a52")])
		return rows
	rows.append(["droplet", "Soil moisture", "%d%%" % roundi(ws.soil_moisture[i] * 100.0), ws.soil_moisture[i], UiKit.SKY])
	rows.append(["leaf", "Plant cover", "%d%%" % roundi(ws.vegetation_cover[i] * 100.0), ws.vegetation_cover[i], UiKit.LEAF])
	rows.append(["mountain", "Topsoil", "%d%%" % roundi(ws.soil_depth[i] * 100.0), ws.soil_depth[i], Color("9a7650")])
	rows.append(["gauge", "Elevation", "%d m" % roundi(ws.elevation[i] * 120.0), ws.elevation[i], UiKit.INK_FAINT])
	_flood_row(sim, i, rows)
	if sw > 0.01 and str(rows[0][1]) != "Flood water":
		rows.append(["droplets", "Runoff", "%.0f mm" % (ws.surface_water[i] * 1000.0), -1.0])
	return rows


## "River level" row for floodplain tiles: how close the stream is to flooding this tile.
func _flood_row(sim: Simulation, i: int, rows: Array) -> void:
	var r := sim.floodplain[i] if i < sim.floodplain.size() else -1
	if r < 0:
		return
	var level := clampf(sim.river_stage(r) / sim.flood_stage_for(i), 0.0, 1.5)
	var label := "Floodplain" if sim.flood_risk(i) == 2 else "High bank"
	rows.append(["waves", label, "river %d%%" % roundi(level * 100.0), minf(level, 1.0),
		UiKit.CORAL if level >= 0.8 else UiKit.SKY])


## Inspector text (plain, for tests / accessibility).
func tile_text(sim: Simulation, t: Vector2i) -> String:
	var h := tile_header(sim, t)
	var lines := PackedStringArray([str(h[0])])
	for r in tile_rows(sim, t):
		lines.append("%s: %s" % [r[1], r[2]])
	return "\n".join(lines)


func _slide_in(c: Control) -> void:
	var off := Vector2(0, 40) if portrait else Vector2(40, 0)
	UiKit.appear(c, off, 0.22)
	AudioDirector.sfx("ui_open", 1.0, -6.0)


func _slide_out(c: Control) -> void:
	if reduce_motion or UiKit.reduce_motion or not c.is_inside_tree():
		c.visible = false
		relayout()
		return
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 0.0, 0.14)
	tw.tween_callback(func() -> void:
		c.visible = false
		c.modulate.a = 1.0
		relayout())


# ================================================================== toolbar

func _build_tool_bar() -> void:
	_toolbar = UiKit.card()
	root.add_child(_toolbar)
	var sb := (_toolbar.get_theme_stylebox("panel", "Card") as StyleBoxFlat).duplicate() as StyleBoxFlat
	sb.set_content_margin_all(8)
	_toolbar.add_theme_stylebox_override("panel", sb)
	_tool_scroll = ScrollContainer.new()
	_tool_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_toolbar.add_child(_tool_scroll)
	var row := UiKit.hbox(4)
	_tool_scroll.add_child(row)
	tool_bar_row = row
	var group := ButtonGroup.new()
	for t in TOOL_LABELS.size():
		var b := _tool_button(TOOL_LABELS[t], TOOL_ICONS[t], t)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t == Tool.INSPECT
		b.tooltip_text = TOOL_TIPS[t]
		var tt := t
		b.pressed.connect(func() -> void: select_tool(tt))
		b.toggled.connect(func(_on: bool) -> void: _style_tools())
		row.add_child(b)
		_tool_buttons.append(b)
	var sep := ColorRect.new()
	sep.color = UiKit.LINE
	sep.custom_minimum_size = Vector2(1, 56)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sep)
	overlay_button = _tool_button("Layers", "layers", -1)
	overlay_button.tooltip_text = "Map layers: moisture, plants, soil, water"
	overlay_button.pressed.connect(func() -> void: overlay_requested.emit())
	row.add_child(overlay_button)
	events_button = _tool_button("History", "history", -1)
	events_button.tooltip_text = "What happened, and why"
	events_button.pressed.connect(func() -> void:
		if events_panel.visible:
			hide_events()
		else:
			events_requested.emit())
	row.add_child(events_button)
	_tool_more = _tool_button("More", "chevron-right", -1)
	_tool_more.tooltip_text = "More tools"
	_tool_more.visible = false
	_tool_more.pressed.connect(func() -> void:
		_tool_page = (_tool_page + 1) % maxi(1, _tool_pages)
		AudioDirector.sfx("ui_click", 1.2, -6.0)
		relayout())
	row.add_child(_tool_more)
	_tool_sep = sep
	# portrait phones: Layers / History float in a small stack above the toolbar
	_side = UiKit.card()
	var ssb := sb.duplicate() as StyleBoxFlat
	ssb.set_content_margin_all(6)
	_side.add_theme_stylebox_override("panel", ssb)
	_side.add_child(UiKit.vbox(4))
	_side.visible = false
	root.add_child(_side)
	_style_tools()


## Fits the toolbar to `avail` px without scrolling: buttons narrow down to a compact width,
## and if even that does not fit, the tools split into pages behind a "More" button.
func _fit_tools(avail: float) -> void:
	var extra: Array = [] if overlay_button.get_parent() != tool_bar_row else [overlay_button, events_button]
	var n := _tool_buttons.size() + extra.size()
	var gap := 4.0
	var sep_w := 9.0 if not extra.is_empty() else 0.0
	var bw := clampf((avail - sep_w - gap * (n - 1)) / n, TOOL_MIN_W, TOOL_W)
	var fits := bw * n + gap * (n - 1) + sep_w <= avail + 0.5
	_tool_pages = 1
	if not fits:
		bw = TOOL_MIN_W
		var per := maxi(2, floori((avail - sep_w - (bw + gap) * (extra.size() + 1)) / (bw + gap)))
		_tool_per = per
		_tool_pages = ceili(float(_tool_buttons.size()) / per)
		_tool_page = mini(_tool_page, _tool_pages - 1)
		for k in _tool_buttons.size():
			_tool_buttons[k].visible = k / per == _tool_page
	else:
		_tool_page = 0
		for b in _tool_buttons:
			b.visible = true
	_tool_more.visible = _tool_pages > 1
	(_tool_more.get_child(0).get_child(1) as Label).text = "More" if _tool_page < _tool_pages - 1 else "Back"
	for b in _tool_buttons + extra + [_tool_more]:
		(b as Button).custom_minimum_size.x = bw
		var name := (b as Button).get_child(0).get_child(1) as Label
		name.add_theme_font_size_override("font_size", 14 if bw >= 68.0 else 12)


func tools_fit_without_scroll() -> bool:
	return tool_bar_row.get_combined_minimum_size().x <= _tool_scroll.custom_minimum_size.x + 1.0


func _tool_button(text: String, icon_name: String, t: int) -> Button:
	var b := UiKit.button("", Vector2(74, 78), "", "Tool")
	var col := UiKit.vbox(1)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(col)
	var ic := UiKit.icon(icon_name, 26, UiKit.INK)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var name := UiKit.label(text, 14)
	name.add_theme_font_override("font", UiKit.font(false, 600))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name)
	var cost := UiKit.label("", 0, "Badge")
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", 11)
	cost.visible = t > 0
	col.add_child(cost)
	if t >= 0:
		_tool_icon.append(ic)
		_tool_name.append(name)
		_tool_cost.append(cost)
	return b


func select_tool(t: int) -> void:
	tool = t
	if _tool_pages > 1 and t / _tool_per != _tool_page:
		_tool_page = t / _tool_per  # keyboard shortcut to a tool on another page: flip to it
		relayout()
	if t < _tool_buttons.size():
		_tool_buttons[t].set_pressed_no_signal(true)
	_style_tools()
	tool_selected.emit(t)


func _style_tools() -> void:
	for t in _tool_buttons.size():
		var on := _tool_buttons[t].button_pressed
		_tool_icon[t].self_modulate = Color.WHITE if on else UiKit.INK
		_tool_name[t].add_theme_color_override("font_color", Color.WHITE if on else UiKit.INK)
		_tool_cost[t].add_theme_color_override("font_color", Color(1, 1, 1, 0.85) if on else
			(UiKit.CORAL if _tool_cost[t].has_meta("short") and bool(_tool_cost[t].get_meta("short")) else UiKit.INK_SOFT))


## Cost badges ("3⚒ 2🪵" as "3 lab · 2 wood") and the unaffordable state.
func _update_costs(ws: WorldState) -> void:
	for t in range(1, _tool_buttons.size()):
		var c := Vector2.ZERO
		if _sim != null and _sim.world == ws:
			c = _sim.action_cost(TOOL_ACTIONS[t])
		else:
			var raw: Array = Simulation.ACTION_COST.get(TOOL_ACTIONS[t], [0.0, 0.0])
			c = Vector2(raw[0], raw[1]) * (0.5 if ws.relaxed else 1.0) * (0.0 if ws.free_build else 1.0)
		var txt := "free" if c == Vector2.ZERO else ("%s labor" % _num(c.x) if c.y <= 0.0 else "%s · %s wood" % [_num(c.x), _num(c.y)])
		var short := ws.labor + 1e-6 < c.x or ws.wood + 1e-6 < c.y
		_tool_cost[t].text = txt
		_tool_cost[t].set_meta("short", short)
		_tool_buttons[t].self_modulate = Color(1, 1, 1, 0.6) if short else Color.WHITE
	_style_tools()


func _num(v: float) -> String:
	return "%d" % roundi(v) if is_equal_approx(v, roundf(v)) else "%.1f" % v


# ================================================================== overlay legend

func _build_legend() -> void:
	_legend = UiKit.card()
	_legend.visible = false
	root.add_child(_legend)
	var col := UiKit.vbox(6)
	_legend.add_child(col)
	var head := UiKit.hbox(6)
	head.add_child(UiKit.icon("layers", 18, UiKit.TEAL))
	_legend_title = UiKit.label("Layer", 0, "Subheading")
	head.add_child(_legend_title)
	col.add_child(head)
	_legend_grad = TextureRect.new()
	_legend_grad.custom_minimum_size = Vector2(200, 14)
	_legend_grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_legend_grad.stretch_mode = TextureRect.STRETCH_SCALE
	col.add_child(_legend_grad)
	var lh := UiKit.hbox(0)
	lh.add_child(UiKit.label("Low", 0, "Caption"))
	lh.add_child(UiKit.spacer())
	lh.add_child(UiKit.label("High", 0, "Caption"))
	col.add_child(lh)


func set_overlay_name(n: String) -> void:
	set_overlay(maxi(0, WorldView.OVERLAY_NAMES.find(n)), false)


func set_overlay(o: int, colorblind: bool) -> void:
	_overlay_index = o
	var n: String = WorldView.OVERLAY_NAMES[o]
	(overlay_button.get_child(0).get_child(1) as Label).text = "Layers" if o == 0 else n
	if o == 0:
		_legend.visible = false
		return
	_legend_title.text = n
	var g := Gradient.new()
	if colorblind:
		g.set_color(0, WorldView.CB_LOW)
		g.set_color(1, WorldView.CB_HIGH)
	else:
		g.set_color(0, WorldView.OVERLAY_LOW)
		g.set_color(1, WorldView.OVERLAY_HIGH.get(o, UiKit.TEAL))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 128
	gt.height = 4
	_legend_grad.texture = gt
	var was := _legend.visible
	_legend.visible = true
	relayout()
	if not was:
		UiKit.appear(_legend, Vector2(0, 12))


func overlay_label() -> String:
	return WorldView.OVERLAY_NAMES[_overlay_index]


# ================================================================== history + why-chain

func _build_events_panel() -> void:
	events_panel = UiKit.card()
	events_panel.visible = false
	events_panel.clip_contents = true
	root.add_child(events_panel)
	var col := UiKit.vbox(10)
	events_panel.add_child(col)
	var head := UiKit.hbox(8)
	col.add_child(head)
	head.add_child(UiKit.icon_badge("history", UiKit.AMBER_SOFT, UiKit.AMBER.darkened(0.35), 38))
	var title := UiKit.label("History", 0, "Heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_minor_toggle = UiKit.button("Show soil loss", Vector2(0, 44), "mountain", "Segment")
	_minor_toggle.toggle_mode = true
	_minor_toggle.tooltip_text = "Also list the many small soil-erosion events (hidden by default)"
	_minor_toggle.toggled.connect(func(_on: bool) -> void:
		if _event_log != null:
			show_events(_event_log, _selected_event))
	head.add_child(_minor_toggle)
	var close := UiKit.icon_button("x", "Close")
	close.custom_minimum_size = Vector2(48, 48)
	close.pressed.connect(hide_events)
	head.add_child(close)
	# body: [list | why-chain] side by side on wide screens; on phones a master-detail
	# pair where tapping an event slides to its why-chain (with a Back button)
	var body := UiKit.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_hist_list_pane = UiKit.vbox(6)
	_hist_list_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hist_list_pane.size_flags_stretch_ratio = 1.0
	body.add_child(_hist_list_pane)
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hist_list_pane.add_child(list_scroll)
	_events_list = UiKit.vbox(2)
	_events_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_events_list.mouse_filter = Control.MOUSE_FILTER_PASS
	list_scroll.add_child(_events_list)
	_hist_detail_pane = UiKit.vbox(8)
	_hist_detail_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hist_detail_pane.size_flags_stretch_ratio = 1.15
	body.add_child(_hist_detail_pane)
	var why_head := UiKit.hbox(6)
	_hist_back = UiKit.button("All events", Vector2(0, 44), "chevron-left", "Ghost")
	_hist_back.pressed.connect(func() -> void: _set_hist_detail(false))
	why_head.add_child(_hist_back)
	_hist_why_icon = UiKit.icon("circle-help", 18, UiKit.TEAL)
	why_head.add_child(_hist_why_icon)
	why_head.add_child(UiKit.label("Why it happened", 0, "Subheading"))
	_hist_detail_pane.add_child(why_head)
	_chain_scroll = ScrollContainer.new()
	_chain_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chain_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hist_detail_pane.add_child(_chain_scroll)
	_chain = UiKit.vbox(0)
	_chain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chain_scroll.add_child(_chain)
	_apply_hist_mode()


## Two columns on wide screens; one pane at a time (list or why-chain) on narrow ones.
func _apply_hist_mode() -> void:
	_hist_back.visible = not _hist_two_col
	_hist_why_icon.visible = _hist_two_col
	_hist_list_pane.visible = _hist_two_col or not _hist_detail
	_hist_detail_pane.visible = _hist_two_col or _hist_detail


func _set_hist_detail(on: bool) -> void:
	var changed := on != _hist_detail
	_hist_detail = on
	_apply_hist_mode()
	if changed and not _hist_two_col and not UiKit.reduce_motion:
		var pane := _hist_detail_pane if on else _hist_list_pane
		pane.modulate.a = 0.0
		var tw := pane.create_tween()
		tw.tween_property(pane, "modulate:a", 1.0, 0.18)


func history_showing_detail() -> bool:
	return _hist_detail_pane.visible


## Fills the history list (newest first) and optionally selects one event.
func show_events(log_: EventLog, select_id: int = -1, limit: int = 60) -> void:
	_event_log = log_
	for c in _events_list.get_children():
		_events_list.remove_child(c)
		c.queue_free()
	var ids := PackedInt32Array()
	for id in log_.recent(EventLog.CAPACITY):
		if ids.size() >= limit:
			break
		if _minor_toggle.button_pressed or not (log_.type_of(id) in MINOR_TYPES) or id == select_id:
			ids.append(id)
	if ids.is_empty():
		var empty := UiKit.wrap_label("Nothing has happened yet. Events appear here as the island changes.", "Caption")
		_events_list.add_child(empty)
	for id in ids:
		_events_list.add_child(_event_row(log_, id))
	var was := events_panel.visible
	events_panel.visible = true
	if not was:
		relayout()
		UiKit.appear(events_panel, Vector2(-30, 0) if not portrait else Vector2(0, 30))
		AudioDirector.sfx("ui_open", 0.9, -4.0)
	if select_id >= 0:
		show_explanation(select_id)
	else:
		_selected_event = -1
		_set_chain_placeholder()
		_set_hist_detail(false)


func _event_row(log_: EventLog, id: int) -> Button:
	var t := log_.type_of(id)
	var kind := EventLog.kind_of_type(t)
	var b := UiKit.button("", Vector2(0, 52), "", "Ghost")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = true
	b.set_meta("event_id", id)
	var row := UiKit.hbox(10)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	b.add_child(row)
	var col: Color = KIND_COLORS[kind]
	if EventLog.is_bad(t):
		col = UiKit.CORAL
	row.add_child(UiKit.icon_badge(event_icon(t), Color(col, 0.16), col, 34))
	var day := UiKit.label("Day %d" % log_.tick_of(id), 0, "Badge")
	day.custom_minimum_size.x = 56
	row.add_child(day)
	var text := log_.describe(id)
	var colon := text.find(": ")
	var lab := UiKit.label(text.substr(colon + 2) if colon >= 0 else text, 16)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lab.clip_text = true
	row.add_child(lab)
	var eid := id
	b.pressed.connect(func() -> void: show_explanation(eid))
	return b


func _set_chain_placeholder() -> void:
	_explain_lines = PackedStringArray(["Tap an event to see why it happened."])
	for c in _chain.get_children():
		_chain.remove_child(c)
		c.queue_free()
	var p := UiKit.card("Inset")
	p.add_child(UiKit.wrap_label("Tap an event to trace its causes - every link is something the simulation actually recorded.", "Caption", maxf(120.0, _chain_width() - 30.0)))
	_chain.add_child(p)


func _chain_width() -> float:
	var w := events_panel.size.x - 40.0
	return w * 1.15 / 2.15 - 8.0 if _hist_two_col else w


func show_explanation(id: int) -> void:
	if _event_log == null:
		return
	_selected_event = id
	for b in _events_list.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(int(b.get_meta("event_id", -2)) == id)
	_explain_lines = _event_log.explain(id)
	_set_hist_detail(true)
	_chain_scroll.scroll_vertical = 0
	for c in _chain.get_children():
		_chain.remove_child(c)
		c.queue_free()
	var k := 0
	for line in _explain_lines:
		var depth := 0
		while line.begins_with("  "):
			line = line.substr(2)
			depth += 1
		var indent := 18.0 * maxf(0, depth - 1)
		if line.begins_with("(caused by ") or line.begins_with("No recorded") or line.begins_with("…"):
			var cap := UiKit.label(line.trim_prefix("(").trim_suffix(")"), 0, "Caption")
			var m := MarginContainer.new()
			m.add_theme_constant_override("margin_left", int(indent + 44))
			m.add_theme_constant_override("margin_top", 2)
			m.add_theme_constant_override("margin_bottom", 6)
			var r := UiKit.hbox(6)
			r.add_child(UiKit.icon("sparkles", 14, UiKit.INK_FAINT))
			r.add_child(cap)
			m.add_child(r)
			_chain.add_child(m)
			continue
		var is_cause := line.begins_with("because ")
		var text := line.trim_prefix("because ")
		if is_cause:
			var conn := MarginContainer.new()
			conn.add_theme_constant_override("margin_left", int(indent + 14))
			var cr := UiKit.hbox(6)
			cr.add_child(UiKit.icon("chevron-down", 18, UiKit.AMBER))
			cr.add_child(UiKit.label("because", 0, "Badge"))
			conn.add_child(cr)
			_chain.add_child(conn)
		var card := UiKit.card("InsetWarm" if k == 0 else "Inset")
		var cm := MarginContainer.new()
		cm.add_theme_constant_override("margin_left", int(indent))
		var crow := UiKit.hbox(10)
		var ev_type := _type_from_text(text)
		var kind := EventLog.kind_of_type(ev_type)
		var colr: Color = UiKit.CORAL if EventLog.is_bad(ev_type) else KIND_COLORS[kind]
		crow.add_child(UiKit.icon_badge(event_icon(ev_type), Color(colr, 0.16), colr, 32))
		var tl := UiKit.wrap_label(text, "", maxf(120.0, _chain_width() - indent - 70.0))
		tl.add_theme_font_size_override("font_size", 16 if k > 0 else 17)
		if k == 0:
			tl.add_theme_font_override("font", UiKit.font(false, 650))
		crow.add_child(tl)
		card.add_child(crow)
		cm.add_child(card)
		_chain.add_child(cm)
		if not UiKit.reduce_motion and is_inside_tree():
			cm.modulate.a = 0.0
			var tw := cm.create_tween()
			tw.tween_property(cm, "modulate:a", 1.0, 0.18).set_delay(0.04 * k)
		k += 1


func _type_from_text(text: String) -> int:
	var colon := text.find(": ")
	var rest := text.substr(colon + 2) if colon >= 0 else text
	var best := 0
	var best_len := 0
	for t in EventLog.TYPE_NAMES:
		var n: String = EventLog.TYPE_NAMES[t]
		if rest.begins_with(n) and n.length() > best_len:
			best = t
			best_len = n.length()
	return best


func explanation_text() -> String:
	return "\n".join(_explain_lines)


func hide_events() -> void:
	if events_panel.visible:
		AudioDirector.sfx("ui_close", 1.0, -6.0)
	events_panel.visible = false
	relayout()


# ================================================================== toasts

func _build_toasts() -> void:
	_toasts = UiKit.vbox(6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)


func toast(msg: String, seconds: float = 2.5, icon_name: String = "", bad: bool = false) -> void:
	_last_toast = msg
	if icon_name == "":
		icon_name = "triangle-alert" if bad else "info"
	var p := UiKit.card("Chip")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if bad:
		p.theme_type_variation = "ChipWarn"
	var row := UiKit.hbox(8)
	p.add_child(row)
	row.add_child(UiKit.icon(icon_name, 20, UiKit.CORAL if bad else UiKit.TEAL))
	var l := UiKit.label(msg, 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size.x = minf(l.get_theme_font("font").get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 4.0, 440.0)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	# fade only: the VBox owns the position, a position tween would fight its layout
	var tw := p.create_tween()
	if not UiKit.reduce_motion:
		p.modulate.a = 0.0
		tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)


func toast_text() -> String:
	return _last_toast


func _build_award() -> void:
	_award = UiKit.card("Award")
	_award.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_award.visible = false
	_award.set_meta("layout_owned", true)
	var row := UiKit.hbox(12)
	_award.add_child(row)
	_award_icon = UiKit.icon_badge("award", UiKit.AMBER_SOFT, UiKit.AMBER_DARK, 44)
	row.add_child(_award_icon)
	var col := UiKit.vbox(0)
	row.add_child(col)
	_award_sub = UiKit.label("", 14, "Caption")
	_award_sub.add_theme_color_override("font_color", UiKit.AMBER_DARK)
	col.add_child(_award_sub)
	_award_title = UiKit.label("", 0, "Subheading")
	col.add_child(_award_title)
	root.add_child(_award)


## Queues a celebratory banner (achievement, unlock, level up). Banners play one after another
## and wait while a full-screen menu hides the HUD.
func award(title: String, kind: String = "Achievement unlocked", icon_name: String = "award") -> void:
	_award_queue.append(PackedStringArray([title, kind, icon_name]))
	_next_award()


func award_pending() -> int:
	return _award_queue.size() + (1 if _award_busy else 0)


func _next_award() -> void:
	if _award_busy or _award_queue.is_empty() or not is_inside_tree():
		return
	if not visible:
		get_tree().create_timer(0.5).timeout.connect(_next_award)
		return
	_award_busy = true
	var a: PackedStringArray = _award_queue.pop_front()
	_award_title.text = a[0]
	_award_sub.text = a[1].to_upper()
	for c in _award_icon.get_children():
		_award_icon.remove_child(c)
		c.queue_free()
	_award_icon.add_child(UiKit.icon(a[2], 24, UiKit.AMBER_DARK))
	_last_toast = a[1] + ": " + a[0]
	_award.visible = true
	_award.reset_size()
	_place_award()
	var hold := 2.6
	var tw := _award.create_tween()
	if UiKit.reduce_motion:
		_award.modulate.a = 1.0
		tw.tween_interval(hold)
	else:
		_award.pivot_offset = _award.size * 0.5
		_award.modulate.a = 0.0
		_award.scale = Vector2(0.7, 0.7)
		tw.set_parallel(true)
		tw.tween_property(_award, "modulate:a", 1.0, 0.2)
		tw.tween_property(_award, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_interval(hold)
	tw.chain().tween_property(_award, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(func() -> void:
		_award.visible = false
		_award_busy = false
		_next_award())


func _place_award() -> void:
	if _award == null or not _award.visible:
		return
	var sz := root.size
	_award.reset_size()
	var y := sz.y * (0.30 if portrait else 0.22)
	_award.position = Vector2((sz.x - _award.size.x) * 0.5, y)


# ================================================================== popup

func _build_popup() -> void:
	_scrim = ColorRect.new()
	_scrim.color = UiKit.SCRIM
	_scrim.visible = false
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_scrim)
	popup = UiKit.card()
	popup.visible = false
	root.add_child(popup)
	var col := UiKit.vbox(14)
	popup.add_child(col)
	var head := UiKit.hbox(12)
	col.add_child(head)
	_popup_icon = UiKit.icon_badge("sparkles", UiKit.TEAL_SOFT, UiKit.TEAL_DARK, 46)
	head.add_child(_popup_icon)
	_popup_title = UiKit.label("", 0, "Heading")
	_popup_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_popup_title)
	_popup_body = UiKit.label("", 18)
	_popup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_body.add_theme_color_override("font_color", UiKit.INK.lightened(0.12))
	_popup_body.add_theme_constant_override("line_spacing", 4)
	col.add_child(_popup_body)
	var ok := UiKit.primary("Continue", "check", 180)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(dismiss_popup)
	col.add_child(ok)


## Shows a popup; if one is already open, this one is queued and appears after OK.
func show_popup(title: String, body: String, icon_name: String = "") -> void:
	if popup.visible:
		_popup_queue.append(PackedStringArray([title, body, icon_name]))
		return
	_popup_title.text = title
	_popup_body.text = body
	if icon_name == "":
		icon_name = "sparkles"
		if title.begins_with("Tutorial"):
			icon_name = "compass"
		elif title.begins_with("While you were away"):
			icon_name = "history"
	(_popup_icon.get_child(0) as TextureRect).texture = UiKit.icon_tex(icon_name)
	popup.visible = true
	_scrim.visible = true
	relayout()
	UiKit.appear(popup, Vector2(0, 24), 0.24)
	AudioDirector.sfx("notify", 1.0, -4.0)


func dismiss_popup() -> void:
	popup.visible = false
	_scrim.visible = false
	if not _popup_queue.is_empty():
		var next: PackedStringArray = _popup_queue.pop_front()
		show_popup(next[0], next[1], next[2] if next.size() > 2 else "")
	elif _coach_pending:
		_coach_pending = false
		start_coach()


func clear_popups() -> void:
	_popup_queue.clear()
	popup.visible = false
	_scrim.visible = false


func popup_text() -> String:
	return _popup_title.text + "\n" + _popup_body.text if popup.visible else ""


# ================================================================== coach marks

var _coach_pending := false


func _build_coach() -> void:
	_coach = Control.new()
	_coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach.visible = false
	root.add_child(_coach)
	_coach_ring = Panel.new()
	_coach_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := UiKit.box(Color(UiKit.AMBER, 0.08), 20, 0, UiKit.AMBER, 0, 4)
	_coach_ring.add_theme_stylebox_override("panel", ring)
	_coach.add_child(_coach_ring)
	_coach_card = UiKit.card()
	_coach_card.custom_minimum_size = Vector2(360, 0)
	_coach.add_child(_coach_card)
	var col := UiKit.vbox(10)
	_coach_card.add_child(col)
	var head := UiKit.hbox(8)
	head.add_child(UiKit.icon("compass", 20, UiKit.AMBER))
	_coach_step_label = UiKit.label("", 0, "Caption")
	_coach_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_coach_step_label)
	col.add_child(head)
	_coach_text = UiKit.wrap_label("", "", 320)
	_coach_text.add_theme_font_size_override("font_size", 17)
	col.add_child(_coach_text)
	var btns := UiKit.hbox(8)
	var skip := UiKit.ghost("Skip tips")
	skip.pressed.connect(end_coach)
	btns.add_child(skip)
	btns.add_child(UiKit.spacer())
	_coach_next = UiKit.primary("Next", "chevron-right")
	_coach_next.pressed.connect(func() -> void: _coach_go(_coach_i + 1))
	btns.add_child(_coach_next)
	col.add_child(btns)


## Coach marks open after the current popup (tutorial intro) is dismissed.
func queue_coach() -> void:
	if popup.visible:
		_coach_pending = true
	else:
		start_coach()


func start_coach() -> void:
	_coach_steps = [
		[func() -> Control: return _chips_flow, "These are your island's vital signs: villagers, food, water, fish, goats, labor and wood - and the heart meter is overall island health."],
		[func() -> Control: return _obj_card if _obj_card.visible else _day_card, "Your goals live here. Tick them all off before the deadline to win stars."],
		[func() -> Control: return _tool_buttons[Tool.BUILD_FARM], "Pick a tool, then tap the island. Farms must be near the village and cost labor and wood (shown under each tool)."],
		[func() -> Control: return _tool_buttons[Tool.INSPECT], "Inspect any tile to see its soil, water and plants."],
		[func() -> Control: return events_button, "Everything has a cause. Open History and tap an event to see the chain of why it happened."],
		[func() -> Control: return _speed_card, "Pause, play or fast-forward time here. Seasons bring rain, storms and dry spells."],
	]
	_coach.visible = true
	_coach_go(0)


func coach_active() -> bool:
	return _coach.visible


func _coach_go(i: int) -> void:
	if i >= _coach_steps.size():
		end_coach()
		return
	_coach_i = i
	_coach_text.text = _coach_steps[i][1]
	_coach_step_label.text = "Tip %d of %d" % [i + 1, _coach_steps.size()]
	_coach_next.text = "Got it" if i == _coach_steps.size() - 1 else "Next"
	_place_coach()
	call_deferred("_place_coach")
	UiKit.appear(_coach_card, Vector2(0, 10), 0.2)
	if not UiKit.reduce_motion and is_inside_tree():
		var tw := _coach_ring.create_tween().set_loops(3)
		tw.tween_property(_coach_ring, "modulate:a", 0.45, 0.45)
		tw.tween_property(_coach_ring, "modulate:a", 1.0, 0.45)


func _place_coach() -> void:
	if _coach_i < 0 or _coach_i >= _coach_steps.size():
		return
	var target: Control = (_coach_steps[_coach_i][0] as Callable).call()
	var r := Rect2(target.global_position / ui_scale, target.size * target.get_global_transform().get_scale() / ui_scale).grow(8)
	if target == _chips_flow:
		r.size.y = _chips_flow.get_combined_minimum_size().y + 16
	_coach_ring.position = r.position
	_coach_ring.size = r.size
	_coach_card.reset_size()
	var sz := root.size
	var cs := _coach_card.size
	var p := Vector2(r.get_center().x - cs.x * 0.5, r.end.y + 14)
	if p.y + cs.y > sz.y - 10:
		p.y = r.position.y - cs.y - 14
	p.x = clampf(p.x, 10, sz.x - cs.x - 10)
	p.y = clampf(p.y, 10, sz.y - cs.y - 10)
	_coach_card.position = p


func end_coach() -> void:
	_coach.visible = false
	_coach_i = -1
	coach_finished.emit()
