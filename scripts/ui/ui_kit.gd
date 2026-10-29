class_name UiKit
extends RefCounted
## Design system for Keystone Isle: palette, the single shared Theme (fonts, buttons, cards,
## chips, sliders, scrollbars), icon helpers and small "juice" helpers (hover/press tweens,
## haptics, click sounds). Every screen and HUD widget is built from these pieces.

# ---------------------------------------------------------------- palette (cozy paper + teal)
const PAPER := Color(0.985, 0.968, 0.925, 0.95)
const PAPER_SOLID := Color(0.985, 0.968, 0.925)
const PAPER_DIM := Color(0.94, 0.915, 0.86)
const PAPER_DEEP := Color(0.90, 0.87, 0.80)
const INK := Color("2f2a24")
const INK_SOFT := Color("6e6357")
const INK_FAINT := Color("a39887")
const TEAL := Color("2f7d6d")
const TEAL_DARK := Color("235e52")
const TEAL_SOFT := Color("d7ebe4")
const AMBER := Color("e0a33a")
const AMBER_SOFT := Color("f7e6c4")
const CORAL := Color("d0603f")
const CORAL_SOFT := Color("f6dcd2")
const LEAF := Color("5f9e45")
const SKY := Color("4a8fb8")
const LINE := Color(0.18, 0.14, 0.10, 0.12)
const SHADOW := Color(0.10, 0.07, 0.04, 0.22)
const SCRIM := Color(0.08, 0.10, 0.12, 0.55)

const RADIUS := 18
const TOUCH := 56.0          ## minimum touch target in logical px (≥ 48 dp at UI scale 1)
const FONT_BODY := preload("res://assets/fonts/Inter.ttf")
const FONT_DISPLAY := preload("res://assets/fonts/Fraunces.ttf")
const ICON_DIR := "res://assets/icons/"

static var reduce_motion := false
static var haptics := true
static var _theme: Theme
static var _icons := {}
static var _fonts := {}


# ---------------------------------------------------------------- fonts
static func font(display: bool = false, weight: int = 400) -> Font:
	var key := "%s%d" % ["d" if display else "b", weight]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = FONT_DISPLAY if display else FONT_BODY
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_fonts[key] = fv
	return fv


# ---------------------------------------------------------------- style boxes
static func box(bg: Color, radius: int = RADIUS, margin: float = 14.0, border: Color = Color(0, 0, 0, 0),
		shadow: int = 0, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	sb.corner_detail = 10
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if shadow > 0:
		sb.shadow_color = SHADOW
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, shadow * 0.45)
	return sb


static func _button_styles(t: Theme, type: String, normal: Color, hover: Color, pressed: Color,
		fg: Color, fg_pressed: Color, border: Color = LINE, radius: int = 14, shadow: int = 3) -> void:
	t.set_stylebox("normal", type, box(normal, radius, 12, border, shadow))
	t.set_stylebox("hover", type, box(hover, radius, 12, border, shadow + 2))
	t.set_stylebox("pressed", type, box(pressed, radius, 12, border, 1))
	t.set_stylebox("hover_pressed", type, box(pressed.lightened(0.06), radius, 12, border, 2))
	t.set_stylebox("disabled", type, box(Color(normal, normal.a * 0.55), radius, 12, Color(border, border.a * 0.5), 0))
	t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), radius, 12, Color(TEAL, 0.7), 0, 2))
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg)
	t.set_color("font_pressed_color", type, fg_pressed)
	t.set_color("font_hover_pressed_color", type, fg_pressed)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_disabled_color", type, Color(fg, 0.4))
	t.set_color("icon_normal_color", type, fg)
	t.set_color("icon_hover_color", type, fg)
	t.set_color("icon_pressed_color", type, fg_pressed)
	t.set_color("icon_hover_pressed_color", type, fg_pressed)
	t.set_color("icon_focus_color", type, fg)
	t.set_color("icon_disabled_color", type, Color(fg, 0.35))


## The one Theme every UI root uses.
static func make_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(false, 450)
	t.default_font_size = 20
	# Button (secondary): paper chip with hairline border
	t.set_type_variation("Primary", "Button")
	t.set_type_variation("Ghost", "Button")
	t.set_type_variation("Tool", "Button")
	t.set_type_variation("Segment", "Button")
	t.set_type_variation("Danger", "Button")
	_button_styles(t, "Button", Color(1, 0.992, 0.97), Color(1, 1, 1), TEAL_SOFT, INK, TEAL_DARK)
	_button_styles(t, "Primary", TEAL, TEAL.lightened(0.08), TEAL_DARK, Color.WHITE, Color.WHITE, Color(0, 0, 0, 0))
	_button_styles(t, "Danger", CORAL, CORAL.lightened(0.08), CORAL.darkened(0.15), Color.WHITE, Color.WHITE, Color(0, 0, 0, 0))
	_button_styles(t, "Ghost", Color(0, 0, 0, 0), Color(INK, 0.06), Color(TEAL, 0.14), INK, TEAL_DARK, Color(0, 0, 0, 0), 14, 0)
	_button_styles(t, "Tool", Color(0, 0, 0, 0), Color(INK, 0.06), TEAL, INK, Color.WHITE, Color(0, 0, 0, 0), 16, 0)
	_button_styles(t, "Segment", Color(0, 0, 0, 0), Color(INK, 0.06), TEAL, INK_SOFT, Color.WHITE, Color(0, 0, 0, 0), 12, 0)
	for v in ["Button", "Primary", "Danger", "Ghost", "Tool", "Segment"]:
		t.set_constant("h_separation", v, 8)
		t.set_constant("icon_max_width", v, 26)
	t.set_constant("icon_max_width", "Tool", 30)
	t.set_font("font", "Primary", font(false, 650))
	t.set_font("font", "Button", font(false, 560))
	t.set_font("font", "Danger", font(false, 600))
	t.set_font("font", "Tool", font(false, 560))
	t.set_font_size("font_size", "Tool", 15)
	t.set_font("font", "Segment", font(false, 600))
	t.set_font_size("font_size", "Segment", 17)
	# Labels
	t.set_color("font_color", "Label", INK)
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", font(true, 700))
	t.set_font_size("font_size", "Title", 44)
	t.set_type_variation("Heading", "Label")
	t.set_font("font", "Heading", font(true, 650))
	t.set_font_size("font_size", "Heading", 26)
	t.set_type_variation("Subheading", "Label")
	t.set_font("font", "Subheading", font(false, 650))
	t.set_font_size("font_size", "Subheading", 18)
	t.set_type_variation("Caption", "Label")
	t.set_color("font_color", "Caption", INK_SOFT)
	t.set_font_size("font_size", "Caption", 15)
	t.set_type_variation("Value", "Label")
	t.set_font("font", "Value", font(false, 700))
	t.set_font_size("font_size", "Value", 18)
	t.set_type_variation("Badge", "Label")
	t.set_font("font", "Badge", font(false, 700))
	t.set_font_size("font_size", "Badge", 12)
	t.set_color("font_color", "Badge", INK_SOFT)
	# RichTextLabel
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("normal_font", "RichTextLabel", font(false, 450))
	t.set_font("bold_font", "RichTextLabel", font(false, 700))
	t.set_font_size("normal_font_size", "RichTextLabel", 18)
	t.set_font_size("bold_font_size", "RichTextLabel", 18)
	# Panels: Card (frosted paper), Chip (pill), Sheet (solid), Inset (recessed)
	t.set_stylebox("panel", "PanelContainer", box(PAPER, RADIUS, 16, Color(1, 1, 1, 0.6), 10))
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(PAPER, RADIUS, 16, Color(1, 1, 1, 0.7), 12))
	t.set_type_variation("Chip", "PanelContainer")
	var chip := box(PAPER, 999, 8, Color(1, 1, 1, 0.7), 6)
	chip.content_margin_left = 12
	chip.content_margin_right = 14
	t.set_stylebox("panel", "Chip", chip)
	t.set_type_variation("ChipWarn", "PanelContainer")
	var chipw := chip.duplicate() as StyleBoxFlat
	chipw.bg_color = CORAL_SOFT
	chipw.border_color = Color(CORAL, 0.6)
	t.set_stylebox("panel", "ChipWarn", chipw)
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", box(Color(INK, 0.05), 14, 12))
	t.set_type_variation("InsetWarm", "PanelContainer")
	t.set_stylebox("panel", "InsetWarm", box(AMBER_SOFT, 14, 12, Color(AMBER, 0.45)))
	t.set_type_variation("InsetTeal", "PanelContainer")
	t.set_stylebox("panel", "InsetTeal", box(TEAL_SOFT, 14, 12, Color(TEAL, 0.35)))
	t.set_type_variation("Segmented", "PanelContainer")
	t.set_stylebox("panel", "Segmented", box(Color(INK, 0.06), 14, 4))
	t.set_type_variation("Bare", "PanelContainer")
	t.set_stylebox("panel", "Bare", StyleBoxEmpty.new())
	# ProgressBar (meters)
	t.set_stylebox("background", "ProgressBar", box(Color(INK, 0.09), 999, 0))
	t.set_stylebox("fill", "ProgressBar", box(TEAL, 999, 0))
	t.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))
	t.set_font_size("font_size", "ProgressBar", 1)
	# Sliders
	var track := box(Color(INK, 0.12), 999, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(TEAL, 999, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _knob_texture()
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	# LineEdit
	t.set_stylebox("normal", "LineEdit", box(Color(1, 1, 1, 0.9), 14, 12, LINE))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), 14, 12, TEAL, 0, 2))
	t.set_stylebox("read_only", "LineEdit", box(PAPER_DIM, 14, 12, LINE))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", TEAL)
	t.set_color("selection_color", "LineEdit", Color(TEAL, 0.3))
	t.set_color("font_placeholder_color", "LineEdit", INK_FAINT)
	t.set_font_size("font_size", "LineEdit", 20)
	# Scrollbars: slim, rounded, unobtrusive
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, box(Color(0, 0, 0, 0), 999, 3))
		t.set_stylebox("grabber", sb_type, box(Color(INK, 0.22), 999, 3))
		t.set_stylebox("grabber_highlight", sb_type, box(Color(INK, 0.35), 999, 3))
		t.set_stylebox("grabber_pressed", sb_type, box(Color(TEAL, 0.6), 999, 3))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("separator", "HSeparator", box(LINE, 0, 0))
	t.set_constant("separation", "HSeparator", 1)
	# Tooltips
	t.set_stylebox("panel", "TooltipPanel", box(Color(INK, 0.94), 10, 10))
	t.set_color("font_color", "TooltipLabel", Color(1, 0.97, 0.92))
	t.set_font_size("font_size", "TooltipLabel", 16)
	_theme = t
	return t


static func _knob_texture() -> Texture2D:
	var s := 28
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5 - Vector2(0.5, 0.5)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c)
			var a := clampf(12.5 - d, 0.0, 1.0)
			var ring := clampf(d - 9.0, 0.0, 1.0)
			var col := Color.WHITE.lerp(TEAL, ring)
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- icons
static func icon_tex(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var path := ICON_DIR + name + ".svg"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icons[name] = tex
	return tex


static func icon(name: String, size: float = 22.0, tint: Color = INK) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon_tex(name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.self_modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## Round coloured "badge" with an icon inside (used for headers, achievements, list rows).
static func icon_badge(name: String, bg: Color = TEAL_SOFT, fg: Color = TEAL_DARK, size: float = 40.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, 999, size * 0.22))
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(icon(name, size * 0.56, fg))
	return p


# ---------------------------------------------------------------- widgets
static func button(text: String, min_size: Vector2 = Vector2(0, TOUCH), icon_name: String = "",
		variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(maxf(min_size.x, TOUCH), maxf(min_size.y, TOUCH))
	b.focus_mode = Control.FOCUS_NONE
	if icon_name != "":
		b.icon = icon_tex(icon_name)
	if variation != "":
		b.theme_type_variation = variation
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	juice(b)
	b.pressed.connect(func() -> void:
		haptic(12)
		AudioDirector.sfx("ui_click"))
	return b


static func primary(text: String, icon_name: String = "", min_w: float = 0.0) -> Button:
	return button(text, Vector2(min_w, TOUCH), icon_name, "Primary")


static func ghost(text: String, icon_name: String = "", min_w: float = 0.0) -> Button:
	return button(text, Vector2(min_w, TOUCH), icon_name, "Ghost")


static func icon_button(icon_name: String, tip: String = "", variation: String = "Ghost") -> Button:
	var b := button("", Vector2(TOUCH, TOUCH), icon_name, variation)
	b.tooltip_text = tip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


static func label(text: String = "", size: int = 0, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func wrap_label(text: String, variation: String = "", min_w: float = 0.0) -> Label:
	var l := label(text, 0, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = min_w
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func panel(alpha: float = 0.95, variation: String = "Card") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	if alpha < 0.95:
		p.self_modulate = Color(1, 1, 1, clampf(alpha / 0.95, 0.0, 1.0))
	return p


static func card(variation: String = "Card") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func spacer(horizontal: bool = true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func meter(value: float, color: Color = TEAL, height: float = 8.0, width: float = 0.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = clampf(value, 0.0, 1.0)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(width, height)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_meter_color(p, color)
	return p


static func set_meter_color(p: ProgressBar, color: Color) -> void:
	p.add_theme_stylebox_override("fill", box(color, 999, 0))


## Segmented control. Returns the container; buttons are its children (toggle, grouped).
static func segmented(labels: Array, selected: int, on_pick: Callable, icons: Array = []) -> PanelContainer:
	var p := card("Segmented")
	var row := hbox(4)
	p.add_child(row)
	var group := ButtonGroup.new()
	for k in labels.size():
		var b := button(str(labels[k]), Vector2(0, 48), str(icons[k]) if k < icons.size() else "", "Segment")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == selected
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kk := k
		b.pressed.connect(func() -> void: on_pick.call(kk))
		row.add_child(b)
	return p


## On/off pill switch (no stock CheckButton art).
static func toggle(on: bool, on_change: Callable) -> Button:
	var b := button("On" if on else "Off", Vector2(96, 48), "check" if on else "minus", "Segment")
	b.toggle_mode = true
	b.button_pressed = on
	b.add_theme_stylebox_override("normal", box(Color(INK, 0.08), 999, 10))
	b.add_theme_stylebox_override("hover", box(Color(INK, 0.12), 999, 10))
	b.add_theme_stylebox_override("pressed", box(TEAL, 999, 10))
	b.add_theme_stylebox_override("hover_pressed", box(TEAL.lightened(0.08), 999, 10))
	b.toggled.connect(func(v: bool) -> void:
		b.text = "On" if v else "Off"
		b.icon = icon_tex("check" if v else "minus")
		on_change.call(v))
	return b


# ---------------------------------------------------------------- juice
## Hover lift + press squash on any Control (skipped with reduce motion).
static func juice(c: Control) -> void:
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	c.mouse_entered.connect(func() -> void: _scale_to(c, 1.035, 0.12))
	c.mouse_exited.connect(func() -> void: _scale_to(c, 1.0, 0.16))
	if c is BaseButton:
		var b := c as BaseButton
		b.button_down.connect(func() -> void: _scale_to(c, 0.95, 0.06))
		b.button_up.connect(func() -> void: _scale_to(c, 1.0, 0.18))


static func _scale_to(c: Control, s: float, d: float) -> void:
	if reduce_motion or not c.is_inside_tree():
		c.scale = Vector2.ONE
		return
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(s, s), d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fade/slide a control in. `from` is a pixel offset it slides from.
static func appear(c: Control, from: Vector2 = Vector2(0, 16), d: float = 0.22, delay: float = 0.0) -> void:
	c.visible = true
	if reduce_motion or not c.is_inside_tree():
		c.modulate.a = 1.0
		return
	c.modulate.a = 0.0
	if c.get_parent() is Container or c.has_meta("layout_owned"):
		# someone else owns this node's position (a Container or a layout pass that may run
		# after us), so animate only opacity and a gentle scale – never fight the layout.
		var tws := c.create_tween().set_parallel(true)
		tws.tween_callback(func() -> void:
			c.pivot_offset = c.size * 0.5
			c.scale = Vector2(0.96, 0.96)).set_delay(delay)
		tws.tween_property(c, "modulate:a", 1.0, d).set_delay(delay)
		tws.tween_property(c, "scale", Vector2.ONE, d + 0.06).from(Vector2(0.96, 0.96)).set_delay(delay) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return
	var target := c.position
	c.position = target + from
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, d).set_delay(delay)
	tw.tween_property(c, "position", target, d + 0.06).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func pop(c: Control, d: float = 0.35) -> void:
	if reduce_motion or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.6, 0.6)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func haptic(ms: int = 15) -> void:
	if haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ---------------------------------------------------------------- layout helpers
## Insets (left, top, right, bottom) of the OS safe area in the viewport's logical pixels.
static func safe_insets(vp: Viewport) -> Vector4:
	if DisplayServer.get_name() == "headless" or not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0:
		return Vector4.ZERO
	var scr_pos := DisplayServer.window_get_position()
	var vs := vp.get_visible_rect().size
	var kx := vs.x / float(win.x)
	var ky := vs.y / float(win.y)
	var l := maxf(0.0, safe.position.x - scr_pos.x) * kx
	var t := maxf(0.0, safe.position.y - scr_pos.y) * ky
	var r := maxf(0.0, (scr_pos.x + win.x) - safe.end.x) * kx
	var b := maxf(0.0, (scr_pos.y + win.y) - safe.end.y) * ky
	return Vector4(minf(l, 80), minf(t, 80), minf(r, 80), minf(b, 80))


## Sizes a full-screen UI root for a CanvasLayer scaled by `ui_scale`.
static func fit_root(layer: CanvasLayer, root: Control, ui_scale: float) -> Vector2:
	var vs := layer.get_viewport().get_visible_rect().size if layer.is_inside_tree() else Vector2(1280, 720)
	layer.scale = Vector2(ui_scale, ui_scale)
	root.position = Vector2.ZERO
	root.size = vs / ui_scale
	return root.size
