extends Node3D
const WESTERN_FINISH := {
 "windmill-tower":preload("res://assets/western_finish/windmill_landmark.res"),
 "millers-cottage":preload("res://assets/western_finish/farm_cottage.res"),
}
const FARM_HOUSE := preload("res://assets/farm_house/west_farm_house.res")
const FARM_ENCLOSURE := {
 "farm-margin-hedge-a":preload("res://assets/farm_enclosure/farm-margin-hedge-a.res"),
 "farm-margin-hedge-b":preload("res://assets/farm_enclosure/farm-margin-hedge-b.res"),
 "farm-margin-hedge-c":preload("res://assets/farm_enclosure/farm-margin-hedge-c.res"),
 "farm-margin-rocks-a":preload("res://assets/farm_enclosure/farm-margin-rocks-a.res"),
 "farm-margin-rocks-b":preload("res://assets/farm_enclosure/farm-margin-rocks-b.res"),
 "farm-margin-wall-a":preload("res://assets/farm_enclosure/farm-margin-wall-a.res"),
 "farm-margin-wall-b":preload("res://assets/farm_enclosure/farm-margin-wall-b.res"),
 "farm-margin-wall-c":preload("res://assets/farm_enclosure/farm-margin-wall-c.res"),
}
# Existing authored mesh resources, exact same placement contract as static server triangles.
func build(data:Dictionary) -> void:
 var library=load("res://assets/map_dressing.tscn").instantiate()
 var cargo=load("res://scripts/depot_cargo.gd");var cargo_materials=cargo.materials()
 for p in data.get("districtMeshes",[]):
  var resources={"sandbags":"res://assets/ridge/sandbag_stack_2p66m.glb","river_crane":"res://assets/river/crane.glb","pipe_straight":"res://assets/reservoir/pipe_straight2m.glb","pipe_elbow":"res://assets/reservoir/pipe_elbow90.glb"}
  var imported=resources.has(p.asset)
  var source=load(resources[p.asset]).instantiate() if imported else library.get_node("OutsideCoreLandmarks/"+p.asset)
  var node=source.duplicate();node.name=p.id
  node.transform=Transform3D(source.transform.basis.scaled(Vector3(p.scale,p.scale*p.get("scaleY",1.0),p.scale)).rotated(Vector3.RIGHT,p.get("pitch",0.0)).rotated(Vector3.UP,p.get("yaw",0.0)),Vector3(p.x,p.y,p.z))
  if imported:source.free()
  add_child(node)
  # The old 130-triangle house remains available for an old map. The installed
  # 526-triangle contract includes the unchanged 12-triangle footing.
  var revised_house:bool=p.id=="west-farm-house" and p.indices.size()==1578
  if WESTERN_FINISH.has(p.id):
   # Same donor triangles/order, one shared opaque baked material per landmark.
   # Scope these two playable instances only; distant scenery keeps its donors.
   var building:MeshInstance3D=node.get_child(0)
   building.mesh=WESTERN_FINISH[p.id];building.material_override=null
   building.set_surface_override_material(0,null)
  if revised_house:
   var house:MeshInstance3D=node.get_child(0);house.mesh=FARM_HOUSE;house.material_override=null
   for s in house.mesh.get_surface_count():house.set_surface_override_material(s,null)
  if p.has("quay"):add_child(preload("res://scripts/quay_landing.gd").build(p))
  if p.has("cargoParts"):cargo.finish(node,p.asset,cargo_materials)
  if p.has("revetmentParts"):_add_revetment_parts(node,p,library)
  if p.has("accessSteps"):
   for i in p.accessSteps.size():
    var a=p.accessSteps[i];var step=MeshInstance3D.new();step.name="AccessStep"+str(i)
    var box=BoxMesh.new();box.size=Vector3(a.w,a.h,a.d);step.mesh=box
    var stone=ShaderMaterial.new();stone.shader=load("res://assets/shaders/district_stone.gdshader");step.material_override=stone
    node.add_child(step);step.transform=node.transform.affine_inverse()*Transform3D(Basis.IDENTITY,Vector3(a.x,a.y,a.z))
  if p.id=="bridgehead-office":
   var finish=load("res://scripts/building_finish.gd");finish.apply(node.get_child(0),6,0,"b7b09c");finish.apply(node.get_child(0),2,1,"657073")
  if p.id=="bridgehead-wall":
   var stone=ShaderMaterial.new();stone.shader=load("res://assets/shaders/district_stone.gdshader");node.get_child(0).material_override=stone
  if p.has("loadingSteps"):
   var stairs=p.loadingSteps
   for i in int(stairs.count):
    var top=lerpf(p.y+.25,stairs.endTop,float(i)/(stairs.count-1))
    var step=MeshInstance3D.new();step.name="LoadingStep"+str(i)
    var box=BoxMesh.new();box.size=Vector3(stairs.width,top-stairs.bottom,stairs.landingDepth if i==0 else stairs.depth);step.mesh=box
    var concrete=StandardMaterial3D.new();concrete.albedo_color=Color("88867b");concrete.roughness=.96;step.material_override=concrete
    node.add_child(step);step.position=node.transform.affine_inverse()*Vector3(stairs.startX+stairs.get("direction",1)*i*stairs.depth-stairs.get("direction",1)*((stairs.landingDepth-stairs.depth)/2 if i==0 else 0.0),(top+stairs.bottom)/2,p.z)
  if p.id=="river-warehouse":
   var plaster=StandardMaterial3D.new();plaster.albedo_color=Color("b7b29f");plaster.roughness=.96
   plaster.albedo_texture=load("res://assets/farm_plaster.png");plaster.uv1_triplanar=true;plaster.uv1_scale=Vector3.ONE*.5
   node.get_child(0).set_surface_override_material(5,plaster)
   var roof=StandardMaterial3D.new();roof.albedo_color=Color("5b6568");roof.roughness=.91
   node.get_child(0).set_surface_override_material(2,roof)
  if p.id in ["west-farm-barn","orchard-shed"]:
   var wall=StandardMaterial3D.new();wall.albedo_color=Color("bdb5a3");wall.roughness=.94
   wall.albedo_texture=load("res://assets/farm_plaster.png");wall.uv1_triplanar=true;wall.uv1_scale=Vector3.ONE*.5
   node.get_child(0).set_surface_override_material(2,wall)
   var roof=StandardMaterial3D.new();roof.albedo_color=Color("876148");roof.roughness=.92
   node.get_child(0).set_surface_override_material(1,roof)
  if not revised_house and p.id=="west-farm-house":
   var plaster=StandardMaterial3D.new();plaster.albedo_color=Color("c4bda8");plaster.roughness=.96
   plaster.albedo_texture=load("res://assets/farm_plaster.png");plaster.uv1_triplanar=true;plaster.uv1_scale=Vector3.ONE*.5
   node.get_child(0).set_surface_override_material(3,plaster)
   var tiles=StandardMaterial3D.new();tiles.albedo_color=Color("826448");tiles.roughness=.94
   node.get_child(0).set_surface_override_material(2,tiles)
  if p.id in ["west-farm-barn","orchard-shed"]:
   var finish=load("res://scripts/building_finish.gd")
   finish.apply(node.get_child(0),2,0,"bdb5a3")
   finish.apply(node.get_child(0),1,1,"876148")
  if p.id=="orchard-shed":
   var door_mesh:MeshInstance3D=node.get_child(0)
   var original:StandardMaterial3D=door_mesh.mesh.surface_get_material(0)
   var door:=ShaderMaterial.new()
   door.shader=preload("res://assets/shaders/district_stone.gdshader")
   door.set_shader_parameter("press_ink",preload("res://assets/orchard_press/press.png"))
   door.set_shader_parameter("building_space",true)
   door.set_shader_parameter("finish_kind",3)
   door.set_shader_parameter("original_colour",original.albedo_color)
   door.set_shader_parameter("original_roughness",original.roughness)
   door_mesh.set_surface_override_material(0,door)
  if p.id=="west-farm-house":
   var finish=load("res://scripts/building_finish.gd")
   finish.apply(node.get_child(0),5,0,"c4bda8")
   finish.apply(node.get_child(0),2,1,"826448")
  if p.id=="river-warehouse":
   var finish=load("res://scripts/building_finish.gd")
   finish.apply(node.get_child(0),5,0,"b7b29f")
   finish.apply(node.get_child(0),2,1,"5b6568")
  if p.id=="reservoir-house":
   # Finish only the existing reservoir wall and roof surfaces, not the
   # surrounding props, foundation, or mesh/collision contract.
   for surface in [4,2,0,1,3]:
    var finish=ShaderMaterial.new();finish.shader=load("res://assets/reservoir/sluicehouse_finish.gdshader")
    finish.set_shader_parameter("stone_atlas",load("res://assets/reservoir/sluicehouse_atlas.png"))
    finish.set_shader_parameter("roof_surface",surface==2)
    finish.set_shader_parameter("service_trim",surface in [0,1,3])
    node.get_child(0).set_surface_override_material(surface,finish)
  if p.id=="reservoir-valve":
   var finish=load("res://scripts/building_finish.gd");finish.apply(node.get_child(0),0,2,"53605b");finish.apply(node.get_child(0),1,2,"925f48")
  if p.id in ["reservoir-pipe","reservoir-elbow"]:_finish_utility_pipe(node)
  if FARM_ENCLOSURE.has(p.id) and p.indices.size()==FARM_ENCLOSURE[p.id].surface_get_array_index_len(0):
   # Exact eight prebaked solids; old maps with the original geometry retain their kit mesh.
   var part:MeshInstance3D=node.get_child(0);part.mesh=FARM_ENCLOSURE[p.id];part.material_override=null;part.set_surface_override_material(0,null)
  elif p.id.begins_with("farm-margin") or p.id.begins_with("orchard-wall"):
   var material=StandardMaterial3D.new();material.roughness=.97
   material.albedo_color=Color("52623b") if p.asset=="hedgerow_4m" else Color("77776d")
   if p.asset=="low_stone_wall_4m":
    var stone=ShaderMaterial.new();stone.shader=load("res://assets/shaders/district_stone.gdshader");node.get_child(0).material_override=stone
   else:node.get_child(0).material_override=material
  if not p.has("foundationWidth"):continue
  var base=MeshInstance3D.new();base.name=p.id+"-foundation"
  var mesh=BoxMesh.new();mesh.size=Vector3(p.foundationWidth,p.y-p.foundationBottom,p.foundationDepth);base.mesh=mesh
  var mat=ShaderMaterial.new();mat.shader=load("res://assets/shaders/district_stone.gdshader");base.material_override=mat
  base.position=Vector3(p.x,(p.y+p.foundationBottom)/2,p.z);base.rotation.y=p.get("foundationYaw",0.0);add_child(base)
 for p in data.get("districtMeshes",[]):
  if p.has("cargoParts"):cargo.build(self,p,library,cargo_materials)
 library.free()


func _finish_utility_pipe(node:Node) -> void:
 if node is MeshInstance3D:
  var finish=load("res://scripts/building_finish.gd")
  for surface in node.mesh.get_surface_count():finish.apply(node,surface,2,"62756b")
 for child in node.get_children():_finish_utility_pipe(child)

# Small authored compound, not a placement-cap expansion. Children use absolute
# world transforms and exact triangles in the existing placement's collider.
func _add_revetment_parts(node:Node3D,p:Dictionary,library:Node) -> void:
 assert(p.id in ["ridge-bags-north","ridge-bags-south"])
 assert(p.revetmentParts.size()<=3)
 var bags=0;var rocks=0
 var bag_meshes:Array[MeshInstance3D]=[]
 _collect_revetment_meshes(node,bag_meshes)
 for i in p.revetmentParts.size():
  var part=p.revetmentParts[i]
  assert(part.asset in ["sandbags","rock_cluster"])
  var source:Node3D
  if part.asset=="sandbags":
   bags+=1;source=load("res://assets/ridge/sandbag_stack_2p66m.glb").instantiate()
  else:
   rocks+=1;source=library.get_node("OutsideCoreLandmarks/rock_cluster").duplicate()
  assert(bags<=2 and rocks<=1)
  var position=Vector3(part.x,part.y,part.z)
  assert(position.is_finite() and abs(part.x-p.x)<=7 and abs(part.z-p.z)<=3)
  assert(part.scale>0 and part.scale<=1 and part.get("scaleY",1.0)>0 and part.get("scaleY",1.0)<=1)
  var world=Transform3D(source.transform.basis.scaled(Vector3(part.scale,part.scale*part.get("scaleY",1.0),part.scale)).rotated(Vector3.UP,part.yaw),position)
  source.name="RevetmentPart"+str(i);node.add_child(source)
  source.transform=node.transform.affine_inverse()*world
  if part.asset=="sandbags":_collect_revetment_meshes(source,bag_meshes)
 _batch_revetment_bags(node,bag_meshes)

func _collect_revetment_meshes(node:Node,meshes:Array[MeshInstance3D]) -> void:
 if node is MeshInstance3D:meshes.append(node)
 for child in node.get_children():_collect_revetment_meshes(child,meshes)

func _batch_revetment_bags(parent:Node3D,meshes:Array[MeshInstance3D]) -> void:
 # One material, ordered triangles, no index/vertex optimisation or shape change.
 var tool=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 var material:Material=meshes[0].mesh.surface_get_material(0)
 for source in meshes:
  assert(source.mesh.get_surface_count()==1 and source.mesh.surface_get_material(0)==material)
  var chain:Array[Transform3D]=[];var cursor:Node3D=source
  while cursor!=parent:
   chain.append(cursor.transform);cursor=cursor.get_parent()
  chain.reverse();var world=parent.transform
  for transform in chain:world=world*transform
  tool.append_from(source.mesh,0,world)
 tool.set_material(material)
 var batch=MeshInstance3D.new();batch.name="RevetmentSandbags";batch.mesh=tool.commit()
 parent.add_child(batch);parent.move_child(batch,0)
 # Authored placements are absolute world-space. Top-level avoids a second
 # float transform and preserves existing baked world vertices exactly.
 batch.top_level=true;batch.transform=Transform3D.IDENTITY
 for source in meshes:source.free()
