shader_type spatial;
render_mode diffuse_burley;
// Same opaque Burley lighting and culling for both material families.
uniform sampler2D press_ink : source_color, filter_linear_mipmap, repeat_disable;
uniform bool building_space = false;
uniform vec4 stone_color : source_color = vec4(0.48,0.43,0.34,1.0);
uniform vec4 surface_color : source_color=vec4(.65,.6,.5,1);
uniform int finish_kind=0;
uniform float bottom_y=0.0;
uniform vec4 original_colour : source_color;
uniform float original_roughness = .6;
// The material selects one coordinate space for the whole draw.
varying vec3 finish_pos;
varying vec3 finish_normal;
varying vec3 metre_scale;
float hash_cell(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){
 if(building_space){
  finish_pos=VERTEX;
  finish_normal=NORMAL;
  metre_scale=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 }else{
  finish_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
  finish_normal=normalize(mat3(MODEL_MATRIX)*NORMAL);
  metre_scale=vec3(1.0);
 }
}
void fragment(){
 if(building_space){
  vec3 local_pos=finish_pos;
  vec3 local_normal=finish_normal;
  // The Orchard donor surface uses unscaled local coordinates.
  if(finish_kind==3){
   ALBEDO=original_colour.rgb;
   ROUGHNESS=original_roughness;
   vec2 p=vec2(local_pos.x,local_pos.y-.25);
   vec2 aa=max(fwidth(p),vec2(.004));
   // Local Z points west in the placed orchard instance. No projection on walls,
   // posts, rear/east face, or other members sharing surface zero.
   if (abs(local_pos.z-3.08)<.002 && local_normal.z>.9 && abs(p.x)<=1.501 && p.y>=-.001 && p.y<=2.301) {
    float jamb=(1.0-smoothstep(.085,.085+aa.x,1.5-abs(p.x)));
    float crown=smoothstep(2.15-aa.y,2.15+aa.y,p.y);
    float deep_side=(1.0-smoothstep(.14,.14+2.0*aa.x,1.5-abs(p.x)));
    float deep_head=smoothstep(2.075-aa.y,2.145+aa.y,p.y);
    float leaf=clamp(abs(p.x)/.272,0.0,5.0);
    float grain=mix(.5,noise(p*vec2(14,1.5)),1.0-smoothstep(.35,.95,aa.x*14.0));
    float plank_fade=1.0-smoothstep(.095,.21,aa.x);
    float board=.80+.22*mix(.5,hash(vec2(floor(leaf),step(0.0,p.x))),plank_fade);
    float lines=smoothstep(.010,.018+aa.x/.272,min(fract(leaf),1.0-fract(leaf)));
    vec3 timber=vec3(.292,.192,.122)*board*(.88+.20*grain)*mix(.83,1.0,mix(1.0,lines,plank_fade));
    timber*=1.0-.2*deep_head-.16*deep_side;
    float rail=(1.0-smoothstep(.088,.088+aa.y,abs(p.y-1.79)))+
               (1.0-smoothstep(.094,.094+aa.y,abs(p.y-.43)));
    timber=mix(timber,vec3(.395,.269,.168)*(.85+.17*noise(p*vec2(2,18))),clamp(rail,0.0,1.0)*.78);
    float meeting=1.0-smoothstep(.057,.057+aa.x,abs(p.x-.033));
    timber=mix(timber,vec3(.328,.226,.148),meeting);
    float closed_joint=1.0-smoothstep(.009,.019+aa.x,abs(p.x+.013));
    timber=mix(timber,vec3(.052,.042,.031),closed_joint*.96);
    float latch=(1.0-smoothstep(.18,.18+aa.x,abs(p.x-.04)))*
                (1.0-smoothstep(.036,.036+aa.y,abs(p.y-1.1)));
    timber=mix(timber,vec3(.46,.395,.29),latch*.91);
    float frame=max(jamb,crown);
    vec3 frame_col=vec3(.116,.080,.054)*(.85+.23*noise(p*vec2(1.9,2.3)));
    float top_edge=smoothstep(2.255,2.277,p.y);
    frame_col+=vec3(.035,.025,.017)*top_edge;
    ALBEDO=mix(timber,frame_col,frame);
    // Sign is ink on existing west-facing boards, not a solid prop.
    vec2 badge_uv=vec2(p.x/2.24+.5,(1.95-p.y)/.84);
    if(all(greaterThanEqual(badge_uv,vec2(0.))) && all(lessThanEqual(badge_uv,vec2(1.)))){
     vec4 pigment=texture(press_ink,badge_uv);
     ALBEDO=mix(ALBEDO,pigment.rgb,pigment.a*.94);
    }
    ROUGHNESS=mix(.91,.67,latch*(1.0-frame));
   }
  }else{
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
 }else{
  vec3 world_pos=finish_pos;
  vec3 world_normal=finish_normal;
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
}
