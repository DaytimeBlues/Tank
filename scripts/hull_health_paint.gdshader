shader_type spatial;
render_mode cull_disabled;

// Replaces one existing, opaque PBR surface; coordinates only, no vertex/depth writes.
uniform vec4 base_tint : source_color = vec4(1.0);
uniform sampler2D base_map : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float base_roughness = 1.0;
uniform float base_metallic = 0.0;
uniform mat3 mesh_to_turret;
uniform float span = 0.96;
uniform int signed_health = 0; // Blue positive, Red negative; zero is never a health claim.
uniform vec4 blue_ink : source_color = vec4(0.60, 0.86, 1.0, 1.0);
uniform vec4 red_ink : source_color = vec4(1.0, 0.66, 0.52, 1.0);
uniform vec4 empty_ink : source_color = vec4(0.13, 0.14, 0.15, 1.0);
varying vec3 paint_pos;
varying float top_facing;
void vertex() {
	paint_pos = mesh_to_turret * VERTEX;
	top_facing = (mesh_to_turret * NORMAL).y;
}
void fragment() {
	vec3 original = base_tint.rgb * texture(base_map,UV).rgb;
	ROUGHNESS = base_roughness;
	METALLIC = base_metallic;
	ALBEDO = original;
	if (signed_health != 0 && top_facing > 0.55 && abs(paint_pos.z - 0.30) <= 0.06) {
		float slot = (paint_pos.x / span + 0.5) * 3.0;
		// Blue: square-ended bars. Red: triangles. Shape identifies either team
		// without hue and remains the same across filled and spent cells.
		float half_width = signed_health > 0 ? 0.41 : 0.41 * clamp((0.36 - paint_pos.z) / 0.12, 0.0, 1.0);
		if (slot >= 0.0 && slot < 3.0 && abs(fract(slot) - 0.5) < half_width) {
			bool full = int(floor(slot)) < abs(signed_health);
			ALBEDO = full ? (signed_health > 0 ? blue_ink.rgb : red_ink.rgb) : empty_ink.rgb;
		}
	}
}
