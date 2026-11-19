class_name TankPortVisual
extends Node3D

const IDS := ["kestrel","bastion","foundry","palisade","leichttraktor"]
var visual_id := ""
var model: Node3D
var turret: Node3D
var barrel_pitch: Node3D
var barrel: Node3D
var barrel_rest := Vector3.ZERO
# One replacement material on an existing turret surface. Never a floating node.
var health_plate: MeshInstance3D
var health_ink: ShaderMaterial
var painted_health := 0
var recoil_age := 10.0

func choose(id: String) -> void:
	assert(id in IDS)
	visual_id = id
	if is_instance_valid(model):
		retire_health_paint()
		remove_child(model)
		model.queue_free()
	var packed: PackedScene = load("res://assets/models/%s.glb" % id)
	model = packed.instantiate()
	add_child(model)
	turret = model.find_child("TurretYaw",true,false) as Node3D
	barrel = model.find_child("Barrel",true,false) as Node3D
	assert(turret != null and barrel != null)
	barrel_pitch = model.find_child("BarrelPitch",true,false) as Node3D
	barrel_rest = barrel.position
	_bind_health_plate()

func _bind_health_plate() -> void:
	painted_health = 0
	health_ink = null
	health_plate = turret.get_node_or_null("Turret") as MeshInstance3D
	if health_plate == null or health_plate.mesh == null or health_plate.mesh.get_surface_count() < 1: return
	var m := health_plate.get_active_material(0) as StandardMaterial3D
	# These five approved models use a flat or single albedo-map PBR finish. Fail closed for substitutions.
	if m == null or m.resource_name != ("Material" if visual_id=="leichttraktor" else "Armor") or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.no_depth_test or m.next_pass != null or health_plate.get_surface_override_material(0) != null: return
	health_ink = ShaderMaterial.new()
	health_ink.shader = preload("res://scripts/hull_health_paint.gdshader")
	health_ink.set_shader_parameter("base_tint", m.albedo_color)
	if m.albedo_texture: health_ink.set_shader_parameter("base_map", m.albedo_texture)
	health_ink.set_shader_parameter("base_roughness", m.roughness)
	health_ink.set_shader_parameter("base_metallic", m.metallic)
	health_ink.set_shader_parameter("mesh_to_turret", health_plate.transform.basis)
	health_ink.set_shader_parameter("span", 0.60 if visual_id=="leichttraktor" else 0.96)

func retire_health_paint() -> void:
	if painted_health == 0: return
	painted_health = 0
	health_ink.set_shader_parameter("signed_health", 0)
	health_plate.set_surface_override_material(0, health_plate.mesh.surface_get_material(0))

static func _number_is(value: Variant, expected: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value == expected

# One strict seat contract governs both local observation and per-peer paint.
static func health_stamp(player: Dictionary) -> int:
	var hp: Variant = player.get("health")
	var team: Variant = player.get("team")
	if typeof(player.get("connected")) != TYPE_BOOL or not player.connected: return 0
	if not _number_is(player.get("maxHealth"),3) or not _number_is(player.get("respawnSeconds"),0): return 0
	if not (_number_is(hp,1) or _number_is(hp,2) or _number_is(hp,3)): return 0
	if team=="blue": return int(hp)
	if team=="red": return -int(hp)
	return 0

func present_health(player: Dictionary, live: bool) -> void:
	var stamp := health_stamp(player) if live and health_ink else 0
	if stamp == 0:
		retire_health_paint()
		return
	if stamp == painted_health: return
	health_ink.set_shader_parameter("signed_health",stamp)
	if painted_health == 0: health_plate.set_surface_override_material(0,health_ink)
	painted_health = stamp

func apply_player(player: Dictionary, _own: bool) -> void:
	if visual_id != player.visualId:
		choose(player.visualId)
	var tank: Dictionary = player.tank
	var q: Dictionary = tank.quaternion
	var basis_value := Basis(Quaternion(q.x,q.y,q.z,q.w))
	transform = Transform3D(basis_value,Vector3(tank.x,tank.y,tank.z)+basis_value*Vector3(0,-1,0))
	turret.rotation.y = tank.turret
	if barrel_pitch != null: barrel_pitch.rotation.x = -float(tank.get("gunPitch", 0.0))
	visible = player.health > 0

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
