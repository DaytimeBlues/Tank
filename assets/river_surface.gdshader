shader_type spatial;
render_mode cull_disabled;
uniform float flow_speed = 0.35;
uniform float phase_offset = 0.0;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float t=TIME*flow_speed+phase_offset;
 float a=world_pos.x*.9+world_pos.z*1.7-t;
 float b=world_pos.x*2.3-world_pos.z*.6+t*.72;
 float ripple=sin(a)*.5+sin(b)*.3;
 float sx=cos(a)*.018*.9+cos(b)*.009*2.3;
 float sz=cos(a)*.018*1.7-cos(b)*.009*.6;
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(-sx,1.0,-sz)),0.0)).xyz);
 ALBEDO=mix(vec3(.095,.20,.20),vec3(.19,.31,.29),.5+ripple*.25);
 ROUGHNESS=.44;SPECULAR=.35;
}

