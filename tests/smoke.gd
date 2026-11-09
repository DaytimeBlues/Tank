extends SceneTree

var failures: Array[String] = []
var checks := 0
var results: Dictionary = {}

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	check(main.arena.terrain_chunks == 16,"16 terrain chunks")
	check(main.arena.bridge_count == 3,"3 bridges")
	check(main.arena.tree_count == 98,"98 source trees")
	check(main.arena.base_labels.size() == 7,"7 bases")
	var triangles := 0
	var vertices_match := true
	for chunk in main.arena.source_data.chunks:
		var instance: MeshInstance3D = main.arena.get_node(str(chunk.id))
		var arrays: Array = instance.mesh.surface_get_arrays(0)
		triangles += arrays[Mesh.ARRAY_INDEX].size()/3
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(points.size()):
			var expected := Vector3(chunk.vertices[i*3],chunk.vertices[i*3+1],chunk.vertices[i*3+2])
			if not points[i].is_equal_approx(expected): vertices_match = false
	check(triangles == 8192,"8192 exact source terrain triangles")
	check(vertices_match,"all terrain vertex positions agree with source data")
	for id in TankPortVisual.IDS:
		var visual := TankPortVisual.new()
		root.add_child(visual)
		visual.choose(id)
		for required in ["Hull","TurretYaw","BarrelPitch","Barrel","Muzzle"]:
			check(visual.model.find_child(required,true,false) != null,id+" hierarchy "+required)
		var muzzle: Node3D = visual.model.find_child("Muzzle",true,false)
		check(muzzle.global_position.distance_to(Vector3(0,1.65,4.05))<0.0001,id+" rest muzzle contract")
		var rest := visual.barrel.position
		visual.recoil_age = 0.022
		visual._process(0)
		check(visual.barrel.position.distance_to(rest-Vector3(0,0,0.18))<0.0001,id+" barrel-only recoil")
		visual.recoil_age = 0.29
		visual._process(0)
		check(visual.barrel.position.is_equal_approx(rest),id+" barrel recoil returns")
		visual.queue_free()
	var transport := TankPortTransport.new()
	for url in ["wss://example.com:443","ws://127.0.0.1:5218@evil.example","ws://localhost.evil.example:5218","ws://127.0.0.1:0","ws://127.0.0.1:70000"]:
		check(transport.open_local(url,{}) == ERR_UNAUTHORIZED,"reject nonlocal or malformed endpoint")
	check(transport.rejoin() == ERR_UNCONFIGURED,"no synthetic reconnect without a seat")
	# Presentation-only unit probes do not change authoritative gameplay state.
	for i in range(12):
		main._present_shot({"x":0,"y":2,"z":0,"endX":2,"endY":2,"endZ":2,"hit":true,"blocked":true})
	check(main.effects.size() == 24,"accepted presentation stays capped at eight dedicated slots per cue,24 total mesh nodes")
	main._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not main.window_focused and main.controls_blocked,"focus-out latches a neutral input gate")
	main._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	check(main.window_focused and main.controls_blocked,"focus-in retains fresh-release input latch")
	for sample in [[Vector2(0,1),0.0],[Vector2(1,0),0.5],[Vector2(0,-1),1.0],[Vector2(-1,0),-0.5],[Vector2(1,1),0.25],[Vector2(-1,-1),-0.75]]:
		check(is_equal_approx(main.normalized_bearing(sample[0]),sample[1]),"pointer bearing normalized to server [-1,1] contract")
	main._network_error("Wrong room")
	check(main.state.is_empty() and main.controls_blocked and main.ready_button.disabled and not main.connect_buttons[0].disabled and not main.connect_buttons[1].disabled,"terminal error clears state, neutralizes controls and permits corrected Create/Join")
	results = {"kind":"Godot scene/map/actual imported-model smoke","checks":checks,"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL","engine":Engine.get_version_info().string}
	var file := FileAccess.open("res://evidence/godot-smoke.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t")+"\n")
	print("TANK_GODOT_SMOKE "+JSON.stringify(results))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
