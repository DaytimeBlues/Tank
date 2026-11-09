class_name TankPortVisual
extends Node3D

const IDS := ["kestrel","bastion","foundry","palisade"]
var visual_id := ""
var model: Node3D
var turret: Node3D
var barrel: Node3D
var barrel_rest := Vector3.ZERO
var label: Label3D
var recoil_age := 10.0

func choose(id: String) -> void:
	assert(id in IDS)
	visual_id = id
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	var packed: PackedScene = load("res://assets/models/%s.glb" % id)
	model = packed.instantiate()
	add_child(model)
	turret = model.find_child("TurretYaw",true,false) as Node3D
	barrel = model.find_child("Barrel",true,false) as Node3D
	assert(turret != null and barrel != null)
	barrel_rest = barrel.position
	if label == null:
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.pixel_size = 0.018
		label.position = Vector3(0,3.6,0)
		add_child(label)

func apply_player(player: Dictionary, own: bool) -> void:
	if visual_id != player.visualId:
		choose(player.visualId)
	var tank: Dictionary = player.tank
	var q: Dictionary = tank.quaternion
	var basis_value := Basis(Quaternion(q.x,q.y,q.z,q.w))
	transform = Transform3D(basis_value,Vector3(tank.x,tank.y,tank.z)+basis_value*Vector3(0,-1,0))
	turret.rotation.y = tank.turret
	visible = player.health > 0
	label.text = "%s%s · %s/3" % ["YOU · " if own else "",str(player.team).to_upper(),player.health]
	label.modulate = Color("85c6ed") if player.team == "blue" else Color("ee9980")

func _process(delta: float) -> void:
	recoil_age += delta
	if barrel == null:
		return
	var amount := 0.0
	if recoil_age < 0.022:
		amount = recoil_age/0.022
	elif recoil_age < 0.28:
		amount = 1.0-(recoil_age-0.022)/0.258
	barrel.position = barrel_rest-Vector3(0,0,0.18*smoothstep(0.0,1.0,amount))
