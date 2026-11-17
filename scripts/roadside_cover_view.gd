extends Node3D
# Visual stones remain inside shared authoritative cover cuboids.
func stone_mesh(size:Vector3,bevel:float)->ArrayMesh:
 var half=size/2;var points=[]
 for x in [-1.0,1.0]:
  for y in [-1.0,1.0]:
   for z in [-1.0,1.0]:
    var signs=Vector3(x,y,z)
    for axis in 3:
     var p=(half-Vector3.ONE*bevel)*signs;p[axis]=half[axis]*signs[axis];points.append(p)
 var vertices=PackedVector3Array();var normals=PackedVector3Array()
 for x in [-1.0,0.0,1.0]:
  for y in [-1.0,0.0,1.0]:
   for z in [-1.0,0.0,1.0]:
    var n=Vector3(x,y,z)
    if n.length_squared()==0:continue
    n=n.normalized();var mx=-INF
    for p in points:mx=maxf(mx,n.dot(p))
    var face=[];var center=Vector3.ZERO
    for p in points:
     if abs(n.dot(p)-mx)<.0001:face.append(p);center+=p
    if face.size()<3:continue
    center/=face.size()
    var u=n.cross(Vector3.UP if abs(n.y)<.9 else Vector3.RIGHT).normalized();var v=n.cross(u)
    face.sort_custom(func(a,b):return atan2((a-center).dot(v),(a-center).dot(u))<atan2((b-center).dot(v),(b-center).dot(u)))
    for i in range(1,face.size()-1):
     for p in [face[0],face[i+1],face[i]]:vertices.append(p);normals.append(n)
 var arr=[];arr.resize(Mesh.ARRAY_MAX);arr[Mesh.ARRAY_VERTEX]=vertices;arr[Mesh.ARRAY_NORMAL]=normals
 var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr);return mesh
func build(data:Dictionary):
 var mortar=StandardMaterial3D.new();mortar.albedo_color=Color("55584c");mortar.roughness=1
 var mat=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.roughness=.96
 var bricks=MultiMesh.new();bricks.transform_format=MultiMesh.TRANSFORM_3D;bricks.use_colors=true
 bricks.mesh=stone_mesh(Vector3(1,1,1),.10);bricks.instance_count=data.get("cover",[]).size()*10
 var index=0
 for b in data.get("cover",[]):
  assert(b.w>0 and b.h>0 and b.d>0)
  var wall=MeshInstance3D.new();wall.name=str(b.id)
  var box=BoxMesh.new();box.size=Vector3(b.w-.08,b.h-.02,b.d-.02);wall.mesh=box;wall.material_override=mortar
  wall.position=Vector3(b.x,b.y,b.z);add_child(wall)
  for row in 4:
   var lengths=[.5,.5] if row%2==0 else [.25,.5,.25]
   var cursor=-b.d/2
   for col in lengths.size():
    var size=Vector3(b.w,b.h/4-.012,b.d*lengths[col]-.012)
    var center=Vector3(b.x,b.y-b.h/2+(row+.5)*b.h/4,b.z+cursor+b.d*lengths[col]/2)
    cursor+=b.d*lengths[col]
    bricks.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(size),center))
    bricks.set_instance_color(index,Color("827f6d").lerp(Color("a6a08b"),float((row*7+col*3+index)%11)/14));index+=1
 var node=MultiMeshInstance3D.new();node.name="BeveledStoneFaces";node.multimesh=bricks;node.material_override=mat;add_child(node)

