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
var menu_free_rect := Rect2()  ## viewport px left for the island beside the title menu
var _post_fit: Callable  ## layout step that needs the content inside the themed tree
# new-world form state
var _nw := {"seed": 0, "size": 1, "preset": 0, "relaxed": false, "free_build": false, "rare_events": false}
var _endless_seed := 0
var _prestige_armed := false
const MEDAL_COLORS := [Color("a39887"), Color("b87333"), Color("8f9aa6"), Color("e0a33a")]
const MODE_ICONS := {"daily": "calendar", "weekly": "calendar-days", "endless": "infinity"}


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
	_cancel_fade()
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
	if not visible or current == "":
		return
	current = ""  # logically closed at once (is_open() is false); the sheet then fades out
	_stack.clear()
	var c := _content
	_content = null
	if UiKit.reduce_motion or not is_inside_tree():
		visible = false
		if c != null:
			c.queue_free()
		closed.emit()
		return
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the game is usable while the sheet fades
	if c != null:
		_ignore_mouse(c)
	var t := Motion.tween(root, "fade")
	t.tween_property(root, "modulate:a", 0.0, Motion.FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		visible = false
		root.modulate.a = 1.0
		root.mouse_filter = Control.MOUSE_FILTER_STOP
		if c != null:
			c.queue_free())
	closed.emit()


func _cancel_fade() -> void:
	Motion.stop(root, "fade")
	root.modulate.a = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	for ch in root.get_children():
		if ch.has_meta("leaving"):
			ch.queue_free()


static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in n.get_children():
		_ignore_mouse(ch)


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
		var old := _content
		if animate and not UiKit.reduce_motion and is_inside_tree():
			# cross-fade: the old sheet fades out under the new one (input goes to the new one)
			old.set_meta("leaving", true)
			_ignore_mouse(old)
			Motion.disappear(old, Vector2.ZERO, Motion.FAST, func() -> void: old.queue_free())
		else:
			root.remove_child(old)
			old.queue_free()
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
		"modes": _content = _modes(sz)
		"journal": _content = _journal(sz)
		"codex": _content = _codex(sz)
		"help": _content = _help(sz)
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
	items.append(["Daily · Weekly · Endless", "calendar", func() -> void: open("modes"), false])
	items.append(["Challenges", "flame", func() -> void: open("challenges"), false])
	items.append(["New world", "globe", func() -> void: open("new_world"), false])
	items.append(["Load game", "folder-open", func() -> void: open("load"), false])
	items.append(["Journal", "book-open", func() -> void: open("journal"), false])
	var k := 0
	var bh := 54.0 if sz.y >= 700 else 48.0
	for it in items:
		var b := UiKit.button(it[0], Vector2(w, bh), it[1], "Primary" if it[3] else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(it[2])
		col.add_child(b)
		UiKit.appear(b, Vector2(-16, 0), 0.22, 0.05 * k + 0.1)
		k += 1
	# settings + help share the last row to keep the menu short on small landscape phones
	var last := UiKit.hbox(8)
	var sb := UiKit.button("Settings", Vector2(0, bh), "settings")
	sb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.pressed.connect(func() -> void: open("settings"))
	last.add_child(sb)
	var hb := UiKit.button("Help", Vector2(0, bh), "circle-help")
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hb.pressed.connect(func() -> void: open("help"))
	last.add_child(hb)
	col.add_child(last)
	UiKit.appear(last, Vector2(-16, 0), 0.22, 0.05 * k + 0.1)
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
	var s3 := UiKit.hbox(4)
	s3.add_child(UiKit.icon("sparkles", 18, pr.banner_color()))
	s3.add_child(UiKit.label("Level %d%s" % [pr.level(), I18n.t("  ·  P%d") % pr.prestige if pr.prestige > 0 else ""], 0, "Caption"))
	foot.add_child(s3)
	col.add_child(foot)
	var card: PanelContainer = null
	if portrait:
		card = UiKit.card()
		holder.remove_child(col)
		card.add_child(col)
		holder.add_child(card)
	# Quiet studio lockup beside the version line. Light type, because it sits on the sea.
	var credit := UiKit.vbox(1)
	var align := HORIZONTAL_ALIGNMENT_LEFT if portrait else HORIZONTAL_ALIGNMENT_RIGHT
	var credit_lines: Array = [
		["Developed by Faiz Nasir", Color(0.98, 0.96, 0.91, 0.94)],
		["FG Universal Empire", Color(0.98, 0.96, 0.91, 0.72)],
	]
	for row in credit_lines:
		var line := UiKit.label(row[0], 0, "Caption")
		line.horizontal_alignment = align
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_color_override("font_color", row[1])
		credit.add_child(line)
	var ver := UiKit.label(I18n.f("v%s · made with Godot", str(ProjectSettings.get_setting("application/config/version", "1.0"))), 0, "Caption")
	ver.horizontal_alignment = align
	ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ver.add_theme_color_override("font_color", Color(0.98, 0.96, 0.91, 0.55))
	credit.add_child(ver)
	holder.add_child(credit)
	_post_fit = func() -> void:
		if card != null:
			card.reset_size()
			card.position = Vector2((sz.x - card.size.x) * 0.5, sz.y - card.size.y - 28.0)
		else:
			col.reset_size()
			col.position = Vector2(64, (sz.y - col.size.y) * 0.5)
		credit.reset_size()
		credit.position = Vector2(16, 12) if portrait else Vector2(sz.x - credit.size.x - 22, sz.y - credit.size.y - 16)
		# the island floats in the open space beside / above the menu, clear of the credit
		var free := Rect2(Vector2(16, credit.position.y + credit.size.y + 8), Vector2(sz.x - 32, card.position.y - credit.size.y - 36)) if card != null \
			else Rect2(Vector2(col.position.x + col.size.x + 24, 24), Vector2(sz.x - col.position.x - col.size.x - 48, credit.position.y - 40))
		menu_free_rect = Rect2(free.position * ui_scale, free.size * ui_scale)
		if main.has_method("frame_menu_view"):
			main.frame_menu_view(menu_free_rect)
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
	tc.add_child(UiKit.label(I18n.f("Island %d" if d["kind"] == "campaign" else "Challenge %d", int(d["index"])), 0, "Caption"))
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
		labels.append(I18n.done("%s · %d" % [I18n.t(SIZE_LABELS[k]), ScenarioCatalog.SIZES[k]]) if not portrait else SIZE_LABELS[k])
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
	_row(s4, "zap", "Rare events & species", UiKit.toggle(bool(_nw["rare_events"]), func(v: bool) -> void: _nw["rare_events"] = v),
		"Locust swarms, algal blooms and king tides - and the wildlife that counters them.")
	var go := UiKit.primary("Create island", "sparkles")
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(func() -> void:
		main.start_sandbox({"seed": int(_nw["seed"]), "size": ScenarioCatalog.SIZES[int(_nw["size"])],
			"preset": int(_nw["preset"]), "relaxed": bool(_nw["relaxed"]), "free_build": bool(_nw["free_build"]),
			"rare_events": bool(_nw["rare_events"])}))
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
	var wide := _two_col(sz)
	var parts := _sheet(sz, "Settings", "settings", 1080.0 if wide else 680.0)
	var body: VBoxContainer = parts[2]
	var right := body
	if wide:
		# landscape: Sound + Play on the left, Display on the right, so nothing needs scrolling
		var cols := UiKit.hbox(16)
		body.add_child(cols)
		body = UiKit.vbox(12)
		right = UiKit.vbox(12)
		for v in [body, right]:
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.size_flags_stretch_ratio = 1.0
			cols.add_child(v)
	var st: GameSettings = main.settings
	var a := _section(body, "Sound", "volume-2")
	for it in [["master_volume", "Master", "volume-2"], ["music_volume", "Music", "sparkles"],
			["sfx_volume", "Effects", "mouse-pointer-click"], ["ambience_volume", "Sea & rain", "waves"]]:
		a.add_child(_slider_row(it[2], it[1], str(it[0]), float(st.get_value(it[0]))))
	var d := _section(right, "Display", "monitor-smartphone")
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
	var names := []
	for l in I18n.LANGUAGES:
		names.append(l[1])
	var lang := UiKit.segmented(names, maxi(0, I18n.codes().find(str(st.get_value("language")))),
		func(k: int) -> void: main.change_setting("language", I18n.LANGUAGES[k][0]))
	for b in lang.find_children("*", "Button", true, false):
		(b as Button).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # names stay in their own language
	_row(c, "languages", "Language", lang, "Switch any time; the game changes straight away.")
	return _fit_sheet(parts, sz)


## Landscape sheets wide enough for two columns of rows.
func _two_col(sz: Vector2) -> bool:
	return not portrait and sz.x >= 1000.0


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
		["How to play", "circle-help", func() -> void: open("help"), ""],
		["Show tips again", "compass", func() -> void: main.show_coach(), ""],
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
		paths.append([main.save_path, I18n.t("Autosave"), -1])
	for k in SaveSystem.SLOT_COUNT:
		paths.append([SaveSystem.slot_path(k), I18n.t("Slot %d") % (k + 1), k])
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
		c.add_child(UiKit.label(I18n.done(str(p[1]) + ("" if empty else " · " + I18n.t(str(info.get("title", "Island"))))), 17, "Subheading"))
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
	return I18n.t("Saved %04d-%02d-%02d %02d:%02d") % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


# ================================================================== results

func _results(sz: Vector2) -> Control:
	var won := bool(_data.get("won", false))
	var sim: Simulation = main.sim
	var sc := sim.scenario
	var scored := sc != null and sc.is_scored()
	var run: Dictionary = _data.get("run", {})
	var title := "Island saved!" if won else "The island needs you"
	if scored:
		title = "Expedition complete" if won else "The run is over"
	var parts := _sheet(sz, title, "medal" if scored else ("trophy" if won else "heart-pulse"), 620.0)
	var body: VBoxContainer = parts[2]
	(parts[4] as HBoxContainer).get_child(0).visible = false
	body.add_child(UiKit.label(sc.title() if sc != null else "", 0, "Caption"))
	if scored:
		body.add_child(_score_block(sc, run))
	elif won:
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
	reason.visible = not reason.text.begins_with("Final score")
	reason.add_theme_font_size_override("font_size", 19)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(reason)
	if not run.is_empty():
		body.add_child(_xp_line(run))
	if sc != null and won and not scored:
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
		tv.add_child(UiKit.label(I18n.f("Achievement: %s", I18n.t(str(info.get("title", "")))), 17, "Subheading"))
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
	var parts := _sheet(sz, "Journal", "book-open", 900.0)
	var body: VBoxContainer = parts[2]
	_add_journal_tabs(parts, 2, sz)
	var pr: Progress = main.progress
	body.add_child(UiKit.label(I18n.f("%d of %d earned", [pr.achievements.size(), Achievements.LIST.size()]), 0, "Caption"))
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


# ================================================================== daily / weekly / endless

func _medal_icon(m: int, size := 22.0) -> TextureRect:
	return UiKit.icon("medal" if m > 0 else "circle", size, MEDAL_COLORS[clampi(m, 0, 3)])


func _modes(sz: Vector2) -> Control:
	var parts := _sheet(sz, "Daily · Weekly · Endless", "calendar", 1040.0)
	var body: VBoxContainer = parts[2]
	var pr: Progress = main.progress
	body.add_child(UiKit.wrap_label("Seeded islands with rare events and mutators. Everyone gets the same Daily and Weekly island; "
		+ "score points, earn medals and beat your personal best.", "Caption"))
	if _endless_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_endless_seed = rng.randi_range(1, 99999)
	var grid := GridContainer.new()
	grid.columns = 1 if portrait or sz.x < 760 else (3 if sz.x >= 1000 else 2)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	var ids := [ScenarioCatalog.daily_id(), ScenarioCatalog.weekly_id(), ScenarioCatalog.endless_id(_endless_seed)]
	if pr.observe_date(Progress.date_key()):
		var warn := UiKit.wrap_label("Your device clock reads earlier than a day you already played. Islands follow your clock, "
			+ "but scores from them stay on this device.", "Caption")
		body.add_child(warn)
	var k := 0
	for id in ids:
		var c := _mode_card(ScenarioCatalog.get_def(id), pr)
		grid.add_child(c)
		UiKit.appear(c, Vector2(0, 14), 0.2, 0.05 * k)
		k += 1
	var tip := UiKit.card("InsetWarm")
	var th := UiKit.hbox(10)
	tip.add_child(th)
	th.add_child(UiKit.icon("info", 20, UiKit.AMBER_DARK))
	th.add_child(UiKit.wrap_label("Score counts days survived, island health, how much the village grew, harvests, wildlife and rare events weathered, "
		+ "minus villagers lost, times the mutator bonus.", "Caption"))
	th.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(tip)
	return _fit_sheet(parts, sz)


func _mode_card(d: Dictionary, pr: Progress) -> Control:
	var id := str(d["id"])
	var mode := str(d["kind"])
	var md := ContentDB.mode(mode)
	var unlocked := pr.is_unlocked(id)
	var card := UiKit.card("Inset")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(290, 0)
	var col := UiKit.vbox(8)
	card.add_child(col)
	var head := UiKit.hbox(10)
	head.add_child(UiKit.icon_badge(MODE_ICONS.get(mode, "map") if unlocked else "lock",
		UiKit.TEAL_SOFT if unlocked else Color(UiKit.INK, 0.08), UiKit.TEAL_DARK if unlocked else UiKit.INK_FAINT, 42))
	var tc := UiKit.vbox(0)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.add_child(UiKit.label(str(md.get("title", mode.capitalize())), 20, "Heading"))
	var sub := str(d["title"]).get_slice("·", 1).strip_edges()
	tc.add_child(UiKit.label(I18n.f("%s · %s island", [sub, I18n.t(IslandGenerator.PRESET_NAMES[int(d["preset"]) % 4])]), 0, "Caption"))
	head.add_child(tc)
	col.add_child(head)
	var blurb := UiKit.wrap_label(str(md.get("blurb", "")), "")
	blurb.add_theme_font_size_override("font_size", 15)
	blurb.add_theme_color_override("font_color", UiKit.INK_SOFT)
	col.add_child(blurb)
	var muts: Array = d.get("mutators", [])
	if not muts.is_empty():
		for mid in muts:
			var m := ContentDB.mutator(str(mid))
			var r := UiKit.hbox(8)
			r.add_child(UiKit.icon(str(m.get("icon", "sparkles")), 18, UiKit.AMBER_DARK))
			var ml := UiKit.wrap_label("%s - %s" % [m.get("title", mid), m.get("blurb", "")], "Caption")
			ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(ml)
			col.add_child(r)
		col.add_child(UiKit.label(I18n.f("Score bonus ×%.2f", float(d.get("score_mult", 1.0))), 0, "Caption"))
	elif d.has("census"):
		var cz: Array = d["census"]
		col.add_child(UiKit.wrap_label("Yearly census (every 120 days): at least %d villagers, +%d each year (up to %d)." % [int(cz[0]), int(cz[1]), int(cz[2])], "Caption"))
	var medals: Array = d.get("medals", [])
	var mr := UiKit.hbox(6)
	for k in medals.size():
		mr.add_child(_medal_icon(k + 1, 18))
		mr.add_child(UiKit.label(str(int(medals[k])), 0, "Caption"))
	col.add_child(mr)
	var foot := UiKit.hbox(8)
	var b := pr.best(id)
	if b.is_empty():
		foot.add_child(UiKit.label("Not played yet", 0, "Caption"))
	else:
		foot.add_child(_medal_icon(int(b.get("medal", 0)), 22))
		foot.add_child(UiKit.label(I18n.f("Best %d", int(b.get("score", 0))), 16, "Subheading"))
	foot.add_child(UiKit.spacer())
	if mode == "endless" and unlocked:
		var dice := UiKit.icon_button("dice-5", "Another island")
		dice.pressed.connect(func() -> void:
			_endless_seed = (_endless_seed * 48271 + 11) % 99991 + 1
			_build(current, false))
		foot.add_child(dice)
	if unlocked:
		var play := UiKit.primary("Play" if b.is_empty() else "Replay", "play")
		play.pressed.connect(func() -> void: main.start_scenario(id))
		foot.add_child(play)
	else:
		foot.add_child(UiKit.label("Win island 1 to unlock", 0, "Caption"))
		card.modulate = Color(1, 1, 1, 0.7)
	col.add_child(foot)
	return card


# ================================================================== journal: profile, codex, achievements

func _journal_tabs(sel: int) -> Control:
	var tabs := UiKit.segmented(["Profile", "Codex", "Achievements"] if not portrait else ["Profile", "Codex", "Awards"], sel,
		func(k: int) -> void:
			current = ["journal", "codex", "achievements"][k]
			_build(current, false), ["user", "book-open", "award"])
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return tabs


## Journal tabs: in landscape they ride in the sheet header beside the title (one row less to
## scroll); in portrait they head the body.
func _add_journal_tabs(parts: Array, sel: int, sz: Vector2) -> void:
	if _two_col(sz):
		(parts[4] as Control).add_child(_journal_tabs(sel))
	else:
		(parts[2] as Control).add_child(_journal_tabs(sel))


func _journal(sz: Vector2) -> Control:
	var parts := _sheet(sz, "Journal", "book-open", 900.0)
	var body: VBoxContainer = parts[2]
	_add_journal_tabs(parts, 0, sz)
	var pr: Progress = main.progress
	# level card
	var lc := UiKit.card("InsetTeal")
	var lh := UiKit.hbox(14)
	lc.add_child(lh)
	var lvl := UiKit.icon_badge("sparkles", pr.banner_color(), Color.WHITE, 56)
	lh.add_child(lvl)
	var lv := UiKit.vbox(4)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lt := I18n.t("Steward level %d") % pr.level()
	if pr.prestige > 0:
		lt += I18n.t("  ·  Prestige %d") % pr.prestige
	lv.add_child(UiKit.label(lt, 22, "Heading"))
	lv.add_child(UiKit.meter(pr.level_progress(), UiKit.TEAL, 10))
	var nxt := Progress.xp_for_level(pr.level() + 1)
	lv.add_child(UiKit.label(I18n.done(I18n.f("%d / %d XP to level %d", [pr.xp, nxt, pr.level() + 1]) +
		(I18n.t("  ·  +%d%% XP from prestige") % (10 * pr.prestige) if pr.prestige > 0 else "")), 0, "Caption"))
	lh.add_child(lv)
	body.add_child(lc)
	# stats
	var st := _section(body, "Record", "trophy")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 8)
	st.add_child(flow)
	for it in [["star-fill", UiKit.AMBER, I18n.t("%d stars") % pr.total_stars()], ["trophy", UiKit.TEAL, I18n.t("%d islands won") % pr.games_won],
			["medal", MEDAL_COLORS[3], I18n.t("%d medals") % pr.medal_count()],
			["bird", UiKit.SKY, I18n.t("%d/%d species") % [pr.species_count(), ContentDB.species().size()]],
			["zap", UiKit.CORAL, I18n.t("%d/%d rare events") % [pr.codex_events.size(), ContentDB.rare_events().size()]],
			["award", UiKit.TEAL, I18n.t("%d/%d achievements") % [pr.achievements.size(), Achievements.LIST.size()]]]:
		var h := UiKit.hbox(6)
		h.add_child(UiKit.icon(it[0], 20, it[1]))
		h.add_child(UiKit.label(it[2], 16))
		flow.add_child(h)
	# banners
	var bn := _section(body, "Village banner", "flag-triangle-right")
	bn.add_child(UiKit.wrap_label("The flag over your village. New colours unlock with levels, medals, wildlife and prestige.", "Caption"))
	var bf := HFlowContainer.new()
	bf.add_theme_constant_override("h_separation", 8)
	bf.add_theme_constant_override("v_separation", 8)
	bn.add_child(bf)
	for b in ContentDB.banners():
		bf.add_child(_banner_chip(b, pr))
	# prestige
	var ps: Container = _section(body, "Prestige", "rotate-ccw")
	var ps_text: Container = ps
	if _two_col(sz):  # landscape: the button sits beside its explanation
		var ph := UiKit.hbox(14)
		ps.add_child(ph)
		ps_text = UiKit.vbox(0)
		ps_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ph.add_child(ps_text)
		ps = ph
	ps_text.add_child(UiKit.wrap_label(I18n.f("At level %d you may start a new prestige: your level returns to 1, every later run earns 10%% more XP, and the Deep sea banner unlocks. Stars, medals, bests, codex and banners are kept.",
		int(ContentDB.mode("xp").get("prestige_level", 10))), "Caption"))
	var pb := UiKit.button("Tap again to confirm" if _prestige_armed else "Prestige now", Vector2(0, 54), "rotate-ccw",
		"Primary" if _prestige_armed else "")
	pb.size_flags_horizontal = Control.SIZE_SHRINK_END
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.disabled = not pr.can_prestige()
	pb.pressed.connect(func() -> void:
		if not _prestige_armed:
			_prestige_armed = true
		else:
			_prestige_armed = false
			main.prestige()
		_build(current, false))
	ps.add_child(pb)
	if not pr.can_prestige():
		_prestige_armed = false
	return _fit_sheet(parts, sz)


func _banner_chip(b: Dictionary, pr: Progress) -> Control:
	var have := pr.banner_unlocked(b)
	var sel := str(b["id"]) == pr.banner
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 56)
	btn.theme_type_variation = "Primary" if sel else ""
	btn.text = str(b["title"]) if have else _unlock_text(b.get("unlock", {}))
	btn.icon = UiKit.icon_tex("flag-triangle-right" if have else "lock")
	btn.add_theme_color_override("icon_normal_color", Color.html(str(b["color"])) if have and not sel else (Color.WHITE if sel else UiKit.INK_FAINT))
	btn.add_theme_color_override("icon_hover_color", Color.html(str(b["color"])) if have and not sel else (Color.WHITE if sel else UiKit.INK_FAINT))
	btn.expand_icon = false
	btn.disabled = not have
	btn.tooltip_text = I18n.t("%s banner") % b["title"]
	var id := str(b["id"])
	btn.pressed.connect(func() -> void:
		main.set_banner(id)
		AudioDirector.sfx("ui_click")
		_build(current, false))
	return btn


func _unlock_text(u: Dictionary) -> String:
	if u.has("level"):
		return I18n.t("Level %d") % int(u["level"])
	if u.has("medals"):
		return I18n.t("%d medals") % int(u["medals"])
	if u.has("prestige"):
		return I18n.t("Prestige %d") % int(u["prestige"])
	if u.has("species"):
		return I18n.t("%d species") % int(u["species"])
	return "Locked"


func _codex(sz: Vector2) -> Control:
	var parts := _sheet(sz, "Journal", "book-open", 900.0)
	var body: VBoxContainer = parts[2]
	_add_journal_tabs(parts, 1, sz)
	var pr: Progress = main.progress
	body.add_child(UiKit.wrap_label("Wildlife and rare events you have witnessed. They appear on Daily, Weekly and Endless islands, "
		+ "or in a New world with rare events turned on.", "Caption"))
	var cols := 1 if portrait or sz.x < 820 else 2
	var sp := _section(body, "Species", "bird")
	var g1 := GridContainer.new()
	g1.columns = cols
	g1.add_theme_constant_override("h_separation", 10)
	g1.add_theme_constant_override("v_separation", 10)
	sp.add_child(g1)
	for s in ContentDB.species():
		var seen := (pr.codex_species & int(s["bit"])) != 0
		g1.add_child(_codex_card(str(s["icon"]), str(s["title"]) if seen else "Undiscovered species", seen,
			[I18n.f("Needs: %s", I18n.t(str(s["needs"]))), str(s["effect"]) if seen else "Its effect is revealed once it settles on one of your islands."]))
	var ev := _section(body, "Rare events", "zap")
	var g2 := GridContainer.new()
	g2.columns = cols
	g2.add_theme_constant_override("h_separation", 10)
	g2.add_theme_constant_override("v_separation", 10)
	ev.add_child(g2)
	for r in ContentDB.rare_events():
		var seen := pr.codex_events.has(str(r["type"]))
		g2.add_child(_codex_card(str(r["icon"]), str(r["title"]) if seen else "Unknown event", seen,
			[str(r["text"]), I18n.f("Counter: %s", I18n.t(str(r["counter"])))] if seen else ["Not witnessed yet. Survive long enough on a seeded island to see it."]))
	return _fit_sheet(parts, sz)


func _codex_card(icon_name: String, title: String, seen: bool, lines: Array) -> Control:
	var c := UiKit.card("InsetTeal" if seen else "Inset")
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size.x = 260
	var h := UiKit.hbox(10)
	c.add_child(h)
	h.add_child(UiKit.icon_badge(icon_name if seen else "lock", UiKit.TEAL if seen else Color(UiKit.INK, 0.07),
		Color.WHITE if seen else UiKit.INK_FAINT, 42))
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.label(title, 17, "Subheading"))
	for l in lines:
		v.add_child(UiKit.wrap_label(str(l), "Caption"))
	h.add_child(v)
	return c


# ================================================================== help

const HELP := [
	["target", "The goal", "Keep the villagers fed and the island alive. Every island card shows its goals; the top bar tracks food, wood, labor and island health."],
	["hammer", "Tools", "Pick a tool in the bottom bar (Clear, Plant, Farm, House, Dam, Restore, Remove), then tap a tile. Farms feed people but wear out soil; forest holds slopes and water; dams store water but change the river; Restore heals bare land."],
	["cloud-rain", "Seasons", "Each tick is one day and a year is 120 days: Spring, Rainy season, Summer, Dry season. Heavy rain floods valleys; drought brings fire."],
	["layers", "Map layers", "The layers button colours the map by moisture, plants, soil, or water & mud. Colorblind-safe layers are in Settings."],
	["circle-help", "Why did that happen?", "Open the event log and tap \"Why did this happen?\" on an event to see its chain of causes, e.g. cleared forest → muddy water → fewer fish → hunger."],
	["bird", "Wildlife", "Bees, seabirds, tree frogs and wolves arrive when the island can support them, and each one helps: pollination, eggs, pest control and grazing control."],
	["zap", "Rare events", "Locust swarms, algal blooms and king tides strike seeded islands. Each has a counter: forest near farms, clear coasts and coastal forest belts."],
	["medal", "Medals and levels", "Daily, Weekly and Endless runs earn a score and a medal. Every run earns XP; levels unlock village banners, and prestige restarts levels for bonus XP."],
	["history", "Saving", "The game autosaves often and keeps simulating briefly while you are away, then shows what happened. Use the pause menu for manual slots."],
]


func _help(sz: Vector2) -> Control:
	var parts := _sheet(sz, "How to play", "circle-help", 760.0)
	var body: VBoxContainer = parts[2]
	for h in HELP:
		var c := UiKit.card("Inset")
		var r := UiKit.hbox(12)
		c.add_child(r)
		r.add_child(UiKit.icon_badge(str(h[0]), UiKit.TEAL_SOFT, UiKit.TEAL_DARK, 40))
		var v := UiKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UiKit.label(str(h[1]), 17, "Subheading"))
		v.add_child(UiKit.wrap_label(str(h[2]), "Caption"))
		r.add_child(v)
		body.add_child(c)
	var btns := HFlowContainer.new()
	btns.alignment = FlowContainer.ALIGNMENT_END
	btns.add_theme_constant_override("h_separation", 8)
	var coach := UiKit.button("Replay the tutorial", Vector2(0, 54), "compass")
	coach.pressed.connect(func() -> void: main.start_tutorial())
	btns.add_child(coach)
	body.add_child(btns)
	return _fit_sheet(parts, sz)



func _score_block(sc: Scenario, run: Dictionary) -> Control:
	var m := clampi(sc.stars, 0, 3)
	var box := UiKit.vbox(4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := _medal_icon(m, 72)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	if m > 0 and not UiKit.reduce_motion:
		ic.pivot_offset = Vector2(36, 36)
		ic.scale = Vector2.ZERO
		var tw := ic.create_tween()
		tw.tween_interval(0.3)
		tw.tween_callback(func() -> void: AudioDirector.sfx("star", 0.9 + 0.12 * m))
		tw.tween_property(ic, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var ml := UiKit.label(Scenario.MEDAL_NAMES[m].capitalize() + (" medal" if m > 0 else ""), 18, "Subheading")
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ml)
	var pts := UiKit.label(I18n.f("%d points", sc.final_score), 40, "Title")
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pts)
	var medals: Array = sc.def.get("medals", [])
	if m < medals.size():
		var nx := UiKit.label(I18n.f("%d more for %s", [int(medals[m]) - sc.final_score, I18n.t(Scenario.MEDAL_NAMES[m + 1])]), 0, "Caption")
		nx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(nx)
	if bool(run.get("new_best", false)):
		var nb := UiKit.hbox(6)
		nb.alignment = BoxContainer.ALIGNMENT_CENTER
		nb.add_child(UiKit.icon("sparkles", 18, UiKit.AMBER_DARK))
		nb.add_child(UiKit.label("New personal best!", 17, "Subheading"))
		box.add_child(nb)
		if not UiKit.reduce_motion:
			UiKit.pop(nb)
	return box


func _xp_line(run: Dictionary) -> Control:
	var pr: Progress = main.progress
	var c := UiKit.card("InsetTeal")
	var h := UiKit.hbox(10)
	c.add_child(h)
	h.add_child(UiKit.icon_badge("sparkles", pr.banner_color(), Color.WHITE, 40))
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := I18n.t("+%d XP") % int(run.get("xp", 0))
	if bool(run.get("level_up", false)):
		t = I18n.done(t + I18n.t("  ·  Level up! You are now level %d") % pr.level())
	v.add_child(UiKit.label(t, 17, "Subheading"))
	if bool(run.get("off_clock", false)):
		var oc := UiKit.label("Your device clock is earlier than a day you already played, so this score stays on this device.", 0, "Caption")
		oc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(oc)
	if bool(run.get("replay", false)):
		var why := UiKit.label("Replays earn XP only for beating your best on this island.", 0, "Caption")
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(why)
	v.add_child(UiKit.meter(pr.level_progress(), UiKit.TEAL, 8))
	h.add_child(v)
	return c
