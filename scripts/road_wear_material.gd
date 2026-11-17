extends RefCounted
static func create(data:Dictionary)->ShaderMaterial:
 var segments=PackedVector4Array()
 assert(data.get("roads",[]).size()<=32,"Road wear needs bounded segment budget")
 for r in data.get("roads",[]):segments.append(Vector4(r.a.x,r.a.z,r.b.x,r.b.z))
 var count=segments.size()
 while segments.size()<32:segments.append(Vector4.ZERO)
 var material=ShaderMaterial.new();material.shader=load("res://assets/ground_road_wear.gdshader")
 material.set_shader_parameter("road_segments",segments);material.set_shader_parameter("road_count",count)
 return material
static func create_for_chunk(data:Dictionary,chunk:Dictionary)->ShaderMaterial:
 var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
 for i in range(0,chunk.vertices.size(),3):
  lo=lo.min(Vector2(chunk.vertices[i],chunk.vertices[i+2]));hi=hi.max(Vector2(chunk.vertices[i],chunk.vertices[i+2]))
 var selected=[]
 for r in data.get("roads",[]):
  var a=Vector2(r.a.x,r.a.z);var b=Vector2(r.b.x,r.b.z)
  if maxf(a.x,b.x)>=lo.x-9 and minf(a.x,b.x)<=hi.x+9 and maxf(a.y,b.y)>=lo.y-9 and minf(a.y,b.y)<=hi.y+9:selected.append(r)
 return create({"roads":selected})
