class_name GuideSteps
extends RefCounted
## The guided first island, step by step. Each step points at one thing, says one or two short
## sentences, and waits for the player to DO it (tap the village, pick Farm, build, press Play…).
## Text is English; it is translated at display time.
##
## Keys: id · title · body · target ("tile:village", "tile:best_farm", "tile:farm", "ui:chip:<key>",
## "ui:tool:<n>", "ui:speed", "ui:goals", "ui:history", "") · wait (see Guide._met) · clock
## ("hold" = time stands still, "run" = it plays) · unlock {tools, chips, extras} (added to what is
## already open) · hint_after (days) + hint (a nudge if the player seems stuck) · camera.

const T := Hud.Tool

const TUTORIAL := [
	{"id": "village", "title": "Your village",
	 "body": "Ten people have settled here. Tap the village to see how they are doing.",
	 "target": "tile:village", "camera": "village", "wait": "select_village", "clock": "hold",
	 "unlock": {"chips": ["villagers"]}},
	{"id": "food", "title": "They need food",
	 "body": "This is their food store. Fish and goats keep them alive, but to grow they need farms.",
	 "target": "ui:chip:food", "wait": "next", "clock": "hold",
	 "unlock": {"chips": ["food"]}},
	{"id": "pick_farm", "title": "Pick the Farm tool",
	 "body": "Tap Farm in the toolbar.",
	 "target": "ui:tool:3", "wait": "tool:3", "clock": "hold",
	 "unlock": {"tools": [T.BUILD_FARM], "chips": ["labor", "wood"]}},
	{"id": "place_farm", "title": "Build a farm",
	 "body": "Green tiles can take a farm. Tap one next to the village. It costs 3 labor and 2 wood.",
	 "touch": "Green tiles can take a farm. Tap one next to the village, then tap it again to build.",
	 "target": "tile:best_farm", "camera": "village", "wait": "action:farm", "clock": "hold"},
	{"id": "play", "title": "Let time run",
	 "body": "Time is paused. Press Play - one day passes every second.",
	 "target": "ui:speed", "wait": "speed", "clock": "hold",
	 "unlock": {"extras": ["speed_play"]}},
	{"id": "grow", "title": "The crop is growing",
	 "body": "A farm gives a harvest about every 30 days. Watch the Food number.",
	 "target": "tile:farm", "wait": "harvest", "clock": "run",
	 "hint_after": 6, "hint": "Tip: the » button makes time run faster.",
	 "hint_unlock": {"extras": ["speed_fast"]}},
	{"id": "harvest", "title": "First harvest!",
	 "body": "Food went up. The village grows when everyone is fed and the store holds 3 food per person.",
	 "target": "ui:chip:food", "wait": "next", "clock": "hold",
	 "unlock": {"extras": ["speed_fast"]}},
	{"id": "checklist", "title": "Why isn't it growing yet?",
	 "body": "Tap People any time: it shows exactly what the village still needs.",
	 "target": "ui:chip:villagers", "wait": "chip:villagers", "clock": "hold"},
	{"id": "second_farm", "title": "More farms, more food",
	 "body": "Build a second farm, then let time run until a new villager arrives.",
	 "target": "ui:tool:3", "wait": "grow", "clock": "run", "auto_close": true,
	 "hint_after": 40, "hint": "Still waiting? Tap People to see what is missing - often it is food stored."},
	{"id": "goals", "title": "Your goal",
	 "body": "Reach 12 people. Extra stars: island health 85+ and finishing by day 150. You lose if only 6 people remain.",
	 "target": "ui:goals", "wait": "next", "clock": "hold",
	 "unlock": {"chips": ["water", "keystone"]}},
	{"id": "history", "title": "Why did that happen?",
	 "body": "History lists everything that happened on the island, with its causes. That's it - you're on your own now!",
	 "target": "ui:history", "wait": "next", "clock": "hold", "last": true,
	 "unlock": {"extras": ["history", "layers"], "chips": ["fish", "goats"]}},
]

## What each campaign island opens (later islands open more). Islands not listed: everything.
const ISLAND_TOOLS := {
	"living_island": {"tools": [T.INSPECT, T.BUILD_FARM], "chips": ["villagers", "food", "water", "labor", "wood", "keystone", "fish", "goats"],
		"extras": ["speed_play", "speed_fast", "history", "layers"]},
	"expanding_village": {"tools": [T.INSPECT, T.CLEAR_TREES, T.PLANT_TREES, T.BUILD_FARM, T.BUILD_HOUSE, T.DEMOLISH]},
}
