class_name UiKit
extends RefCounted
## Tiny helpers for building touch-friendly UI in code.

const BUTTON_MIN := Vector2(96, 60)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	return t


static func button(text: String, min_size: Vector2 = BUTTON_MIN) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b


static func label(text: String = "", size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


static func panel(alpha: float = 0.82) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.12, alpha)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p
