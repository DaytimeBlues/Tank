class_name AcceptedGunGuide
extends Node3D
# Indicates accepted resting barrel direction ONLY: no raycast/hit/clearance prediction.
const TankView=preload("res://scripts/tank_view.gd")
var beam:MeshInstance3D
var distance_metres:=5.0
var origin:=Vector3.ZERO
var direction:=Vector3.FORWARD
func _init():
	beam=MeshInstance3D.new()
	var mesh=BoxMesh.new();mesh.size=Vector3(.18,.18,.08);beam.mesh=mesh
	var material=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("e9bb62");beam.material_override=material
	beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	visible=false
func update_from_visual(view:Variant,is_own:bool,alive:bool)->void:
	visible=false
	if not is_own or not alive:return
	if not is_instance_valid(view) or not (view is TankView):return
	if not view.is_inside_tree() or not is_instance_valid(view.model) or not is_instance_valid(view.barrel):return
	var muzzle=view.model.find_child("Muzzle",true,false) as Node3D
	if not is_instance_valid(muzzle):return
	# All five verified assets put Muzzle beside Barrel under BarrelPitch, so recoil does NOT move the socket.
	if muzzle.get_parent()!=view.barrel.get_parent():return
	origin=muzzle.global_position
	direction=muzzle.global_basis.z.normalized()
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared()<.99:return
	global_position=origin
	look_at(origin+direction,Vector3.UP)
	# Compact direction reticle, not a laser beam or hit prediction.
	beam.position=Vector3(0,0,-distance_metres)
	visible=true
