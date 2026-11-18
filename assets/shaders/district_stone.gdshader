shader_type spatial;
render_mode diffuse_burley;
uniform vec4 stone_color : source_color = vec4(0.48,0.43,0.34,1.0);
varying vec3 world_pos;
varying vec3 world_normal;
float hash_cell(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;world_normal=normalize(mat3(MODEL_MATRIX)*NORMAL);}
void fragment(){
 vec2 p=abs(world_normal.x)>abs(world_normal.z)?world_pos.zy:world_pos.xy;
 if(abs(world_normal.y)>0.7){p=world_pos.xz;}
 float row=floor(p.y/0.33);
 vec2 cell=vec2(p.x/0.76+mod(row,2.0)*0.5,p.y/0.33);
 vec2 f=fract(cell);
 vec2 aa=max(fwidth(cell)*1.25,vec2(0.008));
 float edge_x=smoothstep(0.02,0.02+aa.x,min(f.x,1.0-f.x));
 float edge_y=smoothstep(0.035,0.035+aa.y,min(f.y,1.0-f.y));
 float stone=edge_x*edge_y;
 float shade=mix(0.86,1.1,hash_cell(floor(cell)));
 vec3 face=stone_color.rgb*shade;
 ALBEDO=mix(stone_color.rgb*0.66,face,stone);
 ROUGHNESS=0.95;
}
