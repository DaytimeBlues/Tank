class_name TankArenaView
extends Node3D

## Local opt-in; absent means original crowns.
var developer_cosmo_crowns: bool = read_developer_crown_flag()
var _developer_crown_cache: Dictionary = {}

var source_data: Dictionary
var terrain_chunks := 0
var bridge_count := 0
var tree_count := 0
var base_labels: Dictionary = {}

func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result

func box_at(center: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = center
	add_child(instance)
	return instance

func build(data: Dictionary) -> void:
	source_data = data
	var roadside = load("res://scripts/roadside_cover_view.gd").new()
	roadside.name = "RoadsideCover"
	roadside.build(data)
	add_child(roadside)
	for chunk in data.chunks:
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var normals := PackedVector3Array()
		for i in range(0, chunk.vertices.size(), 3):
			vertices.append(Vector3(chunk.vertices[i], chunk.vertices[i+1], chunk.vertices[i+2]))
			colors.append(Color(chunk.colors[i], chunk.colors[i+1], chunk.colors[i+2]))
			normals.append(Vector3.ZERO)
		var indices := PackedInt32Array()
		var stone_indices := PackedInt32Array()
		for i in range(0, chunk.indices.size(), 3):
			var a: int = chunk.indices[i]
			var b: int = chunk.indices[i+1]
			var c: int = chunk.indices[i+2]
			var normal := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).normalized()
			if normal.y < 0:
				normal = -normal
			for index in [a,b,c]:
				normals[index] += normal
			# Godot's front-face order is the reverse of the source Three mesh.
			var bridge_top_triangle := false
			for bridge in data.bridges:
				var on_top := true
				for index in [a,b,c]:
					var v: Vector3 = vertices[index]
					on_top = on_top and absf(v.y-bridge.top) < 0.001 and absf(v.x-bridge.x) <= bridge.w/2.0 and absf(v.z-bridge.z) <= bridge.d/2.0
				bridge_top_triangle = bridge_top_triangle or on_top
			if bridge_top_triangle:
				stone_indices.append_array(PackedInt32Array([a,c,b]))
			else:
				indices.append_array(PackedInt32Array([a,c,b]))
		for i in range(normals.size()):
			normals[i] = normals[i].normalized()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := material(Color.WHITE)
		mat.vertex_color_use_as_albedo = true
		mesh.surface_set_material(0, mat)
		if not stone_indices.is_empty():
			arrays[Mesh.ARRAY_INDEX] = stone_indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(1, preload("res://assets/materials/bridge_stone/bridge_stone.tres"))
		var instance := MeshInstance3D.new()
		instance.name = chunk.id
		instance.mesh = mesh
		add_child(instance)
		terrain_chunks += 1
	for bridge in data.bridges:
		var deck := box_at(Vector3(bridge.x, bridge.top-bridge.thickness/2.0, bridge.z), Vector3(bridge.w,bridge.thickness,bridge.d),Color("a89c72"))
		deck.material_override = preload("res://assets/materials/bridge_stone/bridge_stone.tres")
		for x in [-28.0,0.0,28.0]:
			for side in [-1.0,1.0]:
				box_at(Vector3(x,bridge.top+0.015,bridge.z+side*6.7),Vector3(2.0,0.025,0.35),Color("e4d69a"))
		bridge_count += 1
	var water_mesh := box_at(Vector3(0,data.water.y-0.025,0),Vector3(data.water.w,0.05,data.size),Color("365f63"))
	water_mesh.set_meta("river_surface",true)
	for tree in data.trees:
		var trunk := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = tree.radius*0.65
		trunk_mesh.bottom_radius = tree.radius
		trunk_mesh.height = tree.trunkHeight
		trunk_mesh.radial_segments = 6
		trunk.mesh = trunk_mesh
		trunk.material_override = material(Color("554a31"))
		trunk.position = Vector3(tree.x,tree.y+tree.trunkHeight/2.0,tree.z)
		add_child(trunk)
		var crown := MeshInstance3D.new()
		crown.set_meta("original_tree_crown",true)
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = tree.crown
		crown_mesh.height = tree.crown*2.4
		crown_mesh.radial_segments = 6
		crown_mesh.rings = 3
		crown.mesh = fit_developer_crown(crown_mesh) if developer_cosmo_crowns else crown_mesh
		crown.material_override = material(Color("486534"))
		crown.position = Vector3(tree.x,tree.y+tree.trunkHeight+tree.crown*0.45,tree.z)
		add_child(crown)
		tree_count += 1
	for base in data.bases:
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = base.radius-0.12
		ring_mesh.outer_radius = base.radius+0.12
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 4
		ring.mesh = ring_mesh
		ring.material_override = material(Color("e1d49a"),true)
		ring.position = Vector3(base.x,base.y+0.08,base.z)
		add_child(ring)
		var label := Label3D.new()
		label.text = "%s · %s" % [base.id,base.name]
		label.position = Vector3(base.x,base.y+4.0,base.z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 42
		label.pixel_size = 0.024
		label.no_depth_test = false
		add_child(label)
		base_labels[str(base.id)] = label

func update_bases(bases: Array) -> void:
	for base in bases:
		if base_labels.has(str(base.id)):
			var label: Label3D = base_labels[str(base.id)]
			var owner_text := "Blue holds" if base.owner == "blue" else "Red holds" if base.owner == "red" else "Neutral"
			var activity := "Contested" if base.get("contested",false) else "Blue taking" if base.get("net",0) > 0 and base.get("progress",0) < 1 else "Red taking" if base.get("net",0) < 0 and base.get("progress",0) > -1 else ""
			label.text = "%s - %s\n%s%s" % [str(base.id),str(base.get("name","")),owner_text," | "+activity if not activity.is_empty() else ""]
			label.modulate = Color("85c6ed") if base.owner == "blue" else Color("ee9980") if base.owner == "red" else Color("eee6ce")

func read_developer_crown_flag() -> bool:
	var value: Variant = ProjectSettings.get_setting("debug/tank/cosmo_crowns",false)
	return typeof(value)==TYPE_BOOL and value

func fit_developer_crown(original: SphereMesh) -> Mesh:
	var key := Vector2(original.radius,original.height)
	if _developer_crown_cache.has(key):return _developer_crown_cache[key]
	if not ResourceLoader.exists("res://assets/experimental_cosmo/crown_mesh.tres"):return original
	var donor := load("res://assets/experimental_cosmo/crown_mesh.tres") as ArrayMesh
	if donor == null or donor.get_surface_count() != 1:
		push_warning("Developer crown unavailable; retaining original.")
		return original
	var proof := HashingContext.new()
	proof.start(HashingContext.HASH_SHA256)
	proof.update(var_to_bytes(donor.surface_get_arrays(0)))
	if proof.finish().hex_encode() != "537c725220c3540e2986c563ac2f9c37dac27ccb179395897dea0bd2591da429":
		push_warning("Developer crown identity mismatch; retaining original.")
		return original
	var donor_vertices: PackedVector3Array = donor.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if donor_vertices.is_empty():return original
	var source := AABB(donor_vertices[0],Vector3.ZERO)
	for point in donor_vertices:
		if not point.is_finite():return original
		source = source.expand(point)
	if not source.size.is_finite() or source.size.x <= 0 or source.size.y <= 0 or source.size.z <= 0:
		return original
	var target := original.get_aabb()
	var uniform := minf(target.size.x/source.size.x, minf(target.size.y/source.size.y,target.size.z/source.size.z))
	var offset := target.get_center()-source.get_center()*uniform
	var arrays := donor.surface_get_arrays(0).duplicate(true)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(vertices.size()):
		vertices[i] = vertices[i]*uniform+offset
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var fitted := ArrayMesh.new()
	fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_developer_crown_cache[key] = fitted
	return fitted
