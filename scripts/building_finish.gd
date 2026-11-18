extends RefCounted
# Surface-only finish: original arrays, surfaces and transforms remain untouched.
static func apply(mesh:MeshInstance3D,surface:int,kind:int,colour:String)->void:
 var material=ShaderMaterial.new();material.shader=load("res://assets/shaders/building_finish.gdshader")
 material.set_shader_parameter("surface_color",Color(colour));material.set_shader_parameter("finish_kind",kind)
 var vertices=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
 var bottom:=INF
 for p in vertices:bottom=minf(bottom,p.y)
 material.set_shader_parameter("bottom_y",bottom)
 mesh.set_surface_override_material(surface,material)
