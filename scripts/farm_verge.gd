extends Node3D
# Low decorative garden-edge skirt. Exact terrain-conformed vertices; no collision.
func _ready()->void:
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm_verge.json"))
 var material=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.roughness=1
 var groups={}
 for tuft in data.after:
  var key=str(tuft.cell)
  if not groups.has(key):groups[key]=SurfaceTool.new();groups[key].begin(Mesh.PRIMITIVE_TRIANGLES)
  for i in tuft.vertices.size():
   var v=tuft.vertices[i];var c=tuft.colors[i]
   groups[key].set_color(Color(c[0],c[1],c[2]));groups[key].add_vertex(Vector3(v[0],v[1],v[2]))
 for key in groups:
  groups[key].generate_normals();var node=MeshInstance3D.new();node.name="VergeCell"+str(get_child_count());node.mesh=groups[key].commit();node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
 set_meta("tuft_count",data.after.size())
