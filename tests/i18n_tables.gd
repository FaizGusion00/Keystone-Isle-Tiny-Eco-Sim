class_name I18nTables
extends RefCounted
## Every player-facing text that lives in constant tables or data files (shown through I18n.t at
## display time), so tests can require a translation for each even if a sweep never shows it.


static func all_texts() -> PackedStringArray:
	var out := PackedStringArray()
	var add := func(v: Variant) -> void:
		var s := str(v)
		if s != "" and I18n.wants_translation(s) and not out.has(s):
			out.append(s)
	for v in EventText.TITLES.values(): add.call(v)
	for v in EventText.NAMES.values(): add.call(v)
	for v in EventText.PLACES: add.call(v)
	for v in EventText.ROOTS.values(): add.call(v)
	for v in EventText.SPECIES.values(): add.call(v)
	for v in Simulation.SEASON_NAMES: add.call(v)
	for v in ScenarioCatalog.MONTHS: add.call(v)
	for v in Scenario.MEDAL_NAMES: add.call(v)
	for v in IslandGenerator.PRESET_NAMES: add.call(v)
	for v in IslandGenerator.PRESET_BLURBS: add.call(v)
	for v in LandType.NAMES: add.call(v)
	for v in Hud.TOOL_LABELS: add.call(v)
	for v in Hud.TOOL_TIPS: add.call(v)
	for v in Screens.SIZE_LABELS: add.call(v)
	for v in Hud.TOOL_HINTS: add.call(v)
	for m in Moments.BY_TYPE.values():
		add.call(m[1])
		add.call(m[2])
	for st in GuideSteps.TUTORIAL:
		for k in ["title", "body", "touch", "hint"]:
			if st.has(k):
				add.call(st[k])
	for a in Achievements.LIST:
		add.call(a["title"])
		add.call(a["text"])
	for d in ScenarioCatalog.all():
		for k in ["title", "blurb", "intro", "win_text"]:
			if d.has(k):
				add.call(d[k])
	var sb: Dictionary = ScenarioCatalog.SANDBOX
	for k in ["title", "blurb"]:
		if sb.has(k):
			add.call(sb[k])
	for m in ContentDB.mutators():
		add.call(m.get("title", ""))
		add.call(m.get("blurb", ""))
	for mode in ScenarioCatalog.MODES:
		var md := ContentDB.mode(mode)
		add.call(md.get("title", ""))
		add.call(md.get("blurb", ""))
	for s in ContentDB.file("species").get("species", []):
		for k in ["title", "needs", "effect"]:
			add.call(s.get(k, ""))
	for r in ContentDB.file("codex").get("rare_events", []):
		for k in ["title", "text", "counter"]:
			add.call(r.get(k, ""))
	for b in ContentDB.file("cosmetics").get("banners", []):
		add.call(b.get("title", ""))
	return out
