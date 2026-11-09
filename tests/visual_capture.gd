extends SceneTree

# Native rendered presentation fixture, deliberately separate from server play.
# The production camera is not edited. The matched chase uses its exact offset/FOV.
var main: Node
var captures: Array = []
var source_binding: Dictionary = {}
const OUT := "res://evidence/startup-native"

func _initialize() -> void:
	root.unfocusable = true
	root.position = Vector2i(-4000,-4000)
	call_deferred("run")

func fixture(id: String) -> Dictionary:
	var bases: Array = main.arena.source_data.bases.duplicate(true)
	for base in bases: base.merge({"owner":"neutral","net":0,"contested":false},true)
	return {"time":10.0,"players":[{"id":"p1","team":"blue","visualId":id,"connected":true,"ready":true,"health":3,"respawnSeconds":0,"shot":null,"tank":{"x":-118,"y":4.887765873,"z":-46,"yaw":0,"turret":0.65,"reload":0,"speed":0,"quaternion":{"x":0,"y":0,"z":0,"w":1}}}],"playerId":"p1","hostId":"p1","staging":{"waiting":false,"canStart":false,"switchTo":null,"block":null},"won":false,"winner":null,"scores":{"blue":0,"red":0},"capture":{"bases":bases}}

func set_light(original: bool) -> void:
	for child in main.get_children():
		if child is WorldEnvironment: child.environment.ambient_light_energy = 0.8 if original else 0.30
		if child is DirectionalLight3D: child.light_energy = 1.6 if original else 0.95

func set_model(id: String, original: bool) -> void:
	main._accept_state(fixture(id))
	var visual: TankPortVisual = main.peers.p1
	visual.choose(id)
	if original:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		assert(doc.append_from_file("res://art/models/baseline/%s.glb" % id,state) == OK)
		visual.remove_child(visual.model)
		visual.model.free()
		visual.model = doc.generate_scene(state)
		visual.add_child(visual.model)
		visual.turret = visual.model.find_child("TurretYaw",true,false)
		visual.barrel = visual.model.find_child("Barrel",true,false)
		visual.barrel_rest = visual.barrel.position
	visual.turret.rotation.y = 0.65
	main.camera_seeded = false
	main._process(0.0)
	main.shot_effects.clear()

func capture(name_value: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OUT+"/"+name_value+".png"
	var image := root.get_texture().get_image()
	assert(not image.is_empty() and image.get_width() == 1280)
	assert(image.save_png(path) == OK)
	captures.append({"file":path,"cameraPosition":str(main.camera.position),"cameraFov":main.camera.fov,"drawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)})

func bind_inputs() -> void:
	var exported: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://evidence/startup-export-manifest.json"))
	var production := {}
	for path in exported.runtimeSources:
		var current := FileAccess.get_sha256("res://"+path)
		assert(current == exported.runtimeSources[path].sha256,"Runtime source changed since export: "+path)
		production[path] = current
	var baseline := {}
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://evidence/map-model-provenance.json"))
	for id in TankPortVisual.IDS:
		var path := "res://art/models/baseline/%s.glb" % id
		baseline[id] = FileAccess.get_sha256(path)
		assert(baseline[id] == original.models[id],"Retained original GLB changed: "+id)
	source_binding = {"kind":"SHA256 asserted immediately before capture against exact candidate export runtime inputs and retained original model provenance","productionSources":production,"retainedBaselineGlbs":baseline,"exportManifestSha256":FileAccess.get_sha256("res://evidence/startup-export-manifest.json"),"fixtureSha256":FileAccess.get_sha256("res://tests/visual_capture.gd"),"pckSha256":FileAccess.get_sha256("res://web/index.pck")}

func run() -> void:
	bind_inputs()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280,800)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	if not main.presentation_preparation_complete:
		await main.presentation_preparation_finished
	assert(main.presentation_prepared,"Actual preparation must finish before fixture shots")
	for id in TankPortVisual.IDS:
		for condition in ["source-oldlight","source-newlight","candidate-newlight"]:
			set_light(condition == "source-oldlight")
			set_model(id,condition != "candidate-newlight")
			await capture(id+"-"+condition+"-chase")
		set_light(false)
		set_model(id,false)
		var target: Vector3 = main.peers.p1.position+Vector3.UP*1.2
		main.camera.position = target+Vector3(7,4.5,8)
		main.camera.look_at(target)
		await capture(id+"-candidate-newlight-close")
	set_model("kestrel",false)
	var visual: TankPortVisual = main.peers.p1
	var muzzle: Node3D = visual.model.find_child("Muzzle",true,false)
	var origin := muzzle.global_position
	var direction: Vector3 = visual.turret.global_basis.z
	var endpoint := origin+direction*15.0
	var shot := {"id":1,"x":origin.x,"y":origin.y,"z":origin.z,"endX":endpoint.x,"endY":endpoint.y,"endZ":endpoint.z,"hit":true,"blocked":false}
	main.shot_effects.present(shot,10.0)
	for age in [0.025,0.09,0.25,0.60]:
		main.shot_effects.update(10.0+age,main.camera)
		await capture("accepted-contact-age-"+str(age))
	main.shot_effects.clear()
	shot.hit = false
	main.shot_effects.present(shot,20.0)
	main.shot_effects.update(20.09,main.camera)
	await capture("accepted-miss-age-0.09")
	for path in source_binding.productionSources:
		assert(FileAccess.get_sha256("res://"+path) == source_binding.productionSources[path],"Runtime source changed during capture: "+path)
	var report := {"kind":"actual native Compatibility renderer, scripted presentation fixtures with identical source map/chase camera, not server-match or browser/hardware acceptance","engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"sourceBinding":source_binding,"startupPreparation":main.shot_effects.preparation_report,"captures":captures}
	var file := FileAccess.open(OUT+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("TANK_VISUAL_CAPTURE "+JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit()
