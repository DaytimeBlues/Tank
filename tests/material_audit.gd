extends SceneTree

func _initialize() -> void: call_deferred("run")

func inspect_model(model: Node, result: Dictionary) -> void:
	if model is MeshInstance3D:
		for surface in range(model.mesh.get_surface_count()):
			var mat: Material = model.get_active_material(surface)
			if mat is StandardMaterial3D:
				result[mat.resource_name] = {"albedoSrgb":[mat.albedo_color.r,mat.albedo_color.g,mat.albedo_color.b],"linear":[mat.albedo_color.srgb_to_linear().r,mat.albedo_color.srgb_to_linear().g,mat.albedo_color.srgb_to_linear().b],"metallic":mat.metallic,"roughness":mat.roughness,"override":model.material_override != null}
	for child in model.get_children(): inspect_model(child,result)

func run() -> void:
	var report := {}
	for id in TankPortVisual.IDS:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		assert(doc.append_from_file("res://art/models/baseline/%s.glb" % id,state) == OK)
		var baseline := doc.generate_scene(state)
		var original := {}
		inspect_model(baseline,original)
		var candidate := (load("res://assets/models/%s.glb" % id) as PackedScene).instantiate()
		var current := {}
		inspect_model(candidate,current)
		report[id] = {"source":original,"candidate":current}
		baseline.free()
		candidate.free()
	var file := FileAccess.open("res://evidence/imported-material-audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("TANK_MATERIAL_AUDIT "+JSON.stringify(report))
	quit()
