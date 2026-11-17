shader_type spatial;
render_mode cull_disabled;
// One restrained surface shared by the original deck and coplanar base triangles.
// Visual-only: world-space colour cannot move geometry or authority colliders.
uniform sampler2D detail_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 stone_colour : source_color = vec4(0.38, 0.40, 0.41, 1.0);
uniform float detail_strength : hint_range(0.0,0.2) = 0.055;
uniform float stone_roughness : hint_range(0.0,1.0) = 0.94;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 vec3 weight = pow(abs(world_normal),vec3(4.0));
 weight /= max(dot(weight,vec3(1.0)),0.0001);
 vec3 tx = texture(detail_map,world_position.zy*0.25).rgb;
 vec3 ty = texture(detail_map,world_position.xz*0.25).rgb;
 vec3 tz = texture(detail_map,world_position.xy*0.25).rgb;
 float detail = dot(tx*weight.x+ty*weight.y+tz*weight.z,vec3(0.2126,0.7152,0.0722));
 // Four metre retained photograph is only low-amplitude achromatic grain.
 vec3 stone = stone_colour.rgb * (1.0 + (detail-0.5)*detail_strength);
 // Original bridge-kit two metre course rhythm, now world-locked across both meshes.
 vec2 slab = world_position.xz / vec2(2.0,1.0);
 slab.x += mod(floor(slab.y),2.0)*0.5;
 vec2 edge = min(fract(slab),1.0-fract(slab));
 vec2 aa = max(fwidth(slab),vec2(0.001));
 vec2 joint = 1.0-smoothstep(vec2(0.008)-aa,vec2(0.008)+aa,edge);
 float seam = max(joint.x,joint.y)*smoothstep(0.7,0.95,abs(world_normal.y));
 stone *= 1.0-0.16*seam;
 // Side fascia uses actual vertical courses, not stretched top-deck tiling.
 // Pure shading: no displacement, fake openings, new cover or road obstruction.
 float side_weight = 1.0-smoothstep(0.3,0.65,abs(world_normal.y));
 float horizontal = abs(world_normal.z)>abs(world_normal.x) ? world_position.x : world_position.z;
 vec2 course = vec2(horizontal/1.25,world_position.y/0.38);
 course.x += mod(floor(course.y),2.0)*0.5;
 vec2 cell = floor(course);
 vec2 course_edge = min(fract(course),1.0-fract(course));
 vec2 course_aa = max(fwidth(course),vec2(0.001));
 vec2 mortar = 1.0-smoothstep(vec2(0.025)-course_aa,vec2(0.025)+course_aa,course_edge);
 float variation = fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453);
 vec3 fascia = stone * mix(0.84,1.13,variation);
 fascia = mix(fascia,stone_colour.rgb*0.48,max(mortar.x,mortar.y));
 ALBEDO = mix(stone,fascia,side_weight);
 ROUGHNESS = stone_roughness;
 SPECULAR = 0.1;
}
