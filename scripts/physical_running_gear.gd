extends RefCounted
# Presentation only: read the same accumulated accepted-pose travel as the existing donor wheels.
# One skin per existing hull (or donor track side), no new render surfaces or per-link mesh instances.
const SPECS = preload("res://data/running_gear_rig.json")
var wheels: Array = []
var belts: Array = []
var generation := -1
var previous := Vector2.ZERO
var seeded := false

func bind(model: Node3D, id: String) -> bool:
	wheels.clear()
	belts.clear()
	reset_history()
	generation = -1
	var bone_map := {}
	for sk: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
		for i in sk.get_bone_count():
			bone_map[String(sk.get_bone_name(i))] = [sk, i]
	var tracks := {-1: [], 1: []}
	for entry: Dictionary in SPECS.data[id]:
		if not bone_map.has(entry.name): return false
		var binding: Array = bone_map[entry.name]
		var sk: Skeleton3D = binding[0]
		var i: int = binding[1]
		var c := Vector3(entry.c[0], entry.c[1], entry.c[2])
		if sk.get_bone_rest(i).origin.distance_to(c) > 0.001: return false
		if entry.kind == "W":
			wheels.append({"sk":sk, "i":i, "x":c.x, "r":float(entry.r), "phase":0.0})
		else:
			tracks[int(entry.side)].append({"sk":sk,"i":i,"c":c,"s":float(entry.s),"a":float(entry.a),"len":float(entry.length),"x":float(entry.get("x",c.x))})
	for side: int in [-1, 1]:
		var links: Array = tracks[side]
		links.sort_custom(func(a,b): return a.s < b.s)
		if links.is_empty(): return false
		var stations:=PackedFloat64Array()
		var centres:=PackedVector3Array()
		var angles:=PackedFloat64Array()
		var indices:=PackedInt32Array()
		for link: Dictionary in links:
			stations.append(link.s)
			angles.append(link.a)
			centres.append(link.c)
			indices.append(link.i)
		stations.append(links[0].len)
		angles.append(angles[0])
		centres.append(centres[0])
		belts.append({"sk":links[0].sk, "idx":indices,"s":stations,"c":centres,"a":angles,"len":links[0].len,"x":links[0].x,"phase":0.0})
	return true

func reset_history() -> void:
	seeded = false

func consume(metres: Vector2, epoch: int, half_width: float, active: bool) -> void:
	if epoch < generation: return
	if not active or not metres.is_finite() or half_width <= 0.0:
		seeded=false
		generation=epoch
		return
	var advance_allowed := seeded and epoch == generation
	var d := metres - previous
	previous=metres
	generation=epoch
	seeded=true
	if not advance_allowed or d == Vector2.ZERO: return
	var straight := 0.5 * (d.x + d.y)
	var yaw := (d.x - d.y) / (2.0 * half_width)
	for w: Dictionary in wheels:
		var angle:=wrapf(float(w.phase)+(straight-float(w.x)*yaw)/float(w.r),-PI,PI)
		w.phase=angle
		w.sk.set_bone_pose_rotation(w.i,Quaternion(Vector3.RIGHT,angle))
	for belt: Dictionary in belts:
		var length:float=belt.len
		# Both authored loops run forward on the bottom: decrease station in forward travel.
		var phase:=fposmod(float(belt.phase)-(straight-float(belt.x)*yaw),length)
		belt.phase=phase
		var ss:PackedFloat64Array=belt.s
		var cc:PackedVector3Array=belt.c
		var aa:PackedFloat64Array=belt.a
		var ids:PackedInt32Array=belt.idx
		var sk:Skeleton3D=belt.sk
		var j:=maxi(0,mini(ids.size()-1,ss.bsearch(phase,false)-1))
		for n in ids.size():
			var station:=ss[n]+phase
			if station >= length: station-=length
			if station < ss[j]: j=0
			while j+1 < ids.size() and station>=ss[j+1]: j+=1
			var fraction:=(station-ss[j])/(ss[j+1]-ss[j])
			sk.set_bone_pose_position(ids[n],cc[j].lerp(cc[j+1],fraction))
			sk.set_bone_pose_rotation(ids[n],Quaternion(Vector3.RIGHT,lerp_angle(aa[j],aa[j+1],fraction)-aa[n]))

