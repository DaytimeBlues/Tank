extends RefCounted
static func create(data:Dictionary)->ShaderMaterial:
 var segments=PackedVector4Array()
 assert(data.get("roads",[]).size()<=32,"Road wear needs bounded segment budget")
 for r in data.get("roads",[]):segments.append(Vector4(r.a.x,r.a.z,r.b.x,r.b.z))
 var count=segments.size()
 while segments.size()<32:segments.append(Vector4.ZERO)
 var material=ShaderMaterial.new();material.shader=load("res://assets/ground_road_wear.gdshader")
 material.set_shader_parameter("road_segments",segments);material.set_shader_parameter("road_count",count)
 var bases=PackedVector4Array()
 assert(data.get("bases",[]).size()<=7,"Field finish uses seven-base exclusion contract")
 for b in data.get("bases",[]):bases.append(Vector4(b.x,b.z,b.radius,0))
 material.set_shader_parameter("base_count",bases.size())
 while bases.size()<7:bases.append(Vector4.ZERO)
 material.set_shader_parameter("base_circles",bases)
 var roots=PackedVector4Array()
 for t in data.get("trees",[]):
  if t.x < -115 and t.z > -5 and t.z < 150:roots.append(Vector4(t.x,t.z,2.4,0))
 assert(roots.size()<=16,"Western field root-island budget")
 material.set_shader_parameter("root_count",roots.size())
 while roots.size()<16:roots.append(Vector4.ZERO)
 material.set_shader_parameter("root_circles",roots)
 return material
static func create_for_chunk(data:Dictionary,chunk:Dictionary)->ShaderMaterial:
 var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
 for i in range(0,chunk.vertices.size(),3):
  lo=lo.min(Vector2(chunk.vertices[i],chunk.vertices[i+2]));hi=hi.max(Vector2(chunk.vertices[i],chunk.vertices[i+2]))
 var selected=[]
 for r in data.get("roads",[]):
  var a=Vector2(r.a.x,r.a.z);var b=Vector2(r.b.x,r.b.z)
  if maxf(a.x,b.x)>=lo.x-12 and minf(a.x,b.x)<=hi.x+12 and maxf(a.y,b.y)>=lo.y-12 and minf(a.y,b.y)<=hi.y+12:selected.append(r)
 var result=create({"roads":selected,"bases":data.get("bases",[]),"trees":data.get("trees",[])})
 if lo.x<=-9 and hi.x>=-29 and lo.y<=40 and hi.y>=35:
  for item in data.get("districtMeshes",[]):
   if not item.has("quay"):continue
   var path=item.quay.servicePath;var segments:=PackedVector4Array()
   for i in range(path.size()-1):
    segments.append(Vector4(path[i][0],path[i][1],path[i+1][0],path[i+1][1]))
   if segments.size()==5:
    result.set_shader_parameter("quay_footpath",segments)
    result.set_shader_parameter("has_quay_path",true)
 return result
