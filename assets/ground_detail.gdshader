shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){float grass=smoothstep(.025,.10,COLOR.g-COLOR.r);float broad=noise(world.xz*.23);float fine=noise(world.xz*5.0);vec3 soil=vec3(.44,.34,.22);vec3 meadow=vec3(.34,.43,.23);vec3 base=mix(soil,meadow,grass);ALBEDO=mix(COLOR.rgb,base,.73)*(.86+.22*broad+.10*fine);ROUGHNESS=.98;}
