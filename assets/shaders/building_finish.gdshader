shader_type spatial;
render_mode diffuse_burley;
uniform vec4 surface_color : source_color=vec4(.65,.6,.5,1);
uniform int finish_kind=0;
uniform float bottom_y=0.0;
varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 metre_scale;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){local_pos=VERTEX;local_normal=NORMAL;metre_scale=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));}
void fragment(){
 vec3 m=local_pos*metre_scale;
 vec2 p=abs(local_normal.x)>abs(local_normal.z)?m.zy:m.xy;
 if(abs(local_normal.y)>.7)p=m.xz;
 vec3 colour=surface_color.rgb;
 if(finish_kind==0){
  float cloud=noise(p*.48)*.65+noise(p*1.3)*.35;
  float grit=mix(.5,noise(p*12.0),1.0-smoothstep(.3,1.0,length(fwidth(p*12.0))));
  float dirt=(1.0-smoothstep(.1,1.0,(local_pos.y-bottom_y)*metre_scale.y))*(.55+.45*noise(p*.9));
  colour*=.89+.20*cloud+.04*grit;
  colour=mix(colour,colour*vec3(.66,.65,.56),dirt*.55);
 }else if(finish_kind==1){
  // Courses follow local roof slope, not world axes; scale is in metres.
  p=abs(local_normal.z)>abs(local_normal.x)?vec2(m.x,m.z/max(abs(local_normal.y),.25)):vec2(m.z,m.x/max(abs(local_normal.y),.25));
  float row=floor(p.y/.38);vec2 cell=vec2(p.x/.52+mod(row,2.0)*.5,p.y/.38);
  vec2 f=fract(cell);vec2 aa=max(fwidth(cell)*1.2,vec2(.01));
  float joints=(1.0-smoothstep(.025,.025+aa.x,min(f.x,1.0-f.x)))+(1.0-smoothstep(.045,.045+aa.y,min(f.y,1.0-f.y)));
  float detail=(1.0-smoothstep(.35,.9,max(fwidth(cell.x),fwidth(cell.y))))*step(.15,local_normal.y);
  colour*=mix(1.0,.88+.22*hash(floor(cell)),detail);
  colour*=1.0-min(joints,1.0)*.22*detail;
 }else{
  float wear=noise(p*.8)*.6+noise(p*3.0)*.4;
  colour*=.90+.17*wear;
  float low=(1.0-smoothstep(0.0,.45,(local_pos.y-bottom_y)*metre_scale.y));
  colour=mix(colour,colour*vec3(.72,.68,.58),low*.25);
 }
 ALBEDO=colour;ROUGHNESS=finish_kind==2?.86:.96;
}
