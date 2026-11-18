extends Node3D
# Batched soft understorey, <=0.59m high. No physics or hard-cover promises.
# Grouped around existing western-district trees with road/base/service exclusions.
func _ready() -> void:
 var points: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/district_groundcover_points.json"))
 var surface := SurfaceTool.new()
 surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 for blade in range(11):
  var angle := blade*2.39996
  var base := Vector3(cos(angle),0,sin(angle))*0.23
  var side := Vector3(cos(angle+PI/2),0,sin(angle+PI/2))*0.105
  var tip := base+Vector3(cos(angle)*0.23,0.42+0.055*(blade%3),sin(angle)*0.23)
  surface.set_color(Color("4c633a"));surface.add_vertex(base-side)
  surface.set_color(Color("718043"));surface.add_vertex(base+side)
  surface.set_color(Color("82904f"));surface.add_vertex(tip)
 surface.generate_normals()
 var mesh := surface.commit()
 var mat := StandardMaterial3D.new()
 mat.vertex_color_use_as_albedo=true;mat.cull_mode=BaseMaterial3D.CULL_DISABLED;mat.roughness=1.0
 mesh.surface_set_material(0,mat)
 var batches := {}
 for p in points:
  var key := Vector2i(floori(p[0]/24.0),floori(p[2]/24.0))
  if not batches.has(key):batches[key]=[]
  batches[key].append(p)
 for key in batches:
  var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=batches[key].size()
  for i in range(mm.instance_count):
   var p: Array=batches[key][i]
   mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,p[3]).scaled(Vector3.ONE*p[4]),Vector3(p[0],p[1],p[2])))
  var node:=MultiMeshInstance3D.new();node.multimesh=mm;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
 set_meta("tuft_count",points.size())
