extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []
	# Packed scenes are remapped to .scn in a release PCK. ResourceLoader follows
	# that remap; FileAccess deliberately does not.
	if not ResourceLoader.exists("res://scenes/main.tscn"):
		failures.append("missing exported scene res://scenes/main.tscn")
	for path in ["res://data/arena.json","res://assets/models/kestrel.glb.import","res://assets/models/palisade.glb.import"]:
		if not FileAccess.file_exists(path): failures.append("missing exported resource "+path)
	for path in ["res://art/models/kestrel/kestrel.blend","res://art/models/baseline/kestrel.glb","res://art/models/generator-baseline.py","res://backend/server.mjs","res://backend/src/private-access.mjs","res://evidence/source-bridge-manifest.json","res://recovery/original-node-history.bundle","res://tests/network_smoke.gd"]:
		if FileAccess.file_exists(path): failures.append("excluded private/development resource present "+path)
	for directory in ["art","backend","tools","docs","evidence","recovery","web","tests"]:
		if DirAccess.dir_exists_absolute("res://"+directory): failures.append("excluded development directory present "+directory)
	print("TANK_GODOT_EXPORT_AUDIT "+JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"resource_root":ProjectSettings.globalize_path("res://"),"root_directories":DirAccess.get_directories_at("res://")}))
	quit(0 if failures.is_empty() else 1)
