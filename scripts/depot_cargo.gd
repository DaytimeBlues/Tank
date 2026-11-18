extends RefCounted
# Bounded cargo additions in the two existing Depot slots; no new authority type.
static func materials()->Dictionary:
 var result={}
 for key in {"depot_crate_stack":["6e6148","9b835c"],"depot_barrel_cluster":["765b43","50635f"]}:
  result[key]=[]
  for colour in {"depot_crate_stack":["6e6148","9b835c"],"depot_barrel_cluster":["765b43","50635f"]}[key]:
   var mat=StandardMaterial3D.new();mat.albedo_color=Color(colour);mat.roughness=.94;result[key].append(mat)
 return result
static func finish(node:Node,asset:String,mats:Dictionary)->void:
 if node is MeshInstance3D:
  assert(node.mesh.get_surface_count()==2)
  for surface in 2:node.set_surface_override_material(surface,mats[asset][surface])
 for child in node.get_children():finish(child,asset,mats)
static func collect(node:Node,world:Transform3D,rows:Array)->void:
 assert(not(node is CollisionObject3D))
 if node is MeshInstance3D:rows.append({"mesh":node.mesh,"transform":world})
 for child in node.get_children():
  if child is Node3D:collect(child,world*child.transform,rows)
static func build(parent:Node3D,p:Dictionary,library:Node,mats:Dictionary)->void:
 assert(p.id in ["depot-crates-a","depot-crates-b"])
 assert(p.cargoParts.size()>=1 and p.cargoParts.size()<=3)
 var group=Node3D.new();group.name=p.id+"-cargo";parent.add_child(group)
 var batches={};var crates=0;var barrels=0
 for part in p.cargoParts:
  assert(part.asset in ["depot_crate_stack","depot_barrel_cluster"] and part.scale==1)
  var position=Vector3(part.x,part.y,part.z)
  assert(position.is_finite() and is_finite(float(part.yaw)) and abs(part.x-p.x)<=6 and abs(part.z-p.z)<=5)
  if part.asset=="depot_crate_stack":crates+=1
  else:barrels+=1
  assert(crates<=2 and barrels<=1)
  var source=library.get_node("OutsideCoreLandmarks/"+part.asset)
  var world=Transform3D(source.transform.basis.rotated(Vector3.UP,part.yaw),position)
  var rows=[];collect(source,world,rows)
  for row in rows:
   for surface in row.mesh.get_surface_count():
    var key=part.asset+str(surface)
    if not batches.has(key):
     var tool=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES);tool.set_material(mats[part.asset][surface]);batches[key]=tool
    batches[key].append_from(row.mesh,surface,row.transform)
 for key in batches:
  var mesh=MeshInstance3D.new();mesh.name=key;mesh.mesh=batches[key].commit();group.add_child(mesh)
