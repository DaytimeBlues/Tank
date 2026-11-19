shader_type spatial;
render_mode cull_disabled;
// Default: canonical playable road treatment. The scenic apron uses the same fixed vertex/lighting path.
uniform bool scenic_ground=false;
uniform vec4 road_segments[32];
uniform vec4 quay_footpath[5];
uniform bool has_quay_path=false;
uniform int road_count=0;
uniform vec4 base_circles[7];
uniform int base_count=0;
uniform vec4 root_circles[16];
uniform int root_count=0;
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
#include "res://assets/depot_fork_verge.gdshaderinc"
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 if (scenic_ground) {
  float broad=noise(world.xz*0.13);
  float grain=noise(world.xz*2.6);
  vec3 tint=COLOR.rgb;
  float grass=smoothstep(0.015,0.09,tint.g-tint.r);
  vec3 earth=vec3(0.42,0.34,0.23);
  vec3 meadow=vec3(0.31,0.39,0.22);
  vec3 base=mix(tint,mix(earth,meadow,grass),0.60);
  ALBEDO=base*(0.88+broad*0.19+grain*0.07);
  ROUGHNESS=0.97;
 } else {
 float grass=smoothstep(.025,.10,COLOR.g-COLOR.r);float broad=noise(world.xz*.23);float fine=noise(world.xz*5.0);
 vec3 base=mix(vec3(.44,.34,.22),vec3(.34,.43,.23),grass);
 ALBEDO=mix(COLOR.rgb,base,.73)*(.86+.22*broad+.10*fine);
 float best=1000000.0;float second_best=1000000.0;float along=0.0;
 for(int i=0;i<32;i++){
  if(i>=road_count)break;
  vec2 a=road_segments[i].xy;vec2 d=road_segments[i].zw-a;float len2=max(dot(d,d),.001);
  float t=clamp(dot(world.xz-a,d)/len2,0.0,1.0);vec2 q=world.xz-a-d*t;float ds=dot(q,q);
  if(ds<best){second_best=best;best=ds;along=t*sqrt(len2);}else{second_best=min(second_best,ds);}
 }
 float dist=sqrt(best);float road=1.0-smoothstep(5.7,7.4,dist);
 // Shared road hierarchy: shallow colour finish only, never physical ruts/berms.
 float dry_road=smoothstep(.6,1.3,world.y);float base_edge_noise=(noise(world.xz*.12)-.5)*2.0;
 for(int i=0;i<7;i++){
  if(i>=base_count)break;
  dry_road*=smoothstep(base_circles[i].z-3.0,base_circles[i].z+6.0,length(world.xz-base_circles[i].xy)+base_edge_noise);
 }
 float edge_jitter=(noise(world.xz*.19)-.5)*1.2;
 float core=1.0-smoothstep(4.8,5.7,dist);
 float shoulder_all=smoothstep(4.8,5.7,dist)*(1.0-smoothstep(7.2,9.0,dist+edge_jitter));
 float road_patch=noise(world.xz*.11+vec2(23,4));
 float grit_filter=1.0-smoothstep(.25,.8,length(fwidth(world.xz*4.0)));
 float packed_grit=mix(.5,noise(world.xz*4.0),grit_filter);
 vec3 road_core=vec3(.51,.455,.345)*(.86+.14*road_patch+.16*packed_grit);
 vec3 rough_edge=mix(vec3(.39,.37,.245),vec3(.50,.45,.33),noise(world.xz*.67));
 ALBEDO=mix(ALBEDO,road_core,core*dry_road*.66);
 ALBEDO=mix(ALBEDO,rough_edge,shoulder_all*dry_road*(.43+.30*noise(world.xz*.31)));
 float ruts=(1.0-smoothstep(.18,.78,abs(dist-1.30+(broad-.5)*.28)))*(1.0-smoothstep(.85,1.0,grass));
 float mud=noise(world.xz*.38+vec2(8.1,1.7));float broken=.45+.55*smoothstep(.1,.7,mud);
 float tread=.97+.03*smoothstep(.35,.65,fract(along*3.7));
 vec3 packed=vec3(.32,.255,.17)*(.85+.26*broad);
 ALBEDO=mix(ALBEDO,packed*tread,ruts*road*broken*.30*smoothstep(0.0,1.5,sqrt(second_best)-dist));
 float verge=smoothstep(3.7,5.3,dist)*(1.0-smoothstep(6.1,7.6,dist));
 vec2 cell=floor(world.xz*8.0);float grit=step(.91,hash(cell))*(1.0-smoothstep(.08,.26,length(fract(world.xz*8.0)-.5)));
 ALBEDO=mix(ALBEDO,vec3(.50,.47,.36),grit*verge*.36);
 vec2 p=world.xz;
 ALBEDO=depot_fork_verge(ALBEDO,p,dist,broad,fine);

 // East landing, central crossing only. Roughly squared local setts laid
 // crosswise in a packed-earth bed, breaking up toward the orchard road.
 vec2 sett_uv=p/vec2(.56,1.06);
 vec2 sett_aa=max(fwidth(sett_uv),vec2(.001));
 if(p.x>40.0 && p.x<54.0 && abs(p.y)<5.7){
  float course=floor(sett_uv.x);
  sett_uv.y+=mod(course,2.0)*.5;
  vec2 key=floor(sett_uv);
  vec2 rim=min(fract(sett_uv),1.0-fract(sett_uv));
  vec2 inset=smoothstep(vec2(.035)-sett_aa,vec2(.035)+sett_aa,rim);
  float resolve=1.0-smoothstep(.2,.85,max(sett_aa.x,sett_aa.y));
  float face=mix(.86,inset.x*inset.y,resolve);
  float width=1.0-smoothstep(4.75,5.7,abs(p.y));
  float distance_fade=1.0-smoothstep(43.0,54.0,p.x);
  float broken=smoothstep(-.15,.32,distance_fade-.60*mix(.5,hash(key),resolve));
  float bed=width*distance_fade;
  vec3 paver=mix(vec3(.29,.29,.26),vec3(.45,.43,.36),mix(.5,hash(key),resolve));
  paver*=.93+.10*broad+.05*fine;
  ALBEDO=mix(ALBEDO,paver,bed*broken*(.23+.75*face));
 }

 // Two bounded western field finishes. Opaque colour only: canonical triangles untouched.
 vec2 field_local=p-vec2(-142.0,120.0);
 // Southern cultivation edge follows the farm, northern edge admits broad grass lobes.
 float pasture_edge=max(abs(field_local.x+(noise(p*.075)-.5)*3.0)-18.0,abs(field_local.y)-15.0+(field_local.y<0.0?(noise(p*.10)-.35)*7.0:0.0));
 float pasture=(pasture_edge+15.0)/15.0;
 float fallow=length((p-vec2(-146.0,32.0))/vec2(16.0,23.0));
 float boundary_noise=(noise(p*.12)-.5)*.24;
 float field_mask=1.0-smoothstep(.74,1.02,min(pasture,fallow)+boundary_noise);
 field_mask*=smoothstep(9.0,11.0,dist)*grass;
 field_mask*=smoothstep(-159.0,-155.0,p.x)*(1.0-smoothstep(151.0,156.0,p.y));
 for(int i=0;i<7;i++){
  if(i>=base_count)break;
  field_mask*=smoothstep(base_circles[i].z+2.0,base_circles[i].z+4.0,length(p-base_circles[i].xy));
 }
 // Clear existing farm connector and windmill service corridor, including tank-width margins.
 field_mask*=1.0-(1.0-smoothstep(4.5,6.0,abs(p.y-74.0)))*(1.0-smoothstep(-110.0,-106.0,p.x));
 field_mask*=1.0-(1.0-smoothstep(4.0,6.0,abs(p.x+129.0)))*(1.0-smoothstep(-16.0,-12.0,p.y));
 for(int i=0;i<16;i++){
  if(i>=root_count)break;
  float island_edge=length(p-root_circles[i].xy)+(noise(p*.35)-.5)*.6;
  field_mask*=smoothstep(root_circles[i].z,root_circles[i].z+1.8,island_edge);
 }
 float row_phase=p.x*.56+p.y*.09+noise(p*.08)*.5;
 float row_wave=.5+.5*sin(row_phase*6.2831853);
 float row_aa=1.0-smoothstep(.35,1.1,fwidth(row_phase));
 float stubble=mix(.5,row_wave,row_aa*smoothstep(.30,.75,noise(p*.065+vec2(12,7))));
 vec3 field_colour=mix(vec3(.37,.34,.205),vec3(.53,.47,.285),.25+.65*noise(p*.17));
 field_colour*=.91+.12*stubble+.08*fine;
 ALBEDO=mix(ALBEDO,field_colour,field_mask*.86);
 // Depot service yard: painted into existing terrain, no floating plane or physics change.
 vec2 yard=abs(p-vec2(-135.5,-120.0))-vec2(3.5,5.2);
 float yard_sd=length(max(yard,vec2(0)))+min(max(yard.x,yard.y),0.0);
 float entry=length((p-vec2(-130.0,-120.0))/vec2(5.0,4.2))-1.0;
 float apron=1.0-smoothstep(-0.3,1.15,min(yard_sd,entry*3.5)+(noise(p*.61)-.5)*.85);
 float gravel=noise(p*10.0);float wheel=(1.0-smoothstep(.25,.65,abs(abs(p.y+120.0)-1.5)))*(1.0-smoothstep(-128.0,-125.0,p.x));
 vec3 yard_colour=vec3(.43,.36,.255)*(.92+.12*broad+.10*gravel)-vec3(.025)*wheel;
 ALBEDO=mix(ALBEDO,yard_colour,apron);
 vec2 mill=abs(p-vec2(-137.0,-22.0))-vec2(5.0,6.5);
 vec2 home=abs(p-vec2(-137.0,-52.0))-vec2(6.0,7.0);
 float mill_sd=length(max(mill,vec2(0)))+min(max(mill.x,mill.y),0.0);
 float home_sd=length(max(home,vec2(0)))+min(max(home.x,home.y),0.0);
 vec2 yard_start=vec2(-132.0,-52.0);vec2 yard_end=vec2(-128.0,-22.0);vec2 yard_axis=yard_end-yard_start;
 float link=length(p-yard_start-yard_axis*clamp(dot(p-yard_start,yard_axis)/dot(yard_axis,yard_axis),0.0,1.0))-2.6;
 float district_ground=1.0-smoothstep(-.2,1.4,min(min(mill_sd,home_sd),link)+(noise(p*.45)-.5)*1.2);
 ALBEDO=mix(ALBEDO,vec3(.43,.36,.255)*(.9+.16*broad+.1*fine),district_ground);
 // West Farm yard and curved connector, painted on unchanged collision terrain.
 vec2 farm=abs(p-vec2(-134.0,75.0))-vec2(6.0,8.0);
 float farm_sd=length(max(farm,vec2(0)))+min(max(farm.x,farm.y),0.0);
 vec2 farm_a=vec2(-132.0,75.0);vec2 farm_b=vec2(-112.0,73.0);vec2 farm_axis=farm_b-farm_a;
 float farm_link=length(p-farm_a-farm_axis*clamp(dot(p-farm_a,farm_axis)/dot(farm_axis,farm_axis),0.0,1.0))-2.6;
 float farm_ground=1.0-smoothstep(-.3,1.5,min(farm_sd,farm_link)+(noise(p*.41)-.5)*1.5);
 ALBEDO=mix(ALBEDO,vec3(.46,.375,.25)*(.88+.17*broad+.12*fine),farm_ground);
 // River Junction service route and shore loading yard on canonical terrain.
 vec2 river_a=vec2(-40.0,10.0);vec2 river_b=vec2(-28.0,26.0);vec2 river_c=vec2(-23.0,37.0);
 vec2 river_ab=river_b-river_a;vec2 river_bc=river_c-river_b;
 float river_link_a=length(p-river_a-river_ab*clamp(dot(p-river_a,river_ab)/dot(river_ab,river_ab),0.0,1.0))-3.3;
 float river_link_b=length(p-river_b-river_bc*clamp(dot(p-river_b,river_bc)/dot(river_bc,river_bc),0.0,1.0))-3.3;
 float river_yard=(length((p-vec2(-26.0,36.0))/vec2(8.0,6.8))-1.0)*5.0;
 float river_mask=1.0-smoothstep(-.2,1.4,min(min(river_link_a,river_link_b),river_yard)+(noise(p*.31)-.5)*1.8);
 river_mask*=1.0-smoothstep(-18.0,-16.0,p.x);
 ALBEDO=mix(ALBEDO,vec3(.44,.365,.26)*(.88+.17*broad+.12*fine),river_mask);
 // Depot servicing apron ties the tower and stores to the existing garage.
 vec2 depot_a=vec2(-142.0,-138.0);vec2 depot_b=vec2(-140.0,-125.0);vec2 depot_axis=depot_b-depot_a;
 float depot_link=length(p-depot_a-depot_axis*clamp(dot(p-depot_a,depot_axis)/dot(depot_axis,depot_axis),0.0,1.0))-4.4;
 float depot_store=(length((p-vec2(-144.0,-129.0))/vec2(5.2,3.4))-1.0)*3.0;
 float depot_mask=1.0-smoothstep(-.3,1.1,min(depot_link,depot_store)+(noise(p*.37)-.5)*1.4);
 ALBEDO=mix(ALBEDO,vec3(.43,.38,.29)*(.9+.12*broad+.08*fine),depot_mask);
 // Reservoir distribution compound, not a new water body.
 vec2 pump_a=vec2(124.0,110.0);vec2 pump_b=vec2(129.0,124.0);vec2 pump_axis=pump_b-pump_a;
 float pump_link=length(p-pump_a-pump_axis*clamp(dot(p-pump_a,pump_axis)/dot(pump_axis,pump_axis),0.0,1.0))-3.0;
 float pump_yard=(length((p-vec2(133.0,125.0))/vec2(7.0,5.0))-1.0)*4.0;
 float pump_mask=1.0-smoothstep(-.2,1.3,min(pump_link,pump_yard)+(noise(p*.32)-.5)*1.5);
 ALBEDO=mix(ALBEDO,vec3(.45,.40,.30)*(.9+.14*broad+.08*fine),pump_mask);
 // Orchard masks have zero support outside this conservative box.
 // Take derivatives before the spatial branch for defined boundary filtering;
 // keep the lane/court noise and color calculations inside the box.
 float orchard_footprint=length(fwidth(p*3.25));
 if(p.x>119.0 && p.x<145.0 && p.y>-2.0 && p.y<18.0) {
  // Orchard loading composition: a worn earth lane leads to a distinct
  // crosswise gravel court. Surface finish only, on canonical terrain.
  vec2 yard_sample=p-vec2(137.6,7.45);
  vec2 court_corner=abs(yard_sample)-vec2(4.2,6.4);
  float orchard_court=length(max(court_corner,vec2(0)))+min(max(court_corner.x,court_corner.y),0.0)-.72;
  float orchard_edge=noise(p*vec2(.46,.61));
  float court_mask=1.0-smoothstep(-.22,1.03,orchard_court+(orchard_edge-.5)*1.42);
  court_mask*=1.0-smoothstep(142.3,143.35,p.x);
  // Keep the entrance open but narrower than the loading area. The existing
  // stone wall and grass outside the court remain its north/side boundaries.
  vec2 orchard_a=vec2(123.6,12.05);
  vec2 ahead=normalize(vec2(1.0,-.27));
  vec2 cross_axis=vec2(-ahead.y,ahead.x);
  vec2 rel=p-orchard_a;
  float travel=dot(rel,ahead);
  float side=dot(rel,cross_axis)-(noise(vec2(travel*.23,8.2))-.5)*.37;
  float lane_mask=smoothstep(-3.0,1.9,travel)*(1.0-smoothstep(12.0,16.0,travel));
  lane_mask*=1.0-smoothstep(2.45,3.8,abs(side)+(orchard_edge-.5)*.56);
  float track=(1.0-smoothstep(.14,.74,abs(abs(side)-1.28)));
  float track_break=.24+.76*smoothstep(.13,.76,noise(p*.35));
  vec3 lane_colour=vec3(.474,.397,.282)*(.91+.13*broad+.06*fine);
  lane_colour=mix(lane_colour,vec3(.367,.303,.214),track*track_break*.53);
  ALBEDO=mix(ALBEDO,lane_colour,lane_mask);
  // Weathered crusher fines and scattered angular pale chips, anisotropy
  // and mip attenuation inherited from the ground's derivative-based grain.
  float pebbles=grit_filter*smoothstep(.72,.91,noise(p*vec2(4.3,5.2)));
  float weather=noise(p*vec2(.31,.42));
  float transfer=track*track_break*(1.0-smoothstep(13.0,18.0,travel));
  vec3 court_colour=mix(vec3(.324,.302,.251),vec3(.411,.376,.310),weather);
  float chips=mix(.5,noise(p*vec2(2.65,3.25)),1.0-smoothstep(.32,1.02,orchard_footprint));
  court_colour+=(chips-.5)*vec3(.043,.040,.034)+vec3(.046,.041,.034)*pebbles;
  court_colour=mix(court_colour,vec3(.347,.317,.260),transfer*.29);
  ALBEDO=mix(ALBEDO,court_colour,court_mask*.97);
 }
 // Ridge battery service pocket, outside capture/road corridor.
 float battery_yard=(length((p-vec2(130.0,-96.0))/vec2(6.4,7.0))-1.0)*4.0;
 vec2 battery_a=vec2(123.0,-98.0);vec2 battery_b=vec2(130.0,-96.0);vec2 battery_axis=battery_b-battery_a;
 float battery_link=length(p-battery_a-battery_axis*clamp(dot(p-battery_a,battery_axis)/dot(battery_axis,battery_axis),0.0,1.0))-3.0;
 float battery_mask=1.0-smoothstep(-.2,1.3,min(battery_yard,battery_link)+(noise(p*.32)-.5)*1.6);
 ALBEDO=mix(ALBEDO,vec3(.43,.385,.29)*(.9+.14*broad+.08*fine),battery_mask);
 // Western crossing watch office: narrow worn threshold, no geometry/road change.
 vec2 watch_a=vec2(-54.0,-10.7);vec2 watch_b=vec2(-54.0,-7.5);vec2 watch_axis=watch_b-watch_a;
 float watch_link=length(p-watch_a-watch_axis*clamp(dot(p-watch_a,watch_axis)/dot(watch_axis,watch_axis),0.0,1.0))-1.15;
 float watch_edge=(length((p-vec2(-49.0,-13.0))/vec2(5.0,1.1))-1.0)*1.0;
 float watch_mask=1.0-smoothstep(-.15,.7,min(watch_link,watch_edge)+(noise(p*.44)-.5)*.8);
 ALBEDO=mix(ALBEDO,vec3(.43,.385,.29)*(.9+.14*broad+.08*fine),watch_mask*.85);
 // The thin packed-earth walk joins the warehouse loading steps to the bank;
 // it is not a vehicle route, terrain displacement, or new cover.
 if (has_quay_path) {
  float foot=1e4;
  for(int i=0;i<5;i++){
   vec2 a=quay_footpath[i].xy, d=quay_footpath[i].zw-a;
   vec2 delta=p-a-d*clamp(dot(p-a,d)/max(dot(d,d),.001),0.,1.);
   foot=min(foot,length(delta));
  }
  float edge=foot+(noise(p*.91)-.5)*.30;
  float mask=(1.-smoothstep(.43,.88,edge))*(.80+.20*broad);
  vec3 earth=vec3(.40,.335,.235)*(.84+.25*broad+.12*fine);
  ALBEDO=mix(ALBEDO,earth,mask);
 }
 float wet=(1.0-smoothstep(.45,1.15,world.y))*(1.0-smoothstep(12.0,19.0,abs(world.x)));
 ALBEDO=mix(ALBEDO,ALBEDO*vec3(.56,.62,.62),wet*.7);ROUGHNESS=mix(.98,.48,wet);
 }
}
