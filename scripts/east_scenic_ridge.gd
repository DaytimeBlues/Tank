extends RefCounted
# Arena coordinates. Its 12.5 m apron rings leave the orchard and bunker
# footing faces untouched through x=210. The two shoulders share one spine.
static func rise(x: float, z: float) -> float:
	if x <= 210.0 or x >= 285.0 or z <= -157.0 or z >= 85.0:
		return 0.0
	var turn := smoothstep(-122.0, -32.0, z)
	var crest_x := lerpf(233.0, 241.5, turn) - 3.0 * smoothstep(-24.0, 60.0, z)
	var section := smoothstep(210.0, crest_x, x) * (1.0 - smoothstep(crest_x, 285.0, x))
	var north := smoothstep(-157.0, -105.0, z) * (1.0 - smoothstep(-94.0, -46.0, z))
	var orchard := smoothstep(-50.0, -3.0, z) * (1.0 - smoothstep(8.0, 85.0, z))
	var spine := smoothstep(-157.0, -118.0, z) * (1.0 - smoothstep(30.0, 85.0, z))
	return section * (8.5 * spine + 11.8 * north + 10.5 * orchard)

static func reshape(perimeter: Node3D) -> void:
	for child in perimeter.get_children():
		if child is MeshInstance3D and child.mesh is ArrayMesh and child.mesh.get_aabb().size.y > 0.1:
			_sculpt(child)
			return

static func _sculpt(land: MeshInstance3D) -> void:
	var source: ArrayMesh = land.mesh
	var result := ArrayMesh.new()
	var local_up := land.transform.basis.inverse() * Vector3.UP
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var original_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var moved := PackedByteArray()
		moved.resize(verts.size())
		var incident := PackedByteArray()
		incident.resize(verts.size())
		for i in verts.size():
			var p := land.transform * verts[i]
			var delta := rise(p.x, p.z)
			if delta > 0.0:
				verts[i] += local_up * delta
				moved[i] = 1
		var sums := PackedVector3Array()
		sums.resize(verts.size())
		for k in range(0, indices.size(), 3):
			var a := indices[k]
			var b := indices[k + 1]
			var c := indices[k + 2]
			var face := (verts[c] - verts[a]).cross(verts[b] - verts[a])
			# The two-sided apron uses downward stored normals; preserve its
			# authored normal hemisphere, not an assumed upward winding.
			if face.dot(original_normals[a]) < 0.0: face = -face
			sums[a] += face
			sums[b] += face
			sums[c] += face
			if moved[a] or moved[b] or moved[c]:
				incident[a] = 1
				incident[b] = 1
				incident[c] = 1
		var normals := original_normals.duplicate()
		for i in normals.size():
			if incident[i]: normals[i] = sums[i].normalized()
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		result.add_surface_from_arrays(source.surface_get_primitive_type(s), arrays)
		result.surface_set_material(s, source.surface_get_material(s))
	land.mesh = result
