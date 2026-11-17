shader_type spatial;
render_mode cull_disabled;
uniform vec4 road_segments[32];
uniform int road_count=0;
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float grass=smoothstep(.025,.10,COLOR.g-COLOR.r);float broad=noise(world.xz*.23);float fine=noise(world.xz*5.0);
 vec3 base=mix(vec3(.44,.34,.22),vec3(.34,.43,.23),grass);
 ALBEDO=mix(COLOR.rgb,base,.73)*(.86+.22*broad+.10*fine);
 float best=1000000.0;float along=0.0;
 for(int i=0;i<32;i++){
  if(i>=road_count)break;
  vec2 a=road_segments[i].xy;vec2 d=road_segments[i].zw-a;float len2=max(dot(d,d),.001);
  float t=clamp(dot(world.xz-a,d)/len2,0.0,1.0);vec2 q=world.xz-a-d*t;float ds=dot(q,q);
  if(ds<best){best=ds;along=t*sqrt(len2);}
 }
 float dist=sqrt(best);float road=1.0-smoothstep(5.7,7.4,dist);
 float ruts=(1.0-smoothstep(.18,.78,abs(dist-1.30+(broad-.5)*.28)))*(1.0-smoothstep(.85,1.0,grass));
 float mud=noise(world.xz*.38+vec2(8.1,1.7));float broken=.45+.55*smoothstep(.1,.7,mud);
 float tread=.97+.03*smoothstep(.35,.65,fract(along*3.7));
 vec3 packed=vec3(.32,.255,.17)*(.85+.26*broad);
 ALBEDO=mix(ALBEDO,packed*tread,ruts*road*broken*.38);
 float verge=smoothstep(3.7,5.3,dist)*(1.0-smoothstep(6.1,7.6,dist));
 vec2 cell=floor(world.xz*8.0);float grit=step(.91,hash(cell))*(1.0-smoothstep(.08,.26,length(fract(world.xz*8.0)-.5)));
 ALBEDO=mix(ALBEDO,vec3(.50,.47,.36),grit*verge*.36);
 vec2 p=world.xz;
 float region=smoothstep(-142.0,-134.0,p.x)*(1.0-smoothstep(-50.0,-42.0,p.x))*smoothstep(-142.0,-134.0,p.y)*(1.0-smoothstep(-70.0,-62.0,p.y));
 float patch=noise(p*.085)*.65+noise(p*.31)*.35;
 float edge_offset=(noise(p*.23)-.5)*1.6;
 float shoulder=smoothstep(5.6,6.8,dist)*(1.0-smoothstep(8.0,11.0,dist+edge_offset));
 ALBEDO=mix(ALBEDO,vec3(.51,.43,.27)*(.9+.15*patch),region*shoulder*grass*.65*(.45+.4*patch));
 float wet=(1.0-smoothstep(.45,1.15,world.y))*(1.0-smoothstep(12.0,19.0,abs(world.x)));
 ALBEDO=mix(ALBEDO,ALBEDO*vec3(.56,.62,.62),wet*.7);ROUGHNESS=mix(.98,.48,wet);
}

