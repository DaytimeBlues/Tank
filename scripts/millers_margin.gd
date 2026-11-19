extends Node3D
## A few broken field-margin drifts, not another full-map detail layer.
## Reuses the project's farm-verge blade palette and golden-angle construction.
const POINTS := "res://data/millers_margin_points.json"
const CULL_M := 56.0
const CELL_M := 16.0

func _ready() -> void:
	name = "MillersMargin"
	var points: Variant = JSON.parse_string(FileAccess.get_file_as_string(POINTS))
	if not points is Array or points.is_empty() or points.size() > 400:
		return
	var mesh := _stool()
	var cells := {}
	for p: Array in points:
		var key := Vector2i(floori(float(p[0])/CELL_M), floori(float(p[2])/CELL_M))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(p)
	for key: Vector2i in cells:
		var centre := Vector3((key.x+.5)*CELL_M, 0, (key.y+.5)*CELL_M)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = cells[key].size()
		for i in mm.instance_count:
			var p: Array = cells[key][i]
			var yaw := Basis(Vector3.UP, p[5]).scaled(Vector3(p[6],p[7],p[6]))
			# Shear root plane to the measured terrain slope; keep blades growing up.
			var ground := Basis(Vector3(1,p[3],0), Vector3.UP, Vector3(0,p[4],1))
			mm.set_instance_transform(i, Transform3D(ground*yaw, Vector3(p[0],p[1],p[2])-centre))
			mm.set_instance_color(i, Color.WHITE.lerp(Color(.79,.81,.64), p[8]))
		var node := MultiMeshInstance3D.new()
		node.name = "Margin_%d_%d" % [key.x,key.y]
		node.position = centre
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = CULL_M
		node.visibility_range_end_margin = 4.0 # hysteresis; no blended transparency
		add_child(node)
	set_meta("tuft_count", points.size())

func _stool() -> ArrayMesh:
	# Asymmetric bent leaves, not eleven identical radial spikes. One shared
	# opaque material; no alpha-card overdraw, textures, animation or per-frame work.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 7:
		var a := i*2.39996
		var dir := Vector3(cos(a),0,sin(a))
		var side := Vector3(-dir.z,0,dir.x)
		var root := dir*(.038+.025*(i%4))
		var width := .022+.007*(i%3)
		var h := .20+.046*(i%5)
		var knee := root+dir*(.042+.012*(i%2))+Vector3.UP*h*.59
		var tip := root+dir*(.11+.033*(i%4))+Vector3(.045,h,.016)
		var base_tint := Color("445233")
		var mid_tint := Color("79804d") if i%3 else Color("818358")
		var tip_tint := Color("b0a675") if i%3 == 0 else Color("939961")
		for v in [root-side*width,root+side*width,knee+side*width*.6]:
			st.set_color(mid_tint if v.y>0 else base_tint)
			st.add_vertex(v)
		for v in [root-side*width,knee+side*width*.6,tip]:
			st.set_color(tip_tint if v==tip else (mid_tint if v.y>0 else base_tint))
			st.add_vertex(v)
	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(material)
	return st.commit()
