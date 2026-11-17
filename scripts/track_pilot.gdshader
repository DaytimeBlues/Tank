shader_type spatial;
render_mode diffuse_burley;
uniform float left_metres=0.0;
uniform float right_metres=0.0;
varying vec3 local_pos;
void vertex(){local_pos=VERTEX;}
void fragment(){
 float travel=local_pos.x<0.0?left_metres:right_metres;
 float band=step(0.72,fract((local_pos.z-travel)/0.32));
 ALBEDO=mix(vec3(0.055,0.065,0.06),vec3(0.15,0.17,0.15),band);
 ROUGHNESS=0.94;
}
