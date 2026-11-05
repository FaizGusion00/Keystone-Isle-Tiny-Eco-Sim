class_name I18n
extends RefCounted
## Translation. English text is the key; res://i18n/<code>.json maps it to the translated text.
##
## * Static labels, buttons and tooltips are translated by Godot's auto-translate, so they switch
##   language live (NOTIFICATION_TRANSLATION_CHANGED) without rebuilding anything.
## * Text built from a template must translate the TEMPLATE first: `I18n.t("Day %d") % day`.
##   Plurals are whole sentences (two keys), never "farm%s" concatenation.
## * Rules code returns English; the UI translates at display time.
## A missing entry falls back to English. `misses` records lookups with no translation
## (tests/test_i18n.gd walks every screen in each language and fails on any miss).

const LANGUAGES := [["en", "English"], ["ms", "Bahasa Melayu"]] ## [code, name in its own language]
const DIR := "res://i18n/"

static var locked := ""          ## tests force a locale ("en") regardless of the saved setting
static var record_misses := false
static var misses := {}          ## key -> true, only while record_misses
static var produced := {}        ## text already translated by t()/f() (not a miss when seen again)
static var _loaded := {}         ## code -> Table


## A Translation backed by a Dictionary that can report lookups it could not answer.
class Table extends Translation:
	var map := {}

	func _get_message(src_message: StringName, _context: StringName) -> StringName:
		var s := String(src_message)
		if map.has(s):
			return StringName(map[s])
		if I18n.record_misses and not I18n.produced.has(s) and I18n.wants_translation(s):
			I18n.misses[s] = true
		return src_message

	func _get_plural_message(src_message: StringName, _src_plural: StringName, _n: int, context: StringName) -> StringName:
		return _get_message(src_message, context)


static func t(s: String) -> String:
	var out := String(TranslationServer.translate(s))
	if record_misses:
		produced[out] = true
	return out


## Translated template, then formatted: I18n.f("Day %d", [3]) / I18n.f("Reach %d villagers", 12).
static func f(template: String, args: Variant) -> String:
	var out := t(template) % args
	if record_misses:
		produced[out] = true
	return out


## Mark text built from translated parts (e.g. "Day 3 · Rain") so the sweep doesn't flag it.
static func done(s: String) -> String:
	if record_misses:
		produced[s] = true
	return s


static func current() -> String:
	return TranslationServer.get_locale().substr(0, 2)


static func codes() -> PackedStringArray:
	var out := PackedStringArray()
	for l in LANGUAGES:
		out.append(l[0])
	return out


## The language to use on a first launch (no settings saved yet): the device's, if we have it.
static func default_language() -> String:
	var dev := OS.get_locale_language()
	return dev if codes().has(dev) else "en"


## Switch the whole game's language. Returns true if it changed.
static func set_language(code: String) -> bool:
	if locked != "":
		code = locked
	if not codes().has(code):
		code = "en"
	if code != "en":
		_ensure(code)
	if current() == code:
		return false
	TranslationServer.set_locale(code)
	return true


static func _ensure(code: String) -> Table:
	if _loaded.has(code):
		return _loaded[code]
	var tab := Table.new()
	tab.locale = code
	var p := DIR + code + ".json"
	if FileAccess.file_exists(p):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			for k in parsed:
				if str(k).begins_with("//"):
					continue  # comment / section keys
				var v := str(parsed[k])
				if v != "":
					tab.map[str(k)] = v
		else:
			push_error("I18n: %s is not valid JSON" % p)
	else:
		push_error("I18n: missing %s" % p)
	TranslationServer.add_translation(tab)
	_loaded[code] = tab
	return tab


## Unregister the script-backed tables (call before quitting: the engine must not outlive them).
static func shutdown() -> void:
	TranslationServer.set_locale("en")
	for code in _loaded:
		TranslationServer.remove_translation(_loaded[code])
	_loaded.clear()


## All entries of a language (tests).
static func table(code: String) -> Dictionary:
	return _ensure(code).map


## Text that needs a translation: has letters and is not a pure number / symbol / unit.
static func wants_translation(s: String) -> bool:
	var letters := 0
	for c in s:
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z"):
			letters += 1
			if letters >= 2:
				return true
	return false
