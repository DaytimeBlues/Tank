// Reservoir finish only. Positions/normals remain local to the original mesh.
// Atlas is opaque and mip-filtered; arbitrary Godot/imported mesh UVs are not used.
shader_type spatial;
render_mode cull_back;
uniform sampler2D stone_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool roof_surface = false;
uniform bool service_trim = false;
varying vec3 lp;
varying vec3 ln;
void vertex() {
	lp=VERTEX;
	ln=NORMAL;
}
void fragment() {
	vec3 n=normalize(ln);
	vec2 quadrant=vec2(.5,0.0);
	vec2 face;
	if(roof_surface && n.y>.25) {
		quadrant=vec2(0.0,.5);
		face=vec2(lp.x/5.6+.5,(lp.z/4.6+.5));
	} else if(roof_surface) {
		face=vec2(lp.x/5.6+.5,.85);
	} else if(service_trim || abs(n.z)>.65) {
		quadrant=(!service_trim && n.z<0.0)?vec2(0.0):vec2(.5,.5);
		face=vec2(lp.x/5.4+.5,1.0-lp.y/(quadrant.y>0.0?4.25:3.25));
	} else {
		quadrant=vec2(.5,0.0);
		face=vec2(lp.z/4.4+.5,1.0-lp.y/4.25);
	}
	vec2 atlas_uv=quadrant+(vec2(6.5)+499.0*clamp(face,vec2(0.0),vec2(1.0)))/1024.0;
	ALBEDO=texture(stone_atlas,atlas_uv).rgb;
	ROUGHNESS=.95;
}
