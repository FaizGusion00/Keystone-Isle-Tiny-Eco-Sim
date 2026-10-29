class_name OfflinePlatformServices
extends PlatformServices
## The shipping implementation for the offline release: no accounts, no network. Calls are
## recorded (for tests and debugging) and otherwise ignored.

var calls: Array = []   ## [method, args] of every call, capped


func backend() -> String:
	return "offline"


func _log(m: String, args: Array = []) -> void:
	if calls.size() < 200:
		calls.append([m, args])


func sign_in() -> void:
	_log("sign_in")
	signed_in_changed.emit(false)


func submit_score(board: String, score: int) -> void:
	_log("submit_score", [board, score])


func unlock_achievement(id: String) -> void:
	_log("unlock_achievement", [id])


func cloud_push(kind: String, _data: Dictionary) -> void:
	_log("cloud_push", [kind])


func cloud_pull(kind: String) -> void:
	_log("cloud_pull", [kind])
