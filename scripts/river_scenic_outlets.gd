extends RefCounted
# The nonplayable scenic apron is authored in a separate mesh. Continue the two
# level outlets into its existing meanders; no outside geometry is a collider.
static func reshape(perimeter: Node3D, data: Dictionary) -> void:
 var top: float = data.water.y
 var half: float = data.size/2.0
 var seam := {}
 for chunk in data.chunks:
  for i in range(0,chunk.vertices.size(),3):
   if absf(absf(chunk.vertices[i+2])-half)<0.001:
    seam[Vector2i(roundi(chunk.vertices[i]),roundi(chunk.vertices[i+2]))]=chunk.vertices[i+1]
 var ribbons: Dictionary = {}
 var land: MeshInstance3D
 for child in perimeter.get_children():
  if not child is MeshInstance3D:continue
  if child.mesh.get_aabb().size.y>0.1:land=child;continue
  var vs: PackedVector3Array=child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
  var line:=PackedVector2Array()
  for i in range(0,vs.size(),2):
   var middle: Vector3=child.transform*((vs[i]+vs[i+1])*.5)
   line.append(Vector2(absf(middle.z),middle.x))
  ribbons[signi(roundi((child.transform*vs[0]).z))]=line
  child.position.y+=top-(child.transform*vs[0]).y
 # One shared indexed strip removes the old box end-cap and welds both outlets.
 var water_node: MeshInstance3D
 for item in perimeter.get_parent().get_parent().get_children():
  if item is MeshInstance3D and item.has_meta("river_surface"):water_node=item;break
 if water_node!=null:
  var rows:=PackedVector2Array()
  var negative:PackedVector2Array=ribbons[-1]
  for i in range(negative.size()-1,-1,-1):rows.append(Vector2(-negative[i].x,negative[i].y))
  var positive:PackedVector2Array=ribbons[1]
  for row in positive:rows.append(row)
  var v:=PackedVector3Array()
  var ix:=PackedInt32Array()
  for i in rows.size():
   var r:Vector2=rows[i]
   v.append(Vector3(r.y-data.water.w*.5,top,r.x));v.append(Vector3(r.y+data.water.w*.5,top,r.x))
   if i>0:
    var k:=2*i
    ix.append_array(PackedInt32Array([k-2,k-1,k,k,k-1,k+1]))
  var norms:=PackedVector3Array();norms.resize(v.size());norms.fill(Vector3.UP)
  var a:Array=[];a.resize(Mesh.ARRAY_MAX);a[Mesh.ARRAY_VERTEX]=v;a[Mesh.ARRAY_NORMAL]=norms;a[Mesh.ARRAY_INDEX]=ix
  var ribbon:=ArrayMesh.new();ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
  water_node.transform=Transform3D.IDENTITY;water_node.mesh=ribbon
  water_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  for child in perimeter.get_children():
   if child is MeshInstance3D and child!=land:child.hide()

 if land==null:return
 var original: ArrayMesh=land.mesh
 var out:=ArrayMesh.new()
 for surface in original.get_surface_count():
  var arrays:=original.surface_get_arrays(surface)
  var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  for i in verts.size():
   var p:Vector3=land.transform*verts[i]
   if absf(p.z)<half-.001:continue
   var line:PackedVector2Array=ribbons[signi(roundi(p.z))]
   var center_x:float=line[-1].y
   for j in range(1,line.size()):
    if absf(p.z)<=line[j].x:
     center_x=lerpf(line[j-1].y,line[j].y,inverse_lerp(line[j-1].x,line[j].x,absf(p.z)));break
   var distance:=absf(p.x-center_x)
   var key:=Vector2i(roundi(p.x),roundi(p.z))
   if absf(absf(p.z)-half)<.001 and seam.has(key):
    p.y=seam[key]
   elif distance<20:
    var bed:=lerpf(top-2.1,top-1.8,minf(distance/5,1))
    if distance>5:bed=lerpf(top-1.8,top+1.2,(distance-5)/5)
    p.y=lerpf(bed,p.y,smoothstep(10,20,distance))
   verts[i]=land.transform.affine_inverse()*p
  arrays[Mesh.ARRAY_VERTEX]=verts
  out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  out.surface_set_material(surface,original.surface_get_material(surface))
 land.mesh=out

