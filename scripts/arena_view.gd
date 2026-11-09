class_name TankArenaView
extends Node3D

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
	for chunk in data.chunks:
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var normals := PackedVector3Array()
		for i in range(0, chunk.vertices.size(), 3):
			vertices.append(Vector3(chunk.vertices[i], chunk.vertices[i+1], chunk.vertices[i+2]))
			colors.append(Color(chunk.colors[i], chunk.colors[i+1], chunk.colors[i+2]))
			normals.append(Vector3.ZERO)
		var indices := PackedInt32Array()
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
		var instance := MeshInstance3D.new()
		instance.name = chunk.id
		instance.mesh = mesh
		var mat := material(Color.WHITE)
		mat.vertex_color_use_as_albedo = true
		instance.material_override = mat
		add_child(instance)
		terrain_chunks += 1
	for bridge in data.bridges:
		box_at(Vector3(bridge.x, bridge.top-bridge.thickness/2.0, bridge.z), Vector3(bridge.w,bridge.thickness,bridge.d),Color("a89c72"))
		for x in [-28.0,0.0,28.0]:
			for side in [-1.0,1.0]:
				box_at(Vector3(x,bridge.top+0.015,bridge.z+side*6.7),Vector3(2.0,0.025,0.35),Color("e4d69a"))
		bridge_count += 1
	box_at(Vector3(0,data.water.y-0.025,0),Vector3(data.water.w,0.05,data.size),Color("365f63"))
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
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = tree.crown
		crown_mesh.height = tree.crown*2.4
		crown_mesh.radial_segments = 6
		crown_mesh.rings = 3
		crown.mesh = crown_mesh
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
			label.modulate = Color("85c6ed") if base.owner == "blue" else Color("ee9980") if base.owner == "red" else Color("eee6ce")
