extends Node3D
# Meshy crown only; original solid trunks remain untouched.
func build(data:Dictionary)->void:
 var scene=load("res://assets/meshy_oak/oak-prepared.glb").instantiate()
 var source:MeshInstance3D=null
 for n in scene.find_children("*","MeshInstance3D",true,false):
  if n.mesh.get_surface_count()==2:source=n;break
 assert(source!=null)
 var arrays=source.mesh.surface_get_arrays(1)
 var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var bounds=AABB(vertices[0],Vector3.ZERO)
 for p in vertices:bounds=bounds.expand(p)
 var center=bounds.get_center();var radius=0.0
 for p in vertices:radius=maxf(radius,Vector2(p.x-center.x,p.z-center.z).length())
 for i in range(vertices.size()):vertices[i]-=center
 arrays[Mesh.ARRAY_VERTEX]=vertices
 var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var material=source.mesh.surface_get_material(1).duplicate();material.vertex_color_use_as_albedo=false
 mesh.surface_set_material(0,material)
 var batches={}
 for tree in data.trees:
  if preload("res://scripts/open_orchard_crowns.gd").TYPES.has(tree.id): continue
  var key=Vector2i(floori((tree.x+160)/80),floori((tree.z+160)/80))
  if not batches.has(key):batches[key]=[]
  batches[key].append(tree)
 for key in batches:
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=batches[key].size()
  for i in range(mm.instance_count):
   var t:Dictionary=batches[key][i]
   # Uniform fit stays inside original circular crown radius for every rotation.
   var scale=minf(float(t.crown)/radius,float(t.crown)*2.4/bounds.size.y)
   var yaw=fposmod(float(t.x)*1.73+float(t.z)*.91,TAU)
   mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale),Vector3(t.x,t.y+t.trunkHeight+t.crown*.45,t.z)))
  var batch=MultiMeshInstance3D.new();batch.multimesh=mm;add_child(batch)
 preload("res://scripts/open_orchard_crowns.gd").add_batches(self,data.trees)
 set_meta("crown_count",data.trees.size());set_meta("source_radius",radius);set_meta("source_height",bounds.size.y)
 scene.free()

