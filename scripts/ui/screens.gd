class_name Screens
extends CanvasLayer
## Full-screen menus drawn over the live island: main menu, campaign & challenges,
## New World, settings, pause, save/load slots, results and achievements.
## Built in code from UiKit; talks to the composition root (`main`) through plain calls.

signal opened(screen_name: String)
signal closed

const PRESET_ICONS := ["leaf", "trees", "sun", "mountain"]
const SIZE_LABELS := ["Small", "Medium", "Large", "Huge"]
const UI_SCALES := [0.85, 1.0, 1.15, 1.3]

var main  ## composition root (untyped on purpose: duck-typed calls)
var root: Control
var current := ""
var ui_scale := 1.0
var portrait := false
var _stack: Array[String] = []
var _data := {}
var _backdrop: ColorRect
var _shade: TextureRect
var _content: Control
var _post_fit: Callable  ## layout step that needs the content inside the themed tree
# new-world form state
var _nw := {"seed": 0, "size": 1, "preset": 0, "relaxed": false, "free_build": false}


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.name = "ScreensRoot"
	root.theme = UiKit.make_theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.09, 0.13, 0.15, 0.35)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_backdrop)
	_shade = TextureRect.new()
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, Color(0.96, 0.93, 0.86, 0.92))
	g.set_color(1, Color(0.96, 0.93, 0.86, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	_shade.texture = gt
	root.add_child(_shade)
	visible = false
	get_viewport().size_changed.connect(_relayout)


func set_ui_scale(s: float) -> void:
	ui_scale = s
	if visible and current != "":
		_build(current)


func is_open() -> bool:
	return visible and current != ""


## Opens a screen. `push` keeps the previous one for Back.
func open(screen_name: String, data: Dictionary = {}, push := true) -> void:
	if push and current != "" and current != screen_name:
		_stack.append(current)
	_data = data
	current = screen_name
	visible = true
	_build(screen_name)
	opened.emit(screen_name)


func back() -> void:
	if _stack.is_empty():
		close()
		return
	var prev: String = _stack.pop_back()
	current = prev
	_build(prev)
	AudioDirector.sfx("ui_close")


func close() -> void:
	if not visible:
		return
	visible = false
	current = ""
	_stack.clear()
	if _content != null:
		_content.queue_free()
		_content = null
	closed.emit()


func _relayout() -> void:
	if visible and current != "":
		_build(current, false)


# ================================================================== frame

func _build(screen_name: String, animate := true) -> void:
	var sz := UiKit.fit_root(self, root, ui_scale)
	portrait = sz.x < sz.y
	_backdrop.size = sz
	_shade.size = sz
	_shade.visible = screen_name == "menu" and not portrait
	_backdrop.color = Color(0.09, 0.13, 0.15, 0.08 if screen_name == "menu" else 0.45)
	if _content != null:
		root.remove_child(_content)
		_content.queue_free()
	match screen_name:
		"menu": _content = _menu(sz)
		"campaign": _content = _campaign(sz, "campaign")
		"challenges": _content = _campaign(sz, "challenge")
		"new_world": _content = _new_world(sz)
		"settings": _content = _settings(sz)
		"pause": _content = _pause(sz)
		"load", "save": _content = _slots(sz, screen_name == "save")
		"results": _content = _results(sz)
		"achievements": _content = _achievements(sz)
		_: _content = Control.new()
	root.add_child(_content)
	if _post_fit.is_valid():
		_post_fit.call()
		_post_fit = Callable()
	if animate:
		UiKit.appear(_content, Vector2(0, 18) if screen_name != "menu" else Vector2(-24, 0), 0.26)


## Standard sheet: a centred card with header (back + title) and a scrolling body.
func _sheet(sz: Vector2, title: String, icon_name: String, max_w := 760.0) -> Array:
	var m := 16.0
	var w := minf(max_w, sz.x - 2 * m)
	var card := UiKit.card()
	card.custom_minimum_size = Vector2(w, 0)
	var col := UiKit.vbox(14)
	card.add_child(col)
	var head := UiKit.hbox(10)
	col.add_child(head)
	var back_btn := UiKit.icon_button("arrow-left", "Back")
	back_btn.pressed.connect(back)
	head.add_child(back_btn)
	head.add_child(UiKit.icon_badge(icon_name, UiKit.TEAL_SOFT, UiKit.TEAL_DARK, 44))
	var t := UiKit.label(title, 30 if not portrait else 26, "Title")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 0)
	col.add_child(scroll)
	var body := UiKit.vbox(12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size.x = w - 64.0
	scroll.add_child(body)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = sz
	holder.add_child(card)
	# sized after the body is filled (see _fit_sheet)
	return [holder, card, body, scroll, head]


func _fit_sheet(parts: Array, sz: Vector2) -> Control:
	_post_fit = func() -> void:
		_do_fit_sheet(parts, sz)
		# again after the first container sort, when wrapped labels know their width
		_do_fit_sheet.call_deferred(parts, sz)
	return parts[0]


func _do_fit_sheet(parts: Array, sz: Vector2) -> void:
	var holder: Control = parts[0]
	if not is_instance_valid(holder) or not holder.is_inside_tree():
		return
	var card: PanelContainer = parts[1]
	var body: VBoxContainer = parts[2]
	var scroll: ScrollContainer = parts[3]
	var head: Control = parts[4]
	var max_h := sz.y - 32.0
	var chrome := head.get_combined_minimum_size().y + 14.0 + 48.0
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, max_h - chrome)
	card.reset_size()
	card.position = ((sz - card.size) * 0.5).floor()
	holder.size = sz


func _section(body: VBoxContainer, title: String, icon_name: String) -> VBoxContainer:
	var h := UiKit.hbox(8)
	h.add_child(UiKit.icon(icon_name, 20, UiKit.TEAL))
	h.add_child(UiKit.label(title, 0, "Subheading"))
	body.add_child(h)
	var box := UiKit.card("Inset")
	body.add_child(box)
	var v := UiKit.vbox(10)
	box.add_child(v)
	return v


func _row(parent: Control, icon_name: String, text: String, ctrl: Control, caption := "") -> void:
	var r := UiKit.hbox(10)
	r.add_child(UiKit.icon(icon_name, 22, UiKit.INK_SOFT))
	var lc := UiKit.vbox(0)
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lc.add_child(UiKit.label(text, 17))
	if caption != "":
		lc.add_child(UiKit.wrap_label(caption, "Caption"))
	r.add_child(lc)
	if ctrl != null:
		r.add_child(ctrl)
	parent.add_child(r)


func _stars_row(n: int, size := 22.0) -> HBoxContainer:
	var h := UiKit.hbox(2)
	for k in 3:
		h.add_child(UiKit.icon("star-fill" if k < n else "star", size, UiKit.AMBER if k < n else UiKit.INK_FAINT))
	return h


# ================================================================== main menu

func _menu(sz: Vector2) -> Control:
	var holder := Control.new()
	holder.size = sz
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UiKit.vbox(10)
	holder.add_child(col)
	var w := 340.0 if not portrait else minf(420.0, sz.x - 48.0)
	col.custom_minimum_size = Vector2(w, 0)
	var brand := UiKit.hbox(10)
	brand.add_child(UiKit.icon_badge("leaf", UiKit.TEAL, Color.WHITE, 52))
	var bt := UiKit.vbox(-4)
	var title := UiKit.label("Keystone Isle", 52 if not portrait else 44, "Title")
	bt.add_child(title)
	bt.add_child(UiKit.label("a tiny eco sim", 18, "Caption"))
	brand.add_child(bt)
	col.add_child(brand)
	col.add_child(_gap(10))
	var items: Array = []
	if main.has_game():
		items.append(["Continue", "play", func() -> void: main.resume_game(), true])
	items.append(["Campaign", "map", func() -> void: open("campaign"), not main.has_game()])
	items.append(["Challenges", "flame", func() -> void: open("challenges"), false])
	items.append(["New world", "globe", func() -> void: open("new_world"), false])
	items.append(["Load game", "folder-open", func() -> void: open("load"), false])
	items.append(["Achievements", "award", func() -> void: open("achievements"), false])
	items.append(["Settings", "settings", func() -> void: open("settings"), false])
	var k := 0
	for it in items:
		var b := UiKit.button(it[0], Vector2(w, 54), it[1], "Primary" if it[3] else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(it[2])
		col.add_child(b)
		UiKit.appear(b, Vector2(-16, 0), 0.22, 0.05 * k + 0.1)
		k += 1
	col.add_child(_gap(6))
	var pr: Progress = main.progress
	var foot := UiKit.hbox(14)
	var s1 := UiKit.hbox(4)
	s1.add_child(UiKit.icon("star-fill", 18, UiKit.AMBER))
	s1.add_child(UiKit.label("%d stars" % pr.total_stars(), 0, "Caption"))
	foot.add_child(s1)
	var s2 := UiKit.hbox(4)
	s2.add_child(UiKit.icon("award", 18, UiKit.TEAL))
	s2.add_child(UiKit.label("%d/%d achievements" % [pr.achievements.size(), Achievements.LIST.size()], 0, "Caption"))
	foot.add_child(s2)
	col.add_child(foot)
	var card: PanelContainer = null
	if portrait:
		card = UiKit.card()
		holder.remove_child(col)
		card.add_child(col)
		holder.add_child(card)
	var ver := UiKit.label("v1.0 · made with Godot", 0, "Caption")
	ver.modulate.a = 0.7
	holder.add_child(ver)
	_post_fit = func() -> void:
		if card != null:
			card.reset_size()
			card.position = Vector2((sz.x - card.size.x) * 0.5, sz.y - card.size.y - 28.0)
		else:
			col.reset_size()
			col.position = Vector2(64, (sz.y - col.size.y) * 0.5)
		ver.reset_size()
		ver.position = Vector2(sz.x - ver.size.x - 20, sz.y - ver.size.y - 14) if not portrait else Vector2(16, 14)
	return holder


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ================================================================== campaign / challenges

func _campaign(sz: Vector2, kind: String) -> Control:
	var parts := _sheet(sz, "Campaign" if kind == "campaign" else "Challenges", "map" if kind == "campaign" else "flame", 980.0)
	var body: VBoxContainer = parts[2]
	var tabs := UiKit.segmented(["Campaign", "Challenges"], 0 if kind == "campaign" else 1, func(k: int) -> void:
		current = "campaign" if k == 0 else "challenges"
		_build(current, false), ["map", "flame"])
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(tabs)
	var pr: Progress = main.progress
	var intro := "Six islands, each teaching one way the island's life is connected." if kind == "campaign" \
		else "Harsh conditions for experienced stewards. Unlocked after island 2."
	body.add_child(UiKit.wrap_label(intro, "Caption"))
	var grid := GridContainer.new()
	grid.columns = 1 if portrait or sz.x < 760 else (3 if sz.x >= 1000 else 2)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	var defs: Array = ScenarioCatalog.CAMPAIGN if kind == "campaign" else ScenarioCatalog.CHALLENGES
	var k := 0
	for d in defs:
		var c := _scenario_card(d, pr)
		grid.add_child(c)
		UiKit.appear(c, Vector2(0, 14), 0.2, 0.04 * k)
		k += 1
	return _fit_sheet(parts, sz)


func _scenario_card(d: Dictionary, pr: Progress) -> Control:
	var unlocked := pr.is_unlocked(str(d["id"]))
	var best := pr.best_stars(str(d["id"]))
	var played := pr.stars.has(str(d["id"]))
	var card := UiKit.card("InsetTeal" if unlocked and best == 0 and not played else "Inset")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(280, 0)
	var col := UiKit.vbox(8)
	card.add_child(col)
	var head := UiKit.hbox(10)
	var badge := UiKit.icon_badge(PRESET_ICONS[int(d.get("preset", 0))] if unlocked else "lock",
		UiKit.TEAL_SOFT if unlocked else Color(UiKit.INK, 0.08), UiKit.TEAL_DARK if unlocked else UiKit.INK_FAINT, 42)
	head.add_child(badge)
	var tc := UiKit.vbox(0)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.add_child(UiKit.label(("Island %d" if d["kind"] == "campaign" else "Challenge %d") % int(d["index"]), 0, "Caption"))
	var t := UiKit.label(str(d["title"]), 20, "Heading")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tc.add_child(t)
	head.add_child(tc)
	col.add_child(head)
	var blurb := UiKit.wrap_label(str(d["blurb"]), "")
	blurb.add_theme_font_size_override("font_size", 15)
	blurb.add_theme_color_override("font_color", UiKit.INK_SOFT)
	blurb.custom_minimum_size.y = 42
	col.add_child(blurb)
	var foot := UiKit.hbox(8)
	foot.add_child(_stars_row(best, 20))
	foot.add_child(UiKit.spacer())
	if unlocked:
		var play := UiKit.primary("Play" if not played else "Replay", "play")
		var id := str(d["id"])
		play.pressed.connect(func() -> void: main.start_scenario(id))
		foot.add_child(play)
	else:
		foot.add_child(UiKit.label("Win the previous island", 0, "Caption"))
	col.add_child(foot)
	if not unlocked:
		card.modulate = Color(1, 1, 1, 0.7)
	return card


# ================================================================== new world

func _new_world(sz: Vector2) -> Control:
	if int(_nw["seed"]) == 0:
		_reroll()
	var parts := _sheet(sz, "New world", "globe", 680.0)
	var body: VBoxContainer = parts[2]
	body.add_child(UiKit.wrap_label("A free sandbox island: no goals, no deadline. Every seed makes a different island.", "Caption"))
	var s1 := _section(body, "Island seed", "dices")
	var sr := UiKit.hbox(8)
	var le := LineEdit.new()
	le.text = str(_nw["seed"])
	le.custom_minimum_size = Vector2(0, 52)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	le.text_changed.connect(func(tx: String) -> void: _nw["seed"] = maxi(1, int(tx)) if tx.is_valid_int() else _hash_seed(tx))
	sr.add_child(le)
	var dice := UiKit.icon_button("dice-5", "Random seed", "")
	dice.pressed.connect(func() -> void:
		_reroll()
		le.text = str(_nw["seed"]))
	sr.add_child(dice)
	s1.add_child(sr)
	var s2 := _section(body, "Size", "maximize")
	var labels := []
	for k in ScenarioCatalog.SIZES.size():
		labels.append("%s · %d" % [SIZE_LABELS[k], ScenarioCatalog.SIZES[k]] if not portrait else SIZE_LABELS[k])
	s2.add_child(UiKit.segmented(labels, int(_nw["size"]), func(k: int) -> void: _nw["size"] = k))
	var s3 := _section(body, "Biome", "palette")
	var blurb := UiKit.wrap_label(IslandGenerator.PRESET_BLURBS[int(_nw["preset"])], "Caption")
	s3.add_child(UiKit.segmented(IslandGenerator.PRESET_NAMES, int(_nw["preset"]), func(k: int) -> void:
		_nw["preset"] = k
		blurb.text = IslandGenerator.PRESET_BLURBS[k], [] if portrait else PRESET_ICONS))
	s3.add_child(blurb)
	var s4 := _section(body, "Rules", "sliders-horizontal")
	_row(s4, "heart-pulse", "Relaxed", UiKit.toggle(bool(_nw["relaxed"]), func(v: bool) -> void: _nw["relaxed"] = v),
		"Half costs; villagers never leave.")
	_row(s4, "hammer", "Free building", UiKit.toggle(bool(_nw["free_build"]), func(v: bool) -> void: _nw["free_build"] = v),
		"Tools cost no labor or wood.")
	var go := UiKit.primary("Create island", "sparkles")
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(func() -> void:
		main.start_sandbox({"seed": int(_nw["seed"]), "size": ScenarioCatalog.SIZES[int(_nw["size"])],
			"preset": int(_nw["preset"]), "relaxed": bool(_nw["relaxed"]), "free_build": bool(_nw["free_build"])}))
	body.add_child(go)
	return _fit_sheet(parts, sz)


func _reroll() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_nw["seed"] = rng.randi_range(1, 999999)


func _hash_seed(tx: String) -> int:
	return maxi(1, absi(hash(tx)) % 2147483646)


# ================================================================== settings

func _settings(sz: Vector2) -> Control:
	var parts := _sheet(sz, "Settings", "settings", 680.0)
	var body: VBoxContainer = parts[2]
	var st: GameSettings = main.settings
	var a := _section(body, "Sound", "volume-2")
	for it in [["master_volume", "Master", "volume-2"], ["music_volume", "Music", "sparkles"],
			["sfx_volume", "Effects", "mouse-pointer-click"], ["ambience_volume", "Sea & rain", "waves"]]:
		a.add_child(_slider_row(it[2], it[1], str(it[0]), float(st.get_value(it[0]))))
	var d := _section(body, "Display", "monitor-smartphone")
	var cur := UI_SCALES.find(_closest_scale(float(st.get_value("ui_scale"))))
	var scale_seg := UiKit.segmented(["S", "M", "L", "XL"], cur, func(k: int) -> void: main.change_setting("ui_scale", UI_SCALES[k]))
	scale_seg.custom_minimum_size.x = 220
	_row(d, "maximize", "Interface size", scale_seg)
	_row(d, "eye", "Colorblind-safe layers", UiKit.toggle(bool(st.get_value("colorblind")), func(v: bool) -> void: main.change_setting("colorblind", v)),
		"Map layers use a blue-orange scale.")
	_row(d, "wind", "Reduce motion", UiKit.toggle(bool(st.get_value("reduce_motion")), func(v: bool) -> void: main.change_setting("reduce_motion", v)),
		"Calmer water, no screen animations.")
	var c := _section(body, "Play", "hand")
	_row(c, "vibrate", "Haptics", UiKit.toggle(bool(st.get_value("haptics")), func(v: bool) -> void: main.change_setting("haptics", v)),
		"Small vibrations on phones and tablets.")
	_row(c, "compass", "Tutorial tips", UiKit.toggle(bool(st.get_value("show_tutorial")), func(v: bool) -> void: main.change_setting("show_tutorial", v)),
		"Show coach marks on the first island.")
	var lang := UiKit.segmented(["English"], 0, func(_k: int) -> void: pass)
	_row(c, "languages", "Language", lang, "More languages coming; all text is ready for translation.")
	return _fit_sheet(parts, sz)


func _closest_scale(v: float) -> float:
	var best: float = UI_SCALES[1]
	for s in UI_SCALES:
		if absf(float(s) - v) < absf(best - v):
			best = s
	return best


func _slider_row(icon_name: String, text: String, key: String, v: float) -> HBoxContainer:
	var r := UiKit.hbox(10)
	r.add_child(UiKit.icon(icon_name, 22, UiKit.INK_SOFT))
	var l := UiKit.label(text, 17)
	l.custom_minimum_size.x = 110
	r.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(120, 40)
	r.add_child(s)
	var val := UiKit.label("%d%%" % roundi(v * 100.0), 0, "Value")
	val.custom_minimum_size.x = 52
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(val)
	s.value_changed.connect(func(x: float) -> void:
		val.text = "%d%%" % roundi(x * 100.0)
		main.change_setting(key, x))
	s.drag_ended.connect(func(_c: bool) -> void: AudioDirector.sfx("ui_click"))
	return r


# ================================================================== pause

func _pause(sz: Vector2) -> Control:
	var parts := _sheet(sz, "Paused", "pause", 460.0)
	var body: VBoxContainer = parts[2]
	(parts[4] as HBoxContainer).get_child(0).visible = false
	var sim: Simulation = main.sim
	var info := UiKit.card("Inset")
	var ic := UiKit.hbox(10)
	info.add_child(ic)
	ic.add_child(UiKit.icon("map", 22, UiKit.TEAL))
	var t := UiKit.vbox(0)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_child(UiKit.label(sim.scenario.title() if sim.scenario != null else "Sandbox", 18, "Subheading"))
	t.add_child(UiKit.label("Day %d · seed %d · %d villagers" % [sim.world.tick, sim.world.world_seed, sim.world.villagers], 0, "Caption"))
	ic.add_child(t)
	body.add_child(info)
	var items := [
		["Resume", "play", func() -> void: main.resume_game(), "Primary"],
		["Save game", "save", func() -> void: open("save"), ""],
		["Load game", "folder-open", func() -> void: open("load"), ""],
		["Restart island", "rotate-ccw", func() -> void: main.restart_scenario(), ""],
		["Settings", "settings", func() -> void: open("settings"), ""],
		["How to play", "circle-help", func() -> void: main.show_coach(), ""],
		["Main menu", "log-out", func() -> void: main.open_menu(), "Ghost"],
	]
	for it in items:
		var b := UiKit.button(it[0], Vector2(0, 54), it[1], it[3])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(it[2])
		body.add_child(b)
	return _fit_sheet(parts, sz)


# ================================================================== save / load slots

func _slots(sz: Vector2, saving: bool) -> Control:
	var parts := _sheet(sz, "Save game" if saving else "Load game", "save" if saving else "folder-open", 640.0)
	var body: VBoxContainer = parts[2]
	var paths: Array = []
	if not saving:
		paths.append([main.save_path, "Autosave", -1])
	for k in SaveSystem.SLOT_COUNT:
		paths.append([SaveSystem.slot_path(k), "Slot %d" % (k + 1), k])
	for p in paths:
		var info := SaveSystem.slot_info(str(p[0]))
		var card := UiKit.card("Inset")
		var r := UiKit.hbox(12)
		card.add_child(r)
		var empty := info.is_empty()
		r.add_child(UiKit.icon_badge("history" if int(p[2]) < 0 else "save",
			UiKit.TEAL_SOFT if not empty else Color(UiKit.INK, 0.06), UiKit.TEAL_DARK if not empty else UiKit.INK_FAINT, 42))
		var c := UiKit.vbox(0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(UiKit.label(str(p[1]) + ("" if empty else " · " + str(info.get("title", "Island"))), 17, "Subheading"))
		if empty:
			c.add_child(UiKit.label("Empty", 0, "Caption"))
		else:
			c.add_child(UiKit.label("Day %d · %d villagers · health %d" % [int(info.get("day", 0)), int(info.get("villagers", 0)), int(info.get("keystone", 0))], 0, "Caption"))
			c.add_child(UiKit.label(_when(float(info.get("saved_at", 0.0))), 0, "Caption"))
		r.add_child(c)
		var slot := int(p[2])
		var path := str(p[0])
		if saving:
			var b := UiKit.primary("Overwrite" if not empty else "Save here", "save")
			b.pressed.connect(func() -> void:
				main.save_slot(slot)
				_build(current, false))
			r.add_child(b)
		elif not empty:
			var b := UiKit.primary("Load", "folder-open")
			b.pressed.connect(func() -> void: main.load_slot(path))
			r.add_child(b)
		if not empty and slot >= 0:
			var del := UiKit.icon_button("trash-2", "Delete this save")
			del.pressed.connect(func() -> void:
				SaveSystem.delete_all(path)
				_build(current, false))
			r.add_child(del)
		body.add_child(card)
	return _fit_sheet(parts, sz)


func _when(unix: float) -> String:
	if unix <= 0.0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(int(unix + Time.get_time_zone_from_system().get("bias", 0) * 60))
	return "Saved %04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


# ================================================================== results

func _results(sz: Vector2) -> Control:
	var won := bool(_data.get("won", false))
	var parts := _sheet(sz, "Island saved!" if won else "The island needs you", "trophy" if won else "heart-pulse", 620.0)
	var body: VBoxContainer = parts[2]
	(parts[4] as HBoxContainer).get_child(0).visible = false
	var sim: Simulation = main.sim
	var sc := sim.scenario
	body.add_child(UiKit.label(sc.title() if sc != null else "", 0, "Caption"))
	if won:
		var srow := UiKit.hbox(10)
		srow.alignment = BoxContainer.ALIGNMENT_CENTER
		var n := int(_data.get("stars", 1))
		for k in 3:
			var s := UiKit.icon("star-fill" if k < n else "star", 64, UiKit.AMBER if k < n else UiKit.INK_FAINT)
			srow.add_child(s)
			if k < n and not UiKit.reduce_motion:
				s.pivot_offset = Vector2(32, 32)
				s.scale = Vector2.ZERO
				var tw := s.create_tween()
				tw.tween_interval(0.25 + 0.3 * k)
				tw.tween_callback(func() -> void: AudioDirector.sfx("star", 1.0 + 0.12 * k))
				tw.tween_property(s, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		body.add_child(srow)
	var reason := UiKit.wrap_label(sc.reason if sc != null else "", "")
	reason.add_theme_font_size_override("font_size", 19)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(reason)
	if sc != null and won:
		var how := UiKit.card("Inset")
		var hv := UiKit.vbox(6)
		how.add_child(hv)
		hv.add_child(UiKit.label("Stars", 0, "Subheading"))
		hv.add_child(_check_line(true, "Every goal met"))
		for so in sc.def.get("stars", []):
			hv.add_child(_check_line(Scenario.met(so, sim.world, sc), Scenario.label(so)))
		if sim.world.relaxed:
			hv.add_child(UiKit.wrap_label("Relaxed mode: one star at most.", "Caption"))
		body.add_child(how)
	var chain: PackedStringArray = _data.get("chain", PackedStringArray())
	if not won and chain.size() > 0:
		var box := UiKit.card("InsetWarm")
		var v := UiKit.vbox(4)
		box.add_child(v)
		var hh := UiKit.hbox(6)
		hh.add_child(UiKit.icon("circle-help", 18, UiKit.AMBER.darkened(0.3)))
		hh.add_child(UiKit.label("What went wrong", 0, "Subheading"))
		v.add_child(hh)
		for line in chain:
			var l := UiKit.wrap_label(line.strip_edges(), "")
			l.add_theme_font_size_override("font_size", 15)
			var depth := (line.length() - line.lstrip(" ").length()) / 2
			var mc := MarginContainer.new()
			mc.add_theme_constant_override("margin_left", 14 * depth)
			mc.add_child(l)
			v.add_child(mc)
		body.add_child(box)
	var fresh: Array = _data.get("achievements", [])
	for id in fresh:
		var info := Achievements.get_info(str(id))
		var ar := UiKit.card("InsetTeal")
		var h := UiKit.hbox(10)
		ar.add_child(h)
		h.add_child(UiKit.icon_badge(str(info.get("icon", "award")), UiKit.TEAL, Color.WHITE, 40))
		var tv := UiKit.vbox(0)
		tv.add_child(UiKit.label("Achievement: " + str(info.get("title", "")), 17, "Subheading"))
		tv.add_child(UiKit.label(str(info.get("text", "")), 0, "Caption"))
		h.add_child(tv)
		body.add_child(ar)
	var btns := HFlowContainer.new()
	btns.alignment = FlowContainer.ALIGNMENT_END
	btns.add_theme_constant_override("h_separation", 8)
	btns.add_theme_constant_override("v_separation", 8)
	var menu_b := UiKit.ghost("Menu", "log-out")
	menu_b.pressed.connect(func() -> void: main.open_menu())
	btns.add_child(menu_b)
	var keep := UiKit.button("Keep playing", Vector2(0, 54), "play")
	keep.pressed.connect(func() -> void: main.keep_playing())
	btns.add_child(keep)
	var retry := UiKit.button("Try again", Vector2(0, 54), "rotate-ccw", "" if won else "Primary")
	retry.pressed.connect(func() -> void: main.restart_scenario())
	btns.add_child(retry)
	var nxt: String = main.next_scenario_id() if won else ""
	if nxt != "":
		var nb := UiKit.primary("Next island", "chevron-right")
		nb.pressed.connect(func() -> void: main.start_scenario(nxt))
		btns.add_child(nb)
	body.add_child(btns)
	return _fit_sheet(parts, sz)


func _check_line(ok: bool, text: String) -> HBoxContainer:
	var h := UiKit.hbox(8)
	h.add_child(UiKit.icon("circle-check" if ok else "circle", 20, UiKit.LEAF if ok else UiKit.INK_FAINT))
	h.add_child(UiKit.label(text, 16))
	return h


# ================================================================== achievements

func _achievements(sz: Vector2) -> Control:
	var parts := _sheet(sz, "Achievements", "award", 900.0)
	var body: VBoxContainer = parts[2]
	var pr: Progress = main.progress
	body.add_child(UiKit.label("%d of %d earned" % [pr.achievements.size(), Achievements.LIST.size()], 0, "Caption"))
	var grid := GridContainer.new()
	grid.columns = 1 if portrait else (3 if sz.x >= 980 else 2)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	for a in Achievements.LIST:
		var have := pr.achievements.has(a["id"])
		var c := UiKit.card("InsetTeal" if have else "Inset")
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size.x = 250
		var h := UiKit.hbox(10)
		c.add_child(h)
		h.add_child(UiKit.icon_badge(str(a["icon"]) if have else "lock", UiKit.TEAL if have else Color(UiKit.INK, 0.07),
			Color.WHITE if have else UiKit.INK_FAINT, 42))
		var v := UiKit.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UiKit.label(str(a["title"]), 17, "Subheading"))
		v.add_child(UiKit.wrap_label(str(a["text"]), "Caption"))
		h.add_child(v)
		grid.add_child(c)
	return _fit_sheet(parts, sz)
