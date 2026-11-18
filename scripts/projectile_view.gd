extends Node3D
# Visible short shells follow server positions. Extrapolation is bounded to 100ms.
const CAP := 32
var nodes: Array[MeshInstance3D] = []
var samples: Array = []
var sampled := 0.0
var seen: Dictionary = {}
var seeded := false
var latest_impact_time := -INF
var fx: TankAcceptedShotEffects
const ImpactAudio = preload("res://scripts/bounded_impact_audio.gd")
var impact_audio = ImpactAudio.new()
func _ready() -> void:
 var mesh := SphereMesh.new()
 mesh.radius=0.13; mesh.height=0.65; mesh.radial_segments=8; mesh.rings=4
 var material := StandardMaterial3D.new()
 # Keep the short physical silhouette readable in shade; no beam, light or trail.
 material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.albedo_color=Color("ffd28a")
 for i in range(CAP):
  var n := MeshInstance3D.new(); n.mesh=mesh; n.material_override=material
  n.visible=false; n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(n); nodes.append(n)
 impact_audio.initialize(self,load("res://assets/effects/cannon_boom.wav"))
func clear() -> void:
 samples.clear(); seen.clear(); seeded=false; latest_impact_time=-INF
 for n in nodes: n.hide()
 impact_audio.clear()
func boom(at: Vector3) -> void:
 impact_audio.play_at(at)
func accept(snapshot: Dictionary, now: float) -> void:
 var server_time:=float(snapshot.get("time",0))
 if not is_finite(server_time) or server_time<latest_impact_time:return
 latest_impact_time=server_time
 samples=snapshot.get("projectiles",[]).slice(0,CAP);sampled=now
 for prior in seen.keys():
  if server_time-float(seen[prior])>=1.0:seen.erase(prior)
 for impact in snapshot.get("impacts",[]).slice(0,CAP):
  if not impact is Dictionary or not impact.has("id") or not impact.has("time"):continue
  var id:=int(impact.id);var stamp:=float(impact.time)
  if id<0 or not is_finite(stamp) or stamp>server_time or server_time-stamp>=1.0 or seen.has(id):continue
  if not impact.has("x") or not impact.has("y") or not impact.has("z"):continue
  var at:=Vector3(float(impact.x),float(impact.y),float(impact.z))
  if not at.is_finite():continue
  # Remember across temporarily missing receipts, including duplicates in one
  # packet. Do not evict a recent ID just to replay an untrusted over-budget one.
  if seen.size()>=CAP*2:continue
  seen[id]=stamp
  if seeded and server_time-stamp<0.35:
   fx.present_impact(impact,now);boom(at)
 seeded=true
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
