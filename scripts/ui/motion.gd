class_name Motion
extends RefCounted
## One motion language for the whole UI: shared durations and easings, and helpers that
## never fight each other (each node has one "motion" tween at a time, killed before a new one).
## With reduce motion every helper jumps straight to its end state (callbacks still run).

const FAST := 0.12   ## taps, small state changes
const BASE := 0.20   ## panels, toasts in
const SLOW := 0.32   ## sheets, big reveals
const EMPH := 0.45   ## celebrations




## The node's motion tween (the previous one, if still running, is killed first).
static func tween(n: Node, key := "motion") -> Tween:
	var old: Variant = n.get_meta(key) if n.has_meta(key) else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := n.create_tween()
	n.set_meta(key, t)
	return t


## Stop a running motion tween (its end callback does not run).
static func stop(n: Node, key := "motion") -> void:
	var t: Variant = n.get_meta(key) if n.has_meta(key) else null
	if t is Tween and (t as Tween).is_valid():
		(t as Tween).kill()


static func animating(n: Node, key := "motion") -> bool:
	var t: Variant = n.get_meta(key) if n.has_meta(key) else null
	return t is Tween and (t as Tween).is_valid() and (t as Tween).is_running()


static func _live(n: Node) -> bool:
	return not UiKit.reduce_motion and n.is_inside_tree()


static func out(t: Tweener) -> Tweener:
	return (t as PropertyTweener).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) if t is PropertyTweener else t


## Fade + slide/scale in (delegates to UiKit.appear's container-aware rules).
static func appear(c: Control, from := Vector2(0, 16), d := BASE, delay := 0.0) -> void:
	UiKit.appear(c, from, d, delay)


## Fade + slide out, then hide and call `then`. Containers' children only fade (layout owns them).
static func disappear(c: Control, to := Vector2(0, 10), d := FAST, then := Callable()) -> void:
	if not c.visible:
		if then.is_valid():
			then.call()
		return
	if not _live(c):
		c.visible = false
		c.modulate.a = 1.0
		if then.is_valid():
			then.call()
		return
	var owned := c.get_parent() is Container or c.has_meta("layout_owned")
	var start := c.position
	var t := tween(c).set_parallel(true)
	t.tween_property(c, "modulate:a", 0.0, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if not owned and to != Vector2.ZERO:
		t.tween_property(c, "position", start + to, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func() -> void:
		c.visible = false
		c.modulate.a = 1.0
		if not owned:
			c.position = start
		if then.is_valid():
			then.call())


## Animate a number shown in `label` from `from` to `to`; `fmt` turns a value into text.
## Always lands exactly on `fmt.call(to)`.
static func count_to(label: Label, from: float, to: float, fmt: Callable, d := SLOW) -> void:
	if not _live(label) or is_equal_approx(from, to):
		label.text = fmt.call(to)
		return
	var t := tween(label, "count")
	t.tween_method(func(v: float) -> void: label.text = fmt.call(v), from, to, d) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void: label.text = fmt.call(to))


static func meter_to(bar: Range, v: float, d := SLOW) -> void:
	if not _live(bar) or absf(bar.value - v) < 0.002:
		bar.value = v
		return
	tween(bar, "meter").tween_property(bar, "value", v, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A soft bump (scale 1 → k → 1) to draw the eye.
static func pulse(c: Control, k := 1.12, d := 0.28) -> void:
	if not _live(c):
		return
	c.pivot_offset = c.size * 0.5
	var t := tween(c, "pulse")
	t.tween_property(c, "scale", Vector2(k, k), d * 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE, d * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A quick sideways shake ("no").
static func shake(c: Control, amp := 7.0, d := 0.32) -> void:
	if not _live(c) or c.get_parent() is Container:
		return
	var x0 := c.position.x
	var t := tween(c, "shake")
	for k in 4:
		var s := amp * (1.0 - k / 4.0) * (1.0 if k % 2 == 0 else -1.0)
		t.tween_property(c, "position:x", x0 + s, d / 5.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(c, "position:x", x0, d / 5.0).set_trans(Tween.TRANS_SINE)


## Tween a colour property (e.g. "self_modulate").
static func color_to(o: Object, prop: String, col: Color, d := BASE) -> void:
	if UiKit.reduce_motion or not (o is Node and (o as Node).is_inside_tree()):
		o.set(prop, col)
		return
	tween(o as Node, "color").tween_property(o, prop, col, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Slide a Control (that is NOT in a Container) to a position.
static func slide_to(c: Control, pos: Vector2, d := BASE) -> void:
	if not _live(c):
		c.position = pos
		return
	tween(c, "slide").tween_property(c, "position", pos, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Stagger several nodes in.
static func stagger(nodes: Array, step := 0.04, from := Vector2(0, 12)) -> void:
	var k := 0
	for n in nodes:
		if n is Control:
			appear(n as Control, from, BASE, step * k)
			k += 1
