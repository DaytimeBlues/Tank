class_name TankArenaView
extends Node3D

## Local opt-in; absent means original crowns.
var developer_cosmo_crowns: bool = read_developer_crown_flag()
var _developer_crown_cache: Dictionary = {}

var source_data: Dictionary
var terrain_chunks := 0
var bridge_count := 0
var tree_count := 0
var base_labels: Dictionary = {}
var base_rings: Dictionary = {}
var _ring_views: Dictionary = {}
var _active_sign_bounds: Dictionary = {}
# Authoritative rate in backend/src/capture.mjs; ETA assumes occupancy stays fixed.
const CAPTURE_RATE := 0.08
const NEUTRAL_RING := Color("e1d49a")
const BLUE_RING := Color("79b8f5")
const RED_RING := Color("f08c79")

func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result

func box_at(center: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = center
	add_child(instance)
	return instance

func build_crossing_barrel(arch: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, arch.indices.size(), 3):
		var triangle := PackedVector3Array()
		for j in [0,2,1]:
			var n := int(arch.indices[i+j])*3
			triangle.append(Vector3(arch.vertices[n],arch.vertices[n+1],arch.vertices[n+2]))
		var normal := (triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()
		for vertex in triangle:
			st.set_normal(normal)
			st.add_vertex(vertex)
	var shell := MeshInstance3D.new()
	shell.name = arch.id
	shell.mesh = st.commit()
	var masonry: ShaderMaterial = preload("res://assets/materials/bridge_stone/bridge_stone.tres").duplicate()
	masonry.set_shader_parameter("arch_face", true)
	shell.material_override = masonry
	add_child(shell)

# An open, opaque ribbon reads light against the ground without a second pass,
# translucent fill, light, or per-frame pulse. Its backbone is the capture radius.
# Blue has six long arcs; Red has six pairs (a long arc and a short one).
func _owned_halo(radius: float, paired: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for sector in range(6):
		var start := float(sector) * TAU / 6.0
		if paired:
			_append_halo_arc(vertices, indices, radius, start, deg_to_rad(22.0))
			_append_halo_arc(vertices, indices, radius, start + deg_to_rad(28.0), deg_to_rad(11.0))
		else:
			_append_halo_arc(vertices, indices, radius, start, deg_to_rad(39.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _append_halo_arc(vertices: PackedVector3Array, indices: PackedInt32Array, radius: float, start: float, sweep: float) -> void:
	# Point tips, a shallow ridge and real gaps leave the centre and ground open.
	var first := vertices.size()
	var lift := Vector3.UP * 0.44  # +0.08m existing ring anchor = 0.52m above base.
	vertices.append(Vector3(cos(start), 0, sin(start)) * radius + lift)
	for step in range(1, 4):
		var fraction := float(step) / 4.0
		var angle := start + sweep * fraction
		var radial := Vector3(cos(angle), 0, sin(angle))
		var taper := sin(PI * fraction)
		var center := radial * radius + lift
		vertices.append(center - radial * 0.20 * taper)
		vertices.append(center + Vector3.UP * 0.12 * taper)
		vertices.append(center + radial * 0.20 * taper)
	vertices.append(Vector3(cos(start + sweep), 0, sin(start + sweep)) * radius + lift)
	# Two bevels share the ridge; 12 triangles per arc. The material is two-sided.
	for i in [0,1,2, 0,2,3, 1,4,5, 1,5,2, 2,5,6, 2,6,3,
			4,7,8, 4,8,5, 5,8,9, 5,9,6, 7,10,8, 8,10,9]:
		indices.append(first + i)

func _apply_ring_owner(id: String, owner: String) -> void:
	if not base_rings.has(id): return
	var color := BLUE_RING if owner == "blue" else RED_RING if owner == "red" else NEUTRAL_RING
	var surface: StandardMaterial3D = base_rings[id]
	if surface.albedo_color == color: return
	surface.albedo_color = color
	if _ring_views.has(id):
		var view: Dictionary = _ring_views[id]
		view.node.mesh = view.shapes.get(owner, view.shapes.neutral)

func build(data: Dictionary) -> void:
	source_data = data
	var depot = load("res://scripts/depot_landmark_view.gd").new()
	depot.name = "DepotLandmarks"
	depot.build(data)
	add_child(depot)
	var roadside = load("res://scripts/roadside_cover_view.gd").new()
	roadside.name = "RoadsideCover"
	roadside.build(data)
	add_child(roadside)
	for chunk in data.chunks:
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var normals := PackedVector3Array()
		for i in range(0, chunk.vertices.size(), 3):
			vertices.append(Vector3(chunk.vertices[i], chunk.vertices[i+1], chunk.vertices[i+2]))
			colors.append(Color(chunk.colors[i], chunk.colors[i+1], chunk.colors[i+2]))
			normals.append(Vector3.ZERO)
		var indices := PackedInt32Array()
		var stone_indices := PackedInt32Array()
		for i in range(0, chunk.indices.size(), 3):
			var a: int = chunk.indices[i]
			var b: int = chunk.indices[i+1]
			var c: int = chunk.indices[i+2]
			var normal := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).normalized()
			if normal.y < 0:
				normal = -normal
			for index in [a,b,c]:
				normals[index] += normal
			# Godot's front-face order is the reverse of the source Three mesh.
			var bridge_top_triangle := false
			for bridge in data.bridges:
				var on_top := true
				for index in [a,b,c]:
					var v: Vector3 = vertices[index]
					on_top = on_top and absf(v.y-bridge.top) < 0.001 and absf(v.x-bridge.x) <= bridge.w/2.0 and absf(v.z-bridge.z) <= bridge.d/2.0
				bridge_top_triangle = bridge_top_triangle or on_top
			if bridge_top_triangle:
				stone_indices.append_array(PackedInt32Array([a,c,b]))
			else:
				indices.append_array(PackedInt32Array([a,c,b]))
		for i in range(normals.size()):
			normals[i] = normals[i].normalized()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := material(Color.WHITE)
		mat.vertex_color_use_as_albedo = true
		mesh.surface_set_material(0, mat)
		if not stone_indices.is_empty():
			arrays[Mesh.ARRAY_INDEX] = stone_indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(1, preload("res://assets/materials/bridge_stone/bridge_stone.tres"))
		var instance := MeshInstance3D.new()
		instance.name = chunk.id
		instance.mesh = mesh
		add_child(instance)
		terrain_chunks += 1
	for bridge in data.bridges:
		var deck := box_at(Vector3(bridge.x, bridge.top-bridge.thickness/2.0, bridge.z), Vector3(bridge.w,bridge.thickness,bridge.d),Color("a89c72"))
		deck.material_override = preload("res://assets/materials/bridge_stone/bridge_stone.tres")
		for x in [-28.0,0.0,28.0]:
			for side in [-1.0,1.0]:
				box_at(Vector3(x,bridge.top+0.015,bridge.z+side*6.7),Vector3(2.0,0.025,0.35),Color("e4d69a"))
		bridge_count += 1
	for b in data.get("shoulders",[]):
		var coping := box_at(Vector3(b.x,b.top-b.thickness/2.0,b.z),Vector3(b.w,b.thickness,b.d),Color("afa897"))
		coping.name=b.id
		var cut: ShaderMaterial=preload("res://assets/materials/bridge_stone/bridge_stone.tres").duplicate()
		cut.set_shader_parameter("stone_colour",Color("8c887b"))
		coping.material_override=cut
	for arch in data.get("arches",[]):
		build_crossing_barrel(arch)
	var water_mesh := box_at(Vector3(0,data.water.y-0.025,0),Vector3(data.water.w,0.05,data.size),Color("365f63"))
	water_mesh.set_meta("river_surface",true)
	for tree in data.trees:
		var trunk := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = tree.radius*0.65
		trunk_mesh.bottom_radius = tree.radius
		trunk_mesh.height = tree.trunkHeight
		trunk_mesh.radial_segments = 6
		trunk.mesh = trunk_mesh
		trunk.material_override = material(Color("554a31"))
		trunk.position = Vector3(tree.x,tree.y+tree.trunkHeight/2.0,tree.z)
		add_child(trunk)
		var crown := MeshInstance3D.new()
		crown.set_meta("original_tree_crown",true)
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = tree.crown
		crown_mesh.height = tree.crown*2.4
		crown_mesh.radial_segments = 6
		crown_mesh.rings = 3
		crown.mesh = fit_developer_crown(crown_mesh) if developer_cosmo_crowns else crown_mesh
		crown.material_override = material(Color("486534"))
		crown.position = Vector3(tree.x,tree.y+tree.trunkHeight+tree.crown*0.45,tree.z)
		add_child(crown)
		tree_count += 1
	var shape_cache := {}  # Shared once per distinct capture radius, never built on state changes.
	for base in data.bases:
		var radius := float(base.radius)
		if not shape_cache.has(radius):
			var neutral := TorusMesh.new()
			neutral.inner_radius = radius - 0.34
			neutral.outer_radius = radius + 0.34
			neutral.rings = 24
			neutral.ring_segments = 4
			shape_cache[radius] = {"neutral": neutral, "blue": _owned_halo(radius, false), "red": _owned_halo(radius, true)}
		var ring := MeshInstance3D.new()
		ring.mesh = shape_cache[radius].neutral
		# A projected objective cue is not a physical object casting a shadow.
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.material_override = material(NEUTRAL_RING,true)
		ring.position = Vector3(base.x,base.y+0.08,base.z)
		add_child(ring)
		base_rings[str(base.id)] = ring.material_override
		_ring_views[str(base.id)] = {"node": ring, "shapes": shape_cache[radius]}
		var label := Label3D.new()
		label.text = "%s · %s" % [base.id,base.name]
		label.position = Vector3(base.x,base.y+4.0,base.z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 42
		label.pixel_size = 0.024
		label.no_depth_test = false
		add_child(label)
		base_labels[str(base.id)] = label


# Keep nearby objective signs legible without covering the tank/terrain.
# Scale only down: distant labels retain their existing depth/occlusion behaviour.
func update_label_sizes(camera: Camera3D, viewport_height: float) -> void:
	if camera == null or viewport_height <= 0.0: return
	var units_per_depth := 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / viewport_height
	for id in base_labels:
		var label: Label3D = base_labels[id]
		var depth := -camera.to_local(label.global_position).z
		if depth <= 0.1:
			label.visible = false
			continue
		label.visible = true
		# A billboard's culling AABB is a cube. Its height is not the text height.
		var bounds: Vector2
		if _active_sign_bounds.has(id):
			bounds = _active_sign_bounds[id]
		else:
			var box := label.get_aabb().size
			bounds = Vector2(box.x,box.y)
		var maximum_width := 220.0 * units_per_depth * depth
		var maximum_height := 48.0 * units_per_depth * depth
		var factor := minf(1.0, minf(maximum_width / maxf(bounds.x,0.001), maximum_height / maxf(bounds.y,0.001)))
		label.scale = Vector3.ONE * factor

func _process(_delta: float) -> void:
	update_label_sizes(get_viewport().get_camera_3d(),get_viewport().get_visible_rect().size.y)

func retire_objectives() -> void:
	_active_sign_bounds.clear()
	for base in source_data.get("bases",[]):
		if base_labels.has(str(base.id)):
			var label: Label3D = base_labels[str(base.id)]
			label.text = "%s - %s\nState unavailable" % [str(base.id),str(base.get("name",""))]
			label.modulate = Color("aaaaaa")
			if _ring_views.has(str(base.id)): _ring_views[str(base.id)].node.hide()
			_apply_ring_owner(str(base.id), "neutral")

# Fixed red-to-blue rail keeps the cursor stable when the capturing side reverses.
func capture_rail(base: Dictionary) -> String:
	if not base.has_all(["progress","net","blue","red","contested"]): return ""
	var value := float(base.progress)
	var net := int(base.net)
	if not is_finite(value) or absf(value)>1 or net!=int(base.blue)-int(base.red): return ""
	var contested := bool(base.contested)
	if ((value==1 and net>=0) or (value==-1 and net<=0)) and not (contested and net==0): return ""
	if net==0 and not contested and value==0 and base.get("owner","neutral")=="neutral": return ""
	var cursor := clampi(roundi((value+1)*5),0,10)
	var rail := "R ["+"─".repeat(cursor)+"◆"+"─".repeat(10-cursor)+"] B"
	if net==0: return rail+"   Paused"
	var seconds := ceili((1.0-signi(net)*value)/(CAPTURE_RATE*absi(net))-0.000001)
	return rail+"   ~%ds"%maxi(1,seconds)

# The world sign gives identity, current owner and direction; the nearby field
# card alone carries the progress rail's conditional ETA and local instructions.
func _world_activity(base: Dictionary) -> String:
	var net_value: Variant = base.get("net")
	var progress_value: Variant = base.get("progress",0)
	var contested: bool = base.get("contested",false)
	var fallback := "Contested" if contested else ""
	if not (net_value is int or net_value is float) or not is_finite(float(net_value)) or net_value!=floorf(net_value): return fallback
	if not (progress_value is int or progress_value is float) or not is_finite(float(progress_value)) or absf(progress_value)>1: return fallback
	var net := int(net_value)
	var progress := float(progress_value)
	var advancing := (net>0 and progress<1) or (net<0 and progress> -1)
	if contested:
		var blue: Variant=base.get("blue")
		var red: Variant=base.get("red")
		if not base.has("progress") or not (blue is int or blue is float) or not (red is int or red is float): return fallback
		if not is_finite(float(blue)) or not is_finite(float(red)) or blue<=0 or red<=0 or blue!=floorf(blue) or red!=floorf(red) or net!=blue-red: return fallback
		if net==0: return "Contested · Paused"
		var team := "Blue" if net>0 else "Red"
		return "Contested · %s %s" % [team,"gaining" if advancing else "holding"]
	if advancing: return "Blue taking" if net>0 else "Red taking"
	if net==0 and absf(progress)>0 and absf(progress)<1 and base.has_all(["blue","red"]) and base.blue==0 and base.red==0: return "Capture paused"
	return ""

func update_bases(bases: Array, frozen: bool = false) -> void:
	for base in bases:
		if base_labels.has(str(base.id)):
			var label: Label3D = base_labels[str(base.id)]
			var owner_text := "Blue holds" if base.owner == "blue" else "Red holds" if base.owner == "red" else "Neutral"
			var activity := "" if frozen else _world_activity(base)
			if _ring_views.has(str(base.id)) and not _ring_views[str(base.id)].node.visible: _ring_views[str(base.id)].node.show()
			_apply_ring_owner(str(base.id), str(base.owner))
			var caption := "%s - %s\n%s" % [str(base.id),str(base.get("name","")),owner_text] if activity.is_empty() else "%s %s · %s\n%s" % [str(base.id),str(base.get("name","")),owner_text,activity]
			if label.text != caption:
				label.text = caption
				if activity.is_empty():
					_active_sign_bounds.erase(str(base.id))
				else:
					# Shape once at a text transition, not once per label per frame.
					# Font metrics are available immediately; billboard mesh updates defer.
					var font := label.font if label.font else ThemeDB.fallback_font
					var plane := font.get_multiline_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size)
					plane.y += label.line_spacing
					_active_sign_bounds[str(base.id)] = (plane + Vector2.ONE*2.0*label.outline_size)*label.pixel_size
			var tint := Color("85c6ed") if base.owner == "blue" else Color("ee9980") if base.owner == "red" else Color("eee6ce")
			if label.modulate != tint: label.modulate = tint

func read_developer_crown_flag() -> bool:
	var value: Variant = ProjectSettings.get_setting("debug/tank/cosmo_crowns",false)
	return typeof(value)==TYPE_BOOL and value

func fit_developer_crown(original: SphereMesh) -> Mesh:
	var key := Vector2(original.radius,original.height)
	if _developer_crown_cache.has(key):return _developer_crown_cache[key]
	if not ResourceLoader.exists("res://assets/experimental_cosmo/crown_mesh.tres"):return original
	var donor := load("res://assets/experimental_cosmo/crown_mesh.tres") as ArrayMesh
	if donor == null or donor.get_surface_count() != 1:
		push_warning("Developer crown unavailable; retaining original.")
		return original
	var proof := HashingContext.new()
	proof.start(HashingContext.HASH_SHA256)
	proof.update(var_to_bytes(donor.surface_get_arrays(0)))
	if proof.finish().hex_encode() != "537c725220c3540e2986c563ac2f9c37dac27ccb179395897dea0bd2591da429":
		push_warning("Developer crown identity mismatch; retaining original.")
		return original
	var donor_vertices: PackedVector3Array = donor.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if donor_vertices.is_empty():return original
	var source := AABB(donor_vertices[0],Vector3.ZERO)
	for point in donor_vertices:
		if not point.is_finite():return original
		source = source.expand(point)
	if not source.size.is_finite() or source.size.x <= 0 or source.size.y <= 0 or source.size.z <= 0:
		return original
	var target := original.get_aabb()
	var uniform := minf(target.size.x/source.size.x, minf(target.size.y/source.size.y,target.size.z/source.size.z))
	var offset := target.get_center()-source.get_center()*uniform
	var arrays := donor.surface_get_arrays(0).duplicate(true)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(vertices.size()):
		vertices[i] = vertices[i]*uniform+offset
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var fitted := ArrayMesh.new()
	fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_developer_crown_cache[key] = fitted
	return fitted
