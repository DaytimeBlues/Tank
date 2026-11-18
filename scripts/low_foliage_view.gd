extends Node3D
# Decorative low foliage only, never hard cover or a new collider.
# Original leaf surface reused; nineteen bounded instances in three local batches.
func build() -> void:
	var points:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/low-foliage.json"))
	assert(points.size()<=24)
	var scene=load("res://assets/meshy_oak/oak-prepared.glb").instantiate()
	var source:MeshInstance3D=null
	for n in scene.find_children("*","MeshInstance3D",true,false):
		if n.mesh.get_surface_count()==2:source=n;break
	assert(source!=null)
	var arrays=source.mesh.surface_get_arrays(1)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var bounds=AABB(vertices[0],Vector3.ZERO)
	for p in vertices:bounds=bounds.expand(p)
	var center=bounds.get_center();var radius:=0.0
	for p in vertices:radius=maxf(radius,Vector2(p.x-center.x,p.z-center.z).length())
	for i in vertices.size():vertices[i]-=center
	arrays[Mesh.ARRAY_VERTEX]=vertices
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material=source.mesh.surface_get_material(1).duplicate();material.vertex_color_use_as_albedo=false
	mesh.surface_set_material(0,material)
	var groups={}
	for p in points:
		if not groups.has(p.district):groups[p.district]=[]
		groups[p.district].append(p)
	for district in groups:
		var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=groups[district].size()
		for i in mm.instance_count:
			var p:Dictionary=groups[district][i]
			assert(p.height<=1.0 and p.radius<=1.0)
			var scale=Vector3(p.radius/radius,p.height/bounds.size.y,p.radius/radius)
			mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,p.yaw).scaled(scale),Vector3(p.x,p.y,p.z)))
		var batch=MultiMeshInstance3D.new();batch.name=district;batch.multimesh=mm
		batch.visibility_range_end=65;batch.visibility_range_end_margin=5
		add_child(batch)
	set_meta("instance_count",points.size());set_meta("mesh_vertices",vertices.size());set_meta("batch_count",groups.size())
	scene.free()
