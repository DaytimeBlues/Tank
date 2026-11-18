extends RefCounted
# One mesh, three opaque material batches; server owns all collision.
static func build(p:Dictionary)->MeshInstance3D:
 var result:=MeshInstance3D.new()
 result.name="TimberLanding"
 var mesh:=ArrayMesh.new()
 for g in p.quay.surfaces:
  var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
  var mat:=StandardMaterial3D.new();mat.roughness=.98
  mat.albedo_color=Color(g.color[0],g.color[1],g.color[2])
  st.set_material(mat)
  for i in range(int(g.firstIndex),int(g.firstIndex+g.count),3):
   var tri:=PackedVector3Array()
   for j in 3:
    var k:=int(p.indices[i+j])*3
    tri.append(Vector3(p.vertices[k],p.vertices[k+1],p.vertices[k+2]))
   var normal:Vector3=(tri[2]-tri[0]).cross(tri[1]-tri[0]).normalized()
   for v in tri:st.set_normal(normal);st.add_vertex(v)
  st.commit(mesh)
 result.mesh=mesh
 return result

