shader_type spatial;
render_mode diffuse_burley;

// Orchard shed only: tint the original solid west-facing door panel.
// Other timber on this same surface retains its original material values.
uniform vec4 original_colour : source_color;
uniform float original_roughness = .6;
varying vec3 local_pos;
varying vec3 local_normal;

float hash(vec2 p) {
 return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p);
 f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
 local_pos=VERTEX;
 local_normal=NORMAL;
}
void fragment() {
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
  ROUGHNESS=mix(.91,.67,latch*(1.0-frame));
 }
}
