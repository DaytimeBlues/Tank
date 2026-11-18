extends RefCounted
# Presentation-only visibility against canonical district triangles. No physics,
# input, weapon or terrain mutation. Static data is rebuilt with each arena.
const CLEARANCE=0.45
const FRAME_RADIUS=0.35
var groups:Array=[]
var triangle_checks=0
var last_blocker=""
var pre_triangle_checks=0
var post_triangle_checks=0
var total_triangle_checks=0
var last_rate=4.0
var last_hard_correction=0.0
var pre_blocker=""
func update(target:Vector3,current:Vector3,desired:Vector3,delta:float,seeded:bool)->Vector3:
 var safe_desired=resolve(target,desired,4.0)
 pre_triangle_checks=triangle_checks;pre_blocker=last_blocker
 var inward=safe_desired!=desired and safe_desired.distance_squared_to(target)<current.distance_squared_to(target)
 last_rate=8.0 if inward else 4.0
 var smoothed=current.lerp(safe_desired,1.0-exp(-last_rate*delta)) if seeded else safe_desired
 var result=resolve(target,smoothed)
 post_triangle_checks=triangle_checks;total_triangle_checks=pre_triangle_checks+post_triangle_checks
 last_hard_correction=result.distance_to(smoothed)
 return result
func build(data:Dictionary)->void:
 groups.clear()
 for p in data.get("districtMeshes",[]):
  var points=PackedVector3Array();var bounds=AABB()
  for i in range(0,p.vertices.size(),3):
   var point=Vector3(p.vertices[i],p.vertices[i+1],p.vertices[i+2])
   bounds=AABB(point,Vector3.ZERO) if i==0 else bounds.expand(point)
   points.append(point)
  var triangles=PackedVector3Array()
  for index in p.indices:triangles.append(points[int(index)])
  groups.append({"id":p.id,"bounds":bounds,"triangles":triangles})
func resolve(target:Vector3,candidate:Vector3,frame_radius:float=FRAME_RADIUS)->Vector3:
 triangle_checks=0;last_blocker=""
 if not target.is_finite() or not candidate.is_finite():return target if target.is_finite() else Vector3.ZERO
 var delta=candidate-target;var length=delta.length()
 if length<.001:return candidate
 var direction=delta/length
 var right=direction.cross(Vector3.UP).normalized()
 if right.length_squared()<.1:right=Vector3.RIGHT
 var up=right.cross(direction).normalized()
 var radius=clampf(frame_radius,FRAME_RADIUS,4.0)
 var offsets=[Vector3.ZERO,right*radius,-right*radius,up*radius,-up*radius,(right+up)*radius,(right-up)*radius,(-right+up)*radius,(-right-up)*radius]
 var fraction=1.0
 for group in groups:
  if group.bounds.grow(radius*1.414214).intersects_segment(target,candidate)==null:continue
  var triangles:PackedVector3Array=group.triangles
  for offset in offsets:
   var endpoint:Vector3=candidate+offset
   if group.bounds.grow(.00001).intersects_segment(target,endpoint)==null:continue
   var ray_length=target.distance_to(endpoint)
   for i in range(0,triangles.size(),3):
    triangle_checks+=1
    var hit=Geometry3D.segment_intersects_triangle(target,endpoint,triangles[i],triangles[i+1],triangles[i+2])
    if hit==null:continue
    var hit_fraction=target.distance_to(hit)/ray_length
    if hit_fraction<fraction:fraction=hit_fraction;last_blocker=group.id
 if fraction>=1.0:return candidate
 # Safety wins if a wall is too close for ideal framing: never enforce a minimum
 # camera distance by pushing through opaque cover.
 return target+direction*maxf(0.0,length*fraction-CLEARANCE)

func framing_fov(target:Vector3,position:Vector3,current:float,delta:float,seeded:bool)->float:
 var constrained=pre_blocker!="" or last_blocker!=""
 var wanted=55.0+25.0*clampf((8.0-target.distance_to(position))/4.0,0.0,1.0) if constrained else 55.0
 # Match inward camera contraction without a lagging crop; restore the original
 # field of view smoothly as clearance returns. Open-road FOV remains exactly55.
 if not seeded or wanted>=current:return wanted
 var result=lerpf(current,wanted,1.0-exp(-4.0*delta))
 return wanted if absf(result-wanted)<.001 else result
