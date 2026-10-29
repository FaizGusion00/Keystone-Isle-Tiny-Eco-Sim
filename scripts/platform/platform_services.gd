class_name PlatformServices
extends RefCounted
## Abstraction over everything a future online phase would need: player sign-in (Google Play
## Games / Apple Game Center), leaderboards, platform achievements and cloud save sync.
## The game only talks to this interface (main.services). Today the only implementation is
## OfflinePlatformServices, a no-op that never touches the network. See docs/TDD.md, "Online-ready".
##
## Contract: every call is non-blocking and must be safe to make while offline/signed out;
## results arrive through signals. Implementations must never block the simulation thread.

signal signed_in_changed(signed_in: bool)
signal cloud_pulled(kind: String, data: Dictionary)  ## kind: "progress" | "save"


## Short name for logs / the settings screen ("offline", "gpgs", "gamecenter", ...).
func backend() -> String:
	return "none"


func is_online_capable() -> bool:
	return false


func is_signed_in() -> bool:
	return false


## Stable player id from the platform ("" when signed out). Never the local profile_id.
func player_id() -> String:
	return ""


func sign_in() -> void:
	pass


func sign_out() -> void:
	pass


## Leaderboard id is the scenario id (e.g. "daily_20261030"); score as shown in game.
func submit_score(_board: String, _score: int) -> void:
	pass


func unlock_achievement(_id: String) -> void:
	pass


## Uploads a serialized blob (progress.to_dict() or SaveSystem.to_dict()). Conflicts are
## resolved by the caller with Progress.merge / SaveSystem.resolve_conflict on pull.
func cloud_push(_kind: String, _data: Dictionary) -> void:
	pass


func cloud_pull(_kind: String) -> void:
	pass
