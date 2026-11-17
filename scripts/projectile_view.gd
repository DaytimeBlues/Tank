extends Node3D
# Visible short shells follow server positions. Extrapolation is bounded to 100ms.
const CAP := 32
var nodes: Array[MeshInstance3D] = []
var samples: Array = []
var sampled := 0.0
var seen: Dictionary = {}
var seeded := false
var fx: TankAcceptedShotEffects
var voices: Array[AudioStreamPlayer3D] = []
var audio_index := 0
func _ready() -> void:
 var mesh := SphereMesh.new()
 mesh.radius=0.13; mesh.height=0.65; mesh.radial_segments=8; mesh.rings=4
 var material := StandardMaterial3D.new()
 material.albedo_color=Color("ecb263"); material.metallic=0.7; material.roughness=0.35
 for i in range(CAP):
  var n := MeshInstance3D.new(); n.mesh=mesh; n.material_override=material
  n.visible=false; n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(n); nodes.append(n)
 for i in range(8):
  var v := AudioStreamPlayer3D.new(); v.stream=load("res://assets/effects/cannon_boom.wav")
  v.volume_db=-20; v.max_db=-20; v.max_distance=180; v.unit_size=20
  add_child(v); voices.append(v)
func clear() -> void:
 samples.clear(); seen.clear(); seeded=false
 for n in nodes: n.hide()
 for v in voices: v.stop()
func boom(at: Vector3) -> void:
 if voices.is_empty(): return
 var v:=voices[audio_index%voices.size()]; audio_index+=1
 v.position=at; v.play()
func accept(snapshot: Dictionary, now: float) -> void:
 samples=snapshot.get("projectiles",[]).slice(0,CAP); sampled=now
 var server_time: float=float(snapshot.get("time",0))
 var current: Dictionary={}
 for impact in snapshot.get("impacts",[]).slice(0,CAP):
  var id: int=int(impact.get("id",-1)); current[id]=true
  if seeded and not seen.has(id) and server_time-float(impact.get("time",0))>=0 and server_time-float(impact.get("time",0))<0.35:
   fx.present_impact(impact,now); boom(Vector3(impact.x,impact.y,impact.z))
 seen=current; seeded=true
 update(now)
func update(now: float) -> void:
 var age:=now-sampled
 for i in range(nodes.size()):
  var n:=nodes[i]
  if i>=samples.size() or age<0 or age>0.3:
   n.hide(); continue
  var s: Dictionary=samples[i]
  var pos:=Vector3(float(s.get("x",0)),float(s.get("y",0)),float(s.get("z",0)))
  var direction:=Vector3(float(s.get("dx",0)),float(s.get("dy",0)),float(s.get("dz",0)))
  if not pos.is_finite() or not direction.is_finite(): n.hide(); continue
  n.position=pos+direction*float(s.get("speed",60))*minf(age,0.1)
  n.basis=Basis.looking_at(direction,Vector3.RIGHT if absf(direction.dot(Vector3.UP))>0.98 else Vector3.UP)*Basis(Vector3.RIGHT,PI/2) if direction.length()>0.01 else Basis.IDENTITY
  n.show()
