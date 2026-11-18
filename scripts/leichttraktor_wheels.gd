extends RefCounted
# Cosmetic consumer of existing AcceptedTrackTravel cumulative metres/reset generation.
# No independent pose filter, interpolation, speed inference or control changes.
# Pi study reference: displacement-derived wheels; implementation is project-authored.
# Does not change materials, hierarchy, hull pose, suspension or gameplay.

var wheels: Array[Dictionary] = []
var seeded := false
var previous_metres := Vector2.ZERO
var previous_generation := -1

func bind_model(model: Node3D, visual_id: String) -> bool:
	wheels.clear()
	previous_generation = -1
	reset_history()
	if visual_id != "leichttraktor" or not is_instance_valid(model):
		return false
	if not model.basis.get_scale().is_equal_approx(Vector3.ONE): return false
	var left_count := 0
	var right_count := 0
	for child in model.find_children("Wheels*", "MeshInstance3D", true, false):
		var wheel := child as MeshInstance3D
		var named_left := str(wheel.name).begins_with("WheelsLeft")
		var named_right := str(wheel.name).begins_with("WheelsRight")
		if not named_left and not named_right:
			continue
		if wheel.mesh == null:
			wheels.clear()
			return false
		var relative := wheel.transform
		var parent := wheel.get_parent()
		while parent != model:
			if not parent is Node3D: wheels.clear();return false
			relative = parent.transform * relative
			parent = parent.get_parent()
		var bounds := wheel.get_aabb()
		var radius := maxf(bounds.size.y * relative.basis.y.length(), bounds.size.z * relative.basis.z.length()) * 0.5
		var axle := relative.basis.x.normalized().dot(Vector3.RIGHT)
		# This donor has centred circular wheels and lateral axles. Fail closed if
		# a future asset changes that contract; do not repair/reparent the import.
		if radius < 0.01 or not is_finite(radius) or absf(axle) < 0.99 or bounds.get_center().length() > 0.001:
			wheels.clear()
			return false
		wheels.append({"node": wheel, "rest": wheel.basis, "radius": radius,
			"x": relative.origin.x, "sign": signf(axle), "phase": 0.0})
		left_count += int(named_left)
		right_count += int(named_right)
	if left_count != 15 or right_count != 15:
		wheels.clear()
		return false
	return true

func reset_history() -> void:
	# Keep visible phase across a history reset, never catch up or snap to zero.
	seeded = false

func consume(metres: Vector2, generation: int, half_width: float, active: bool = true) -> void:
	if wheels.is_empty() or generation < previous_generation: return
	if not active or not metres.is_finite() or not is_finite(half_width) or half_width<=0:
		seeded=false
		previous_generation=generation
		return
	var same_generation := seeded and generation==previous_generation
	var delta := metres-previous_metres
	previous_metres=metres
	previous_generation=generation
	seeded=true
	if not same_generation: return
	# Consume the existing accepted-track result, with no second pose odometry.
	var advance := (delta.x+delta.y)*0.5
	var turn := (delta.x-delta.y)/(2.0*half_width)
	for entry in wheels:
		if not is_instance_valid(entry.node): continue
		var distance: float = advance-float(entry.x)*turn
		entry.phase=wrapf(float(entry.phase)+distance*float(entry.sign)/float(entry.radius),-PI,PI)
		entry.node.basis=entry.rest*Basis(Vector3.RIGHT,entry.phase)
