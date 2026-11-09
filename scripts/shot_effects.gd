class_name TankAcceptedShotEffects
extends RefCounted

const CAP := 8
const TOTAL_NODES := CAP*3
const MAX_RANGE := 150.0
const BLAST_SHADER = preload("res://assets/effects/accepted_shot.gdshader")
var slots: Array[Dictionary] = []
var active: Array = []
var emitted := 0
var rejected := 0
var parent: Node3D
var card_mesh := QuadMesh.new()
var tracer_mesh := BoxMesh.new()
var tracer_material := StandardMaterial3D.new()
signal preparation_finished(ok: bool)
signal scene_startup_finished(ok: bool)
var scene_startup_report: Dictionary = {}
const SCENE_STARTUP_TIMEOUT_MS := 20000
var preparation_started := false
var preparation_complete := false
var preparation_report: Dictionary = {}
var preparation_viewport: SubViewport
const PREPARATION_SIZE := Vector2i(80,64)
const PREPARATION_TIMEOUT_MS := 2000

func _init(owner: Node3D) -> void:
	parent = owner
	card_mesh.size = Vector2.ONE
	tracer_mesh.size = Vector3.ONE
	tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_material.albedo_color = Color("f7d58a")
	# Dedicated pools prevent lingering contact smoke from evicting the essential
	# muzzle/tracer acknowledgement of any of eight simultaneous accepted shots.
	for kind in ["tracer","muzzle","contact"]:
		for i in range(CAP):
			var node := MeshInstance3D.new()
			node.name = "AcceptedShot_%s_%d" % [kind,i]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visible = false
			parent.add_child(node)
			var mat: ShaderMaterial
			if kind != "tracer":
				mat = ShaderMaterial.new()
				mat.shader = BLAST_SHADER
			node.mesh = tracer_mesh if kind == "tracer" else card_mesh
			node.material_override = tracer_material if kind == "tracer" else mat
			slots.append({"node":node,"material":mat,"kind":kind,"active":false})

# Normal battlefield startup is a separate stage. No effect viewport exists yet.
# Complete the root scene draw/readback before the isolated two-second FX test.
func _prepare_first_scene() -> bool:
	var started := Time.get_ticks_msec()
	var tree := parent.get_tree()
	var root_viewport := parent.get_viewport()
	var attempts := 0
	var verified := false
	var draws := 0
	var image_size := Vector2i.ZERO
	var reason := "SCENE_PIXELS_NOT_VERIFIED"
	while attempts < 3 and Time.get_ticks_msec()-started < SCENE_STARTUP_TIMEOUT_MS:
		attempts += 1
		var completed := {"draw":false}
		var on_draw := func(): completed.draw = true
		RenderingServer.frame_post_draw.connect(on_draw,CONNECT_ONE_SHOT)
		while not completed.draw and Time.get_ticks_msec()-started < SCENE_STARTUP_TIMEOUT_MS and is_instance_valid(parent) and parent.is_inside_tree():
			await tree.process_frame
		if RenderingServer.frame_post_draw.is_connected(on_draw):
			RenderingServer.frame_post_draw.disconnect(on_draw)
		if not completed.draw:
			reason = "SCENE_DRAW_TIMEOUT"
			break
		if Time.get_ticks_msec()-started >= SCENE_STARTUP_TIMEOUT_MS:
			reason = "LATE_SCENE_DRAW_TIMEOUT"
			break
		var image := root_viewport.get_texture().get_image()
		if Time.get_ticks_msec()-started >= SCENE_STARTUP_TIMEOUT_MS:
			reason = "SCENE_READBACK_TIMEOUT"
			break
		draws = root_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		if image != null and not image.is_empty() and draws > 0:
			image_size = image.get_size()
			verified = true
			reason = ""
			break
	var elapsed_ms := Time.get_ticks_msec()-started
	if reason.is_empty() and not scene_startup_result_on_time(verified,elapsed_ms): reason = "SCENE_COMPLETION_TIMEOUT"
	var success := scene_startup_result_on_time(verified,elapsed_ms) and reason.is_empty()
	scene_startup_report = {"status":"FIRST_SCENE_DRAW_VERIFIED" if success else "FAILED","success":success,"reason":reason,"elapsedMs":elapsed_ms,"deadlineMs":SCENE_STARTUP_TIMEOUT_MS,"deadlineOverrunMs":maxi(0,elapsed_ms-SCENE_STARTUP_TIMEOUT_MS),"attempts":attempts,"drawCalls":draws,"imageSize":[image_size.x,image_size.y],"effectViewportCreated":false}
	scene_startup_finished.emit(success)
	return success

static func scene_startup_result_on_time(verified: bool, elapsed_ms: int) -> bool:
	return verified and elapsed_ms >= 0 and elapsed_ms < SCENE_STARTUP_TIMEOUT_MS

# Draw into an isolated offscreen world before READY. Allocation alone does not
# compile a first-visible pipeline. Readback after frame_post_draw proves pixels.
# No permanent pool node is borrowed, no present()/history/recoil/input is used.
func prepare() -> bool:
	if preparation_complete:
		return preparation_report.get("success",false)
	if preparation_started:
		return await preparation_finished
	preparation_started = true
	var total_started := Time.get_ticks_msec()
	if DisplayServer.get_name() == "headless":
		scene_startup_report = {"status":"SKIPPED_HEADLESS","success":true,"effectViewportCreated":false}
		scene_startup_finished.emit(true)
		preparation_report = {"status":"SKIPPED_HEADLESS","success":true,"drawnMaterials":0,"temporaryNodes":0,"retired":true,"sceneStartup":scene_startup_report,"totalElapsedMs":Time.get_ticks_msec()-total_started}
		preparation_complete = true
		preparation_finished.emit(true)
		return true
	var scene_ok := await _prepare_first_scene()
	if not scene_ok:
		preparation_report = {"status":"FAILED","success":false,"phase":"SCENE_STARTUP","reason":scene_startup_report.reason,"drawnMaterials":0,"temporaryNodes":0,"retired":true,"sceneStartup":scene_startup_report,"totalElapsedMs":Time.get_ticks_msec()-total_started}
		preparation_complete = true
		preparation_finished.emit(false)
		return false
	var started := Time.get_ticks_msec()
	var tree := parent.get_tree()
	preparation_viewport = SubViewport.new()
	preparation_viewport.name = "EffectsPreparation"
	preparation_viewport.size = PREPARATION_SIZE
	preparation_viewport.own_world_3d = true
	preparation_viewport.transparent_bg = true
	preparation_viewport.gui_disable_input = true
	preparation_viewport.handle_input_locally = false
	preparation_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(preparation_viewport)
	var probe_camera := Camera3D.new()
	probe_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	probe_camera.size = 8.0
	probe_camera.position = Vector3(0,0,10)
	preparation_viewport.add_child(probe_camera)
	probe_camera.current = true
	var centers: Array[Vector2i] = []
	var labels: Array[String] = []
	var index := 0
	for slot in slots:
		if slot.kind == "tracer": continue
		var age := 0.025 if index % 2 == 0 else 0.25
		slot.material.set_shader_parameter("age",age)
		slot.material.set_shader_parameter("life",0.48 if slot.kind == "muzzle" else 0.85)
		slot.material.set_shader_parameter("variant",0.0 if slot.kind == "muzzle" else 1.0)
		slot.material.set_shader_parameter("seed",float(index)*0.37)
		var node := MeshInstance3D.new()
		node.mesh = card_mesh
		node.material_override = slot.material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(float(index % 5-2)*1.8,(1.5-float(index/5))*1.8,0)
		node.scale = Vector3.ONE*1.2
		preparation_viewport.add_child(node)
		centers.append(Vector2i(probe_camera.unproject_position(node.global_position)))
		labels.append(slot.kind+"_"+("hot" if age < 0.1 else "smoke")+"_"+str(index))
		index += 1
	var tracer := MeshInstance3D.new()
	tracer.mesh = tracer_mesh
	tracer.material_override = tracer_material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.position = Vector3(float(index % 5-2)*1.8,(1.5-float(index/5))*1.8,0)
	tracer.scale = Vector3(1.2,0.24,0.24)
	preparation_viewport.add_child(tracer)
	centers.append(Vector2i(probe_camera.unproject_position(tracer.global_position)))
	labels.append("tracer")
	var texture := preparation_viewport.get_texture()
	var verified := 0
	var attempts := 0
	var draws := 0
	var samples: Array = []
	var reason := "PIXELS_NOT_VERIFIED"
	while attempts < 3 and Time.get_ticks_msec()-started < PREPARATION_TIMEOUT_MS:
		attempts += 1
		preparation_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		var completed := {"draw":false}
		var on_draw := func(): completed.draw = true
		RenderingServer.frame_post_draw.connect(on_draw,CONNECT_ONE_SHOT)
		while not completed.draw and Time.get_ticks_msec()-started < PREPARATION_TIMEOUT_MS and is_instance_valid(parent) and parent.is_inside_tree():
			await tree.process_frame
		if RenderingServer.frame_post_draw.is_connected(on_draw):
			RenderingServer.frame_post_draw.disconnect(on_draw)
		if not is_instance_valid(preparation_viewport):
			reason = "CANCELLED"
			break
		if not completed.draw:
			reason = "DRAW_TIMEOUT"
			break
		if Time.get_ticks_msec()-started >= PREPARATION_TIMEOUT_MS:
			reason = "LATE_DRAW_TIMEOUT"
			break
		# get_image is a tiny GPU readback after the documented post-draw signal.
		# Alpha at every non-overlapping cue center verifies all17 actual draws.
		var image := texture.get_image()
		# A blocked GPU readback cannot be preempted. Never accept a late return.
		if Time.get_ticks_msec()-started >= PREPARATION_TIMEOUT_MS:
			reason = "READBACK_TIMEOUT"
			break
		verified = 0
		samples.clear()
		if image != null and not image.is_empty() and image.get_size() == PREPARATION_SIZE:
			for i in range(centers.size()):
				var at := centers[i]
				if at.x >= 0 and at.x < image.get_width() and at.y >= 0 and at.y < image.get_height():
					var pixel := image.get_pixelv(at)
					if pixel.a > 0.04: verified += 1
					samples.append({"cue":labels[i],"pixel":[at.x,at.y],"rgba":pixel.to_html(true)})
			draws = preparation_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		if verified == 17:
			reason = ""
			break
	if is_instance_valid(preparation_viewport):
		preparation_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		preparation_viewport.free()
	preparation_viewport = null
	var elapsed_ms := Time.get_ticks_msec()-started
	if reason.is_empty() and not preparation_result_on_time(verified,elapsed_ms): reason = "RETIREMENT_TIMEOUT"
	var success := preparation_result_on_time(verified,elapsed_ms) and reason.is_empty()
	preparation_report = {"status":"DRAW_VERIFIED" if success else "FAILED","success":success,"reason":reason,"drawnMaterials":verified,"drawCalls":draws,"attempts":attempts,"size":[80,64],"temporaryNodes":19,"retired":true,"elapsedMs":elapsed_ms,"deadlineMs":PREPARATION_TIMEOUT_MS,"deadlineOverrunMs":maxi(0,elapsed_ms-PREPARATION_TIMEOUT_MS),"samples":samples,"phase":"EFFECT_VERIFICATION","sceneStartup":scene_startup_report,"totalElapsedMs":Time.get_ticks_msec()-total_started}
	preparation_complete = true
	preparation_finished.emit(success)
	return success

static func preparation_result_on_time(materials: int, elapsed_ms: int) -> bool:
	return materials == 17 and elapsed_ms >= 0 and elapsed_ms < PREPARATION_TIMEOUT_MS

func clear() -> void:
	for slot in slots:
		slot.node.visible = false
		slot.active = false
	active.clear()

func _take(kind: String, start: float, life: float, origin: Vector3, direction: Vector3, size: float, seed_value: float) -> Dictionary:
	var slot: Dictionary = {}
	for item in slots:
		if item.kind == kind and not item.active:
			slot = item
			break
	if slot.is_empty():
		for item in active:
			if item.kind == kind:
				slot = item
				break
		active.erase(slot)
		# Reuse this cue type's oldest slot; contacts never consume muzzle/tracers.
	var node: MeshInstance3D = slot.node
	slot.merge({"active":true,"kind":kind,"start":start,"life":life,"origin":origin,"direction":direction,"size":size,"until":int((start+life)*1000.0)},true)
	node.position = origin
	node.scale = Vector3.ONE
	node.visible = true
	if kind == "tracer":
		node.mesh = tracer_mesh
		node.material_override = tracer_material
	else:
		node.mesh = card_mesh
		node.material_override = slot.material
		slot.material.set_shader_parameter("age",0.0)
		slot.material.set_shader_parameter("life",life)
		slot.material.set_shader_parameter("variant",0.0 if kind == "muzzle" else 1.0)
		slot.material.set_shader_parameter("seed",seed_value)
	active.append(slot)
	emitted += 1
	return slot

# Called exclusively after the snapshot's accepted new-shot/age/history gate.
# A full-range miss never creates a contact, and no client trace resolves damage.
func present(shot: Dictionary, now: float) -> bool:
	for key in ["x","y","z","endX","endY","endZ"]:
		if not shot.has(key) or not (shot[key] is float or shot[key] is int) or not is_finite(float(shot[key])):
			rejected += 1
			return false
	var origin := Vector3(shot.x,shot.y,shot.z)
	var endpoint := Vector3(shot.endX,shot.endY,shot.endZ)
	var delta := endpoint-origin
	var distance := delta.length()
	if distance > MAX_RANGE or not is_finite(now):
		rejected += 1
		return false
	var direction := delta.normalized() if distance > 0.0001 else Vector3.FORWARD
	var seed_value := float(int(shot.get("id",0)) % 101) * 0.37
	if distance > 0.1:
		var tracer := _take("tracer",now,0.13,origin,direction,minf(distance,4.0),seed_value)
		tracer["distance"] = distance
	_take("muzzle",now,0.48,origin+direction*0.10,direction,1.05,seed_value)
	var hit = shot.get("hit")
	var blocked = shot.get("blocked",false)
	var contact: bool = (hit is String and not hit.is_empty()) or (hit is bool and hit == true) or (blocked is bool and blocked == true)
	if contact:
		# Endpoint is authoritative. Set the card back slightly on that incoming
		# ray so the collider doesn't bury it. No assumed surface normal/scorch.
		_take("contact",now,0.85,endpoint-direction*0.20,direction,1.55,seed_value)
	return true

func update(now: float, camera: Camera3D) -> void:
	for i in range(active.size()-1,-1,-1):
		var slot: Dictionary = active[i]
		var age: float = now-slot.start
		var node: MeshInstance3D = slot.node
		if age >= slot.life or age < 0:
			node.visible = false
			slot.active = false
			active.remove_at(i)
			continue
		var direction: Vector3 = slot.direction
		if slot.kind == "tracer":
			var travelled := minf(slot.distance,slot.distance*age/slot.life)
			var length_value := minf(slot.size,travelled+0.1)
			node.position = slot.origin+direction*maxf(0.0,travelled-length_value/2.0)
			var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
			node.basis = Basis.looking_at(direction,up)
			node.scale = Vector3(0.045,0.045,length_value)
		else:
			var progress: float = age/slot.life
			var growth: float = 1.0+progress*(1.0 if slot.kind == "muzzle" else 1.8)
			node.position = slot.origin+Vector3.UP*progress*(0.38 if slot.kind == "muzzle" else 0.85)
			if camera != null:
				node.basis = camera.global_basis
			node.scale = Vector3.ONE*slot.size*growth
			slot.material.set_shader_parameter("age",age)
