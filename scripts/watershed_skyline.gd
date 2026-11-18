extends MeshInstance3D
## A decorative watershed silhouette, beyond the 320 m arena; never a physics surface.

const SEGMENTS := 160
const RADIUS := 356.0
const FLOOR := -36.0
const CREST_INK := Color("7e929b")
const BASE_INK := Color("9ba9a6")

# Wrapped bell: avoids a separate edge case where the feature crosses angle zero.
func _landform(a: float, peak: float, width: float) -> float:
	var d := wrapf(a - peak, -PI, PI) / width
	return exp(-d * d)

func _ready() -> void:
	var strip := SurfaceTool.new()
	strip.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(SEGMENTS + 1):
		# Close with the original sample exactly, not a separate floating-point endpoint.
		var a := TAU * float(i % SEGMENTS) / SEGMENTS
		var scallops := 0.64 * sin(3.0 * a + 0.35) + 0.36 * sin(5.0 * a - 0.68)
		var shoulder := 0.60 * sin(7.0 * a + 0.8) + 0.40 * sin(11.0 * a - 1.7)
		var breakup := sin(19.0 * a + 0.5) + 0.35 * sin(31.0 * a + 1.6)
		var radius := RADIUS + 13.0 * sin(2.0 * a + 1.1) + 8.0 * sin(5.0 * a - 0.3)
		# East ridge has a broad shoulder that falls into a narrower offset saddle.
		var east_crest := 9.0 * _landform(a, -0.22, 0.34) - 7.0 * _landform(a, 0.24, 0.15)
		var crest := 20.0 + 13.0 * scallops + 6.0 * shoulder + 1.55 * breakup + east_crest
		var direction := Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		strip.set_color(Color(BASE_INK, 0.0))
		strip.add_vertex(direction + Vector3.UP * FLOOR)
		strip.set_color(Color(CREST_INK, 0.82))
		strip.add_vertex(direction + Vector3.UP * crest)
	mesh = strip.commit()
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	ink.vertex_color_use_as_albedo = true
	ink.vertex_color_is_srgb = true
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ink.render_priority = -10  # Keep the backdrop behind standard transparent world effects.
	material_override = ink
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
