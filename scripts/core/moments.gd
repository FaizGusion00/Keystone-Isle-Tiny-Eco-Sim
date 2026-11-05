class_name Moments
extends RefCounted
## "First time" moments: the first time the island does something big (soil reaches the sea,
## fish decline, a flood, a fire, a drought, a full village), a short card explains it in one
## line and offers "Show me" - the camera flies there and the recorded causes light up as
## ripple threads. Each moment is shown once per profile (Progress.moments).

const T := EventLog.Type

## event type -> [id, title, line, icon]
const BY_TYPE := {
	T.EROSION: ["erosion", "The hill is washing away",
		"Without trees, rain carries the topsoil downhill. See the brown gullies?", "mountain"],
	T.MUDDY_WATER: ["mud", "Soil reached the sea",
		"Rain washed soil off bare land into the sea. Muddy water drives the fish away - trees on slopes hold it.", "waves"],
	T.FISH_DECLINE: ["fish", "Fewer fish",
		"Fewer fish means less food. Clear coastal water lets them come back.", "fish"],
	T.FLOOD: ["flood", "Flood!",
		"Heavy rain overflowed the river. Forest upstream and dams slow the water down.", "waves"],
	T.WILDFIRE: ["fire", "Wildfire!",
		"Dry forest caught fire. Rain puts it out; burnt land recovers slowly - or use Restore.", "flame"],
	T.DROUGHT: ["drought", "Drought",
		"No rain for days: soil dries out and crops stop growing. A dam stores water for nearby farms.", "sun"],
	T.HOUSING_FULL: ["homes", "No room to grow",
		"Every home is full. Build houses next to the village so more people can move in.", "house"],
}


static func for_event(t: int) -> Array:
	return BY_TYPE.get(t, [])
