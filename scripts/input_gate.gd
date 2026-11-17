extends RefCounted
# Per-control physical input gate; integrated only in the isolated candidate.
const CONTROLS = ["w", "s", "a", "d", "left", "right", "space", "mouse1"]
var down: Dictionary = {}
var blocked: Dictionary = {}
var eligible := false
func suspend(raw: Dictionary = {}) -> void:
	eligible = false
	for key in CONTROLS:
		if down.get(key, false) or raw.get(key, false): blocked[key] = true
	down.clear()
func resume() -> void:
	eligible = true
func edge(key: String, pressed: bool, echo := false) -> void:
	if not key in CONTROLS: return
	if not pressed:
		down.erase(key)
		blocked.erase(key)
		return
	if echo: return
	if not eligible:
		blocked[key] = true
		return
	if not blocked.get(key, false): down[key] = true
func value(key: String) -> float:
	return 1.0 if eligible and down.get(key, false) and not blocked.get(key, false) else 0.0
func command() -> Dictionary:
	return {"throttle":value("w")-value("s"), "steer":value("a")-value("d"), "aim":value("left")-value("right"), "fire":value("space")+value("mouse1")>0}

func pointer_aim_allowed() -> bool:
	return eligible and not blocked.get("left",false) and not blocked.get("right",false)
