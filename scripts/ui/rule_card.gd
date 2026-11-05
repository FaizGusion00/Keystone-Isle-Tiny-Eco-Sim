class_name RuleCard
extends PanelContainer
## A small card that explains one number in plain words, with a checklist when the number
## depends on conditions (e.g. "why isn't the village growing?"). Opens under the chip that was
## tapped; tapping it, the map, or another chip closes it.

var _title: Label
var _icon: TextureRect
var _rows: VBoxContainer
var _foot: Label
var anchor_rect := Rect2()
var key := ""


func _init() -> void:
	theme_type_variation = "Card"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	custom_minimum_size = Vector2(300, 0)
	var col := UiKit.vbox(8)
	add_child(col)
	var head := UiKit.hbox(8)
	col.add_child(head)
	_icon = UiKit.icon("info", 22, UiKit.TEAL)
	head.add_child(_icon)
	_title = UiKit.label("", 18, "Subheading")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(UiKit.icon("x", 16, UiKit.INK_FAINT))
	_rows = UiKit.vbox(5)
	col.add_child(_rows)
	_foot = UiKit.wrap_label("", "Caption", 280)
	col.add_child(_foot)
	gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and not (e as InputEventMouseButton).pressed) \
				or (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed):
			accept_event()
			close())


## rows: [[state, text], …] with state 1 = met (check), 0 = not met (cross), -1 = plain fact.
func open(k: String, icon_name: String, title: String, rows: Array, foot: String, at: Rect2, width: float) -> void:
	key = k
	anchor_rect = at
	_icon.texture = UiKit.icon_tex(icon_name)
	_title.text = title
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for r in rows:
		var row := UiKit.hbox(8)
		var st := int(r[0])
		var ic := "circle-check" if st == 1 else ("circle-x" if st == 0 else "chevron-right")
		var col := UiKit.LEAF if st == 1 else (UiKit.CORAL if st == 0 else UiKit.INK_FAINT)
		row.add_child(UiKit.icon(ic, 18, col))
		var l := UiKit.wrap_label(str(r[1]), "", width - 70.0)
		l.add_theme_font_size_override("font_size", 15)
		row.add_child(l)
		_rows.add_child(row)
	_foot.text = foot
	_foot.visible = foot != ""
	_foot.custom_minimum_size.x = width - 40.0
	custom_minimum_size.x = width
	var was := visible
	visible = true
	reset_size()
	place()
	if not was:
		Motion.appear(self, Vector2(0, -10), Motion.BASE)


func place() -> void:
	var parent := get_parent() as Control
	if parent == null:
		return
	var sz := get_combined_minimum_size()
	var x := clampf(anchor_rect.position.x + anchor_rect.size.x * 0.5 - sz.x * 0.5, 8.0, parent.size.x - sz.x - 8.0)
	var y := anchor_rect.end.y + 8.0
	if y + sz.y > parent.size.y - 8.0:
		y = maxf(8.0, anchor_rect.position.y - sz.y - 8.0)
	position = Vector2(x, y)


func close() -> void:
	if visible:
		key = ""
		Motion.disappear(self, Vector2(0, -8), Motion.FAST)


func text() -> String:
	var parts := PackedStringArray([_title.text])
	for row in _rows.get_children():
		parts.append((row.get_child(1) as Label).text)
	if _foot.visible:
		parts.append(_foot.text)
	return "\n".join(parts)
