extends RefCounted
# Only these nine existing orchard trees change. All placements, solid trunks,
# nominal crown radii and server data are still supplied by the canonical map.
const TYPES := {"tree-35":1,"tree-39":0,"tree-40":2,"tree-44":1,"tree-46":2,
	"tree-47":0,"tree-53":1,"tree-57":0,"tree-62":2}
const FILES := ["res://assets/open_orchard/vase.glb","res://assets/open_orchard/fan.glb",
	"res://assets/open_orchard/leader.glb"]

static func add_batches(parent: Node3D, trees: Array) -> void:
	for form in FILES.size():
		var group: Array = trees.filter(func(t): return TYPES.get(t.id,-1)==form)
		if group.is_empty(): continue
		var donor: Node = load(FILES[form]).instantiate()
		var child := donor.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
		var mesh := child.mesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = group.size()
		for i in group.size():
			var t: Dictionary = group[i]
			var yaw := fposmod(float(t.x)*1.73+float(t.z)*.91,TAU)
			var basis := Basis(Vector3.UP,yaw).scaled(Vector3.ONE*float(t.crown))
			mm.set_instance_transform(i,Transform3D(basis,Vector3(t.x,t.y+t.trunkHeight,t.z)))
		var batch := MultiMeshInstance3D.new()
		batch.name = "Orchard_"+FILES[form].get_file().get_basename()
		batch.multimesh = mm
		parent.add_child(batch)
		donor.free()
