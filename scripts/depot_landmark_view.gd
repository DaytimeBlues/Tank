extends Node3D
# Opaque closed service garage. Every mesh stays inside the shared solid box.
# Painted shutters are deliberately closed: no decorative doorway implying entry.
func piece(parent:Node3D, label:String, center:Vector3, size:Vector3, colour:String) -> void:
 var n=MeshInstance3D.new();n.name=label
 var m=BoxMesh.new();m.size=size;n.mesh=m
 var mat=StandardMaterial3D.new();mat.albedo_color=Color(colour);mat.roughness=.92
 n.material_override=mat;n.position=center;parent.add_child(n)
 if label in ["Masonry","RoofCap","Shutter"]:
  n.material_override=null
  load("res://scripts/building_finish.gd").apply(n,0,0 if label=="Masonry" else 2,colour)
func build(data:Dictionary) -> void:
 for b in data.get("landmarks",[]):
  var garage=Node3D.new();garage.name=str(b.id);garage.position=Vector3(b.x,b.y,b.z);add_child(garage)
  # Full enclosing masonry shell matches authoritative dimensions exactly.
  piece(garage,"Masonry",Vector3(0,-.09,0),Vector3(b.w-.12,b.h-.18,b.d-.12),"a89b75")
  piece(garage,"RoofCap",Vector3(0,b.h/2-.12,0),Vector3(b.w,.18,b.d),"5b6158")
  piece(garage,"Foundation",Vector3(0,-b.h/2+.22,0),Vector3(b.w,.44,b.d),"686b60")
  # Front panels sit flush, not beyond the collision face.
  for bay in [-1.0,1.0]:
   piece(garage,"Shutter",Vector3(b.w/2-.038,-.35,bay*1.85),Vector3(.036,3.4,3.05),"405b52")
   for slat in 10:
    piece(garage,"ShutterSlat",Vector3(b.w/2-.019,-1.85+slat*.30,bay*1.85),Vector3(.018,.035,3.05),"718176")
   piece(garage,"Lintel",Vector3(b.w/2-.04,1.45,bay*1.85),Vector3(.08,.20,3.4),"d3c59b")
   piece(garage,"DoorHandle",Vector3(b.w/2-.006,-.65,bay*1.85),Vector3(.012,.10,.38),"d8c996")
  # Roof seams and pale clerestory windows break up the long solid silhouette.
  for seam in 9:
   piece(garage,"RoofSeam",Vector3(-5.3+seam*1.3,b.h/2-.025,0),Vector3(.045,.05,b.d-.3),"85897a")
  for side in [-1.0,1.0]:
   for window in 3:
    piece(garage,"WindowFrame",Vector3(-3.5+window*3.5,.75,side*(b.d/2-.025)),Vector3(2,.9,.028),"d3c59b")
    piece(garage,"WindowGlass",Vector3(-3.5+window*3.5,.75,side*(b.d/2-.006)),Vector3(1.75,.65,.012),"445b60")

