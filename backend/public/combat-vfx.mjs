// Client presentation of authoritative events. No collision, damage or shot delay.
export const FX_CAPS=Object.freeze({trail:4,flash:4,smoke:32,spark:32,blast:4});
const finite=v=>Number.isFinite(v),clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const CONTACT_CAP=8, CONTACT_GRACE=.35, RECOIL_ATTACK=.022, RECOIL_END=.28;
// The same shot can have different relevance in each browser. Use the
// existing pool eviction only for the visible flash, tracer and burst.
const CUE_PRIORITY={peer:2,hit:3,scrap:4,incoming:5,own:6,ownScrap:7};
function shotCuePriority(viewerId,owner,shot){
 if(viewerId==null)return CUE_PRIORITY.peer;
 if(owner===viewerId)return CUE_PRIORITY.own;
 if(shot.hit===viewerId)return CUE_PRIORITY.incoming;
 return shot.hit?CUE_PRIORITY.hit:CUE_PRIORITY.peer;
}
function random(seed){let s=seed>>>0;return ()=>{s=(Math.imul(s,1664525)+1013904223)>>>0;return s/4294967296;};}
// Solo BattlefieldDrive.cast ends at the nearest obstruction or its 90m range.
// This classifies a visual contact only; it never creates a server hit/damage.
export function soloPresentationShot(shot){
 if(!shot)return null;
 const distance=Math.hypot(shot.endX-shot.x,shot.endY-shot.y,shot.endZ-shot.z);
 return {...shot,blocked:!shot.hit&&Number.isFinite(distance)&&distance<90-1e-4};
}
export class EffectTimeline {
 constructor(){this.pools=Object.fromEntries(Object.entries(FX_CAPS).map(([k,n])=>[k,Array.from({length:n},()=>({active:false}))]));this.shots=new Map();this.health=new Map();this.connected=new Map();this.recoils=new Map();this.contacts=new Map();this.dust=new Map();this.ready=false;this.lastTime=-Infinity;this.won=false;this.dropped=0;}
 emit(type,data,priority=1){const pool=this.pools[type];let slot=pool.find(s=>!s.active);if(!slot){slot=pool.reduce((a,b)=>a.priority<b.priority?a:b);if(slot.priority>=priority){this.dropped++;return false;}}Object.assign(slot,data,{active:true,priority});return true;}
 clearOwner(id){for(const pool of Object.values(this.pools))for(const s of pool)if(s.owner===id)s.active=false;this.contacts.delete(id);this.recoils.delete(id);this.dust.delete(id);}
 reset(){for(const pool of Object.values(this.pools))for(const s of pool)s.active=false;this.shots.clear();this.health.clear();this.connected.clear();this.contacts.clear();this.recoils.clear();this.dust.clear();this.ready=false;this.lastTime=-Infinity;this.won=false;}
 tick(now){
  for(const pool of Object.values(this.pools))for(const s of pool)if(s.active&&now>=s.start+s.life)s.active=false;
  for(const [id,t]of this.recoils)if(now-t>=RECOIL_END)this.recoils.delete(id);
  for(const [owner,contact]of this.contacts){
   if(now<contact.due)continue;
   this.contacts.delete(owner);
   // A skipped frame can show contact once on the next frame. Do not replay
   // old effects after a stall or leave an unbounded queue of visual events.
   if(now-contact.due<=CONTACT_GRACE)this.contact(contact,now);
  }
 }
 shot(owner,shot,now,reduced=false,priority=CUE_PRIORITY.peer){
  const values=[shot.x,shot.y,shot.z,shot.endX,shot.endY,shot.endZ,now];if(!values.every(finite))return false;
  const dx=shot.endX-shot.x,dy=shot.endY-shot.y,dz=shot.endZ-shot.z,distance=Math.hypot(dx,dy,dz);if(distance>150)return false;
  const r=random(shot.id*541+owner.length),base={owner,start:now,x:shot.x,y:shot.y,z:shot.z,dx:distance?dx/distance:0,dy:distance?dy/distance:0,dz:distance?dz/distance:1};
  const travel=distance>.1?clamp(distance/475,.10,.20):0;
  this.recoils.set(owner,now);this.emit('flash',{...base,life:.14,strength:reduced?.64:1},priority);
  if(travel)this.emit('trail',{...base,distance,life:travel,width:reduced?.05:.08},priority);
  for(let i=0;i<(reduced?1:3);i++)this.emit('smoke',{...base,life:.65,vx:base.dx*1.3+(r()-.5)*.55,vy:.55+r()*.55,vz:base.dz*1.3+(r()-.5)*.55,size:reduced?.24:.37,grow:.8,alpha:.37},1);
  if(shot.hit||shot.blocked){
   const contact={owner,due:now+travel,x:shot.endX,y:shot.endY,z:shot.endZ,dx:base.dx,dy:base.dy,dz:base.dz,hit:!!shot.hit,reduced,priority,seed:shot.id*823+owner.length};
   if(!travel)this.contact(contact,now);
   else if(this.contacts.has(owner)||this.contacts.size<CONTACT_CAP)this.contacts.set(owner,contact);
   else this.dropped++;
  }return true;
 }
 contact({owner,x,y,z,dx,dy,dz,hit,reduced,priority,seed},now){
  const r=random(seed),impact={owner,start:now,x,y,z};
  // Pull the soft surface glow a little back down the incoming ray so
  // the collider cannot bury it. Debris still starts at the contact point.
  this.emit('blast',{...impact,dx,dy,dz,lift:.40,setback:.8,life:hit?.28:.23,initial:(hit?3.7:2.75)*(reduced?.6:1),grow:(hit?2:1.5)*(reduced?.62:1),alpha:hit?1:.88},priority);
  for(let i=0;i<(reduced?2:8);i++)this.emit('spark',{...impact,life:.28+r()*.35,vx:(r()-.5)*12-dx*2,vy:2+r()*5,vz:(r()-.5)*12-dz*2,size:.06+r()*.06},2);
  for(let i=0;i<(reduced?1:4);i++)this.emit('smoke',{...impact,x:x-dx*.66+(r()-.5)*.8,y:y+.48+r()*.44,z:z-dz*.66+(r()-.5)*.8,life:1+r()*.45,vx:(r()-.5)*2,vy:.85+r()*1.3,vz:(r()-.5)*2,size:reduced?.36:.75,grow:reduced?1.05:1.85,alpha:.48},2);
 }
 death(owner,tank,now,reduced=false,priority=3){
  this.clearOwner(owner);const r=random(owner.length*71+Math.round(now*100)),base={owner,start:now,x:tank.x,y:tank.y+.5,z:tank.z};
  this.emit('blast',{...base,life:.48,initial:.5,grow:reduced?3.2:5.4,alpha:1,setback:0},priority);
  for(let i=0;i<(reduced?4:12);i++)this.emit('smoke',{...base,x:base.x+(r()-.5)*2,y:base.y+r(),z:base.z+(r()-.5)*2,life:1.6+r()*.8,vx:(r()-.5)*1.8,vy:1.2+r()*1.8,vz:(r()-.5)*1.8,size:.6,grow:1.7,alpha:.58},3);
  for(let i=0;i<(reduced?4:16);i++)this.emit('spark',{...base,life:.5+r()*.6,vx:(r()-.5)*10,vy:3+r()*5,vz:(r()-.5)*10,size:.045+r()*.045},3);
 }
 accept(state,now,reduced=false){
  if(!state||!finite(state.time)||state.time<this.lastTime)return;
  if(state.won){if(!this.won)this.reset();this.won=true;this.lastTime=state.time;return;}
  if(this.won)this.reset();
  const ids=new Set(state.players.map(p=>p.id));for(const id of this.health.keys())if(!ids.has(id)){this.clearOwner(id);this.shots.delete(id);this.health.delete(id);this.connected.delete(id);}
  for(const p of state.players){
   const known=this.health.has(p.id),previous=this.health.get(p.id),oldShot=this.shots.get(p.id)??0;
   if(known&&this.connected.get(p.id)&&!p.connected)this.clearOwner(p.id);
   if(this.ready&&known&&p.connected&&this.connected.get(p.id)&&p.shot&&p.shot.id>oldShot&&state.time-p.shot.time>=0&&state.time-p.shot.time<.35)this.shot(p.id,p.shot,now,reduced,shotCuePriority(state.viewerId,p.id,p.shot));
   if(this.ready&&known&&previous>0&&p.health===0)this.death(p.id,p.tank,now,reduced,state.viewerId==null?3:p.id===state.viewerId?CUE_PRIORITY.ownScrap:CUE_PRIORITY.scrap);
   if(known&&previous===0&&p.health>0)this.clearOwner(p.id);
   this.shots.set(p.id,Math.max(oldShot,p.shot?.id??0));this.health.set(p.id,p.health);this.connected.set(p.id,p.connected);
  }
  this.ready=true;this.lastTime=state.time;this.won=state.won;
 }
 ambient(players,now,reduced=false){
  if(reduced)return;for(const p of players){if(p.health<=0||!p.connected)continue;const t=p.tank,damaged=p.health===1,moving=Math.abs(t.speed)>1;if(!damaged&&!moving)continue;
   const last=this.dust.get(p.id)??-Infinity;if(now-last<(damaged?.45:.18))continue;this.dust.set(p.id,now);
   this.emit('smoke',{owner:p.id,start:now,x:t.x-Math.sin(t.yaw)*1.8,y:damaged?t.y+1:t.y-.75,z:t.z-Math.cos(t.yaw)*1.8,life:damaged?1.6:.7,vx:0,vy:damaged?1.1:.4,vz:0,size:damaged?.3:.18,grow:damaged?.8:.35,alpha:damaged?.4:.22},0);
  }
 }
 recoil(id,now,reduced=false){
  const start=this.recoils.get(id);if(start===undefined)return 0;
  const age=now-start;if(age<0||age>=RECOIL_END)return 0;
  const progress=age<RECOIL_ATTACK?age/RECOIL_ATTACK:1-(age-RECOIL_ATTACK)/(RECOIL_END-RECOIL_ATTACK);
  return (reduced?.1:.18)*progress*progress*(3-2*progress);
 }
 stats(){return Object.fromEntries(Object.entries(this.pools).map(([k,p])=>[k,p.filter(s=>s.active).length]));}
}
export function createCombatVFX(THREE,scene){
 const timeline=new EffectTimeline(),dummy=new THREE.Object3D(),forward=new THREE.Vector3(0,0,1),direction=new THREE.Vector3(),cameraRight=new THREE.Vector3(),cameraUp=new THREE.Vector3();let disposed=false;
 const smokeGeometry=new THREE.PlaneGeometry(1,1);smokeGeometry.setAttribute('instanceOpacity',new THREE.InstancedBufferAttribute(new Float32Array(FX_CAPS.smoke),1).setUsage(THREE.DynamicDrawUsage));
 const smokeMaterial=new THREE.ShaderMaterial({transparent:true,depthWrite:false,vertexShader:'attribute float instanceOpacity; varying float a; varying vec2 uv0; void main(){a=instanceOpacity;uv0=uv;gl_Position=projectionMatrix*modelViewMatrix*instanceMatrix*vec4(position,1.0);}',fragmentShader:'varying float a; varying vec2 uv0; void main(){float d=length(uv0-0.5)*2.0;float soft=exp(-d*d*3.0)*(1.0-smoothstep(0.65,1.0,d));gl_FragColor=vec4(vec3(0.19,0.20,0.18),soft*a);\n#include <tonemapping_fragment>\n#include <colorspace_fragment>\n}'});
 const flashGeometry=new THREE.PlaneGeometry(1,1);flashGeometry.setAttribute('instanceOpacity',new THREE.InstancedBufferAttribute(new Float32Array(FX_CAPS.flash),1).setUsage(THREE.DynamicDrawUsage));
 const flashMaterial=new THREE.ShaderMaterial({transparent:true,depthWrite:false,blending:THREE.AdditiveBlending,vertexShader:smokeMaterial.vertexShader,fragmentShader:`
 varying float a;
 varying vec2 uv0;
 float square(float v) { return v * v; }
 void main() {
   vec2 p = (uv0 - vec2(0.5, 0.43)) * 2.0;
   float core = exp(-square(p.x * 6.4) - square((p.y - 0.10) * 2.1));
   float gas = exp(-square((p.x + p.y * 0.11) * 2.6) - square(p.y * 1.8));
   float taper = 1.0 - smoothstep(0.69, 1.0, length((uv0 - 0.5) * 2.0));
   vec3 heat = mix(vec3(1.0, 0.39, 0.075), vec3(1.0, 0.94, 0.72), core);
   gl_FragColor = vec4(heat, min(1.0, 0.83 * core + 0.43 * gas) * taper * a);
   #include <tonemapping_fragment>
   #include <colorspace_fragment>
 }`});
 const blastGeometry=new THREE.PlaneGeometry(1,1);blastGeometry.setAttribute('instanceOpacity',new THREE.InstancedBufferAttribute(new Float32Array(FX_CAPS.blast),1).setUsage(THREE.DynamicDrawUsage));
 const blastMaterial=new THREE.ShaderMaterial({transparent:true,depthWrite:false,blending:THREE.AdditiveBlending,vertexShader:smokeMaterial.vertexShader,fragmentShader:`
 varying float a;
 varying vec2 uv0;
 void main() {
   vec2 p = (uv0 - 0.5) * 2.0;
   float d = length(p);
   float churn = sin(p.x * 14.0 + p.y * 6.0) * sin(p.y * 17.0 - p.x * 5.0);
   float edge = d + 0.075 * churn;
   float core = exp(-d * d * 5.8);
   float rim = (edge - 0.58) * 5.5;
   float gas = exp(-rim * rim) * (0.36 + 0.2 * churn);
   float opacity = (core * 0.94 + gas) * (1.0 - smoothstep(0.72, 0.99, d));
   vec3 heat = mix(vec3(1.0, 0.26, 0.035), vec3(1.0, 0.91, 0.62), core);
   gl_FragColor = vec4(heat, min(1.0, opacity) * a);
   #include <tonemapping_fragment>
   #include <colorspace_fragment>
 }`});
 const definitions={trail:[new THREE.BoxGeometry(1,1,1),new THREE.MeshBasicMaterial({color:0xffdf96})],flash:[flashGeometry,flashMaterial],smoke:[smokeGeometry,smokeMaterial],spark:[new THREE.IcosahedronGeometry(1,0),new THREE.MeshBasicMaterial({color:0xffba62})],blast:[blastGeometry,blastMaterial]};
 const meshes={};for(const [type,[g,m]]of Object.entries(definitions)){const mesh=new THREE.InstancedMesh(g,m,FX_CAPS[type]);mesh.frustumCulled=false;mesh.count=0;mesh.visible=false;mesh.name='VFX_'+type;mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);scene.add(mesh);meshes[type]=mesh;}
 function updatePrefix(attribute,count){
  attribute.clearUpdateRanges();attribute.addUpdateRange(0,count*attribute.itemSize);attribute.needsUpdate=true;
 }
 const api={timeline,reset(){timeline.reset();for(const m of Object.values(meshes)){m.count=0;m.visible=false;}},frame(now,camera){
  if(disposed)return;timeline.tick(now);
  cameraRight.set(1,0,0).applyQuaternion(camera.quaternion);cameraUp.set(0,1,0).applyQuaternion(camera.quaternion);
  for(const [type,pool]of Object.entries(timeline.pools)){
   let active=0;const mesh=meshes[type],opacity=mesh.geometry.attributes.instanceOpacity;
   for(const s of pool){
    if(!s.active||now<s.start)continue;
    const i=active++,age=now-s.start,t=age/s.life;
    dummy.quaternion.identity();
     if(type==='trail'){const head=Math.max(Math.min(.5,s.distance),s.distance*t),segment=Math.min(9,head);direction.set(s.dx,s.dy,s.dz);dummy.position.set(s.x,s.y,s.z).addScaledVector(direction,head-segment/2);dummy.quaternion.setFromUnitVectors(forward,direction);dummy.scale.set(s.width,s.width,segment);}
     else if(type==='flash'){
      direction.set(s.dx,s.dy,s.dz);dummy.position.set(s.x,s.y,s.z).addScaledVector(direction,.63);
      dummy.quaternion.copy(camera.quaternion);dummy.rotateZ(Math.atan2(-direction.dot(cameraRight),direction.dot(cameraUp)));
      const size=(1-.48*t)*s.strength;dummy.scale.set(2.5*size,3.5*size,1);opacity.setX(i,(1-t)*(1-t));
     }
     else if(type==='blast'){
      dummy.position.set(s.x,s.y,s.z);dummy.quaternion.copy(camera.quaternion);
      if(s.setback){direction.set(s.dx,s.dy,s.dz);dummy.position.addScaledVector(direction,-s.setback);dummy.position.y+=s.lift;}
      dummy.scale.setScalar(s.initial+s.grow*(s.setback?1-Math.exp(-6*t):Math.sin(Math.PI*t)));
      opacity.setX(i,s.alpha*(1-t)*(1-t));
     }
     else {dummy.position.set(s.x+s.vx*age,s.y+s.vy*age-(type==='spark'?4*age*age:0),s.z+s.vz*age);if(type==='smoke'){dummy.quaternion.copy(camera.quaternion);dummy.scale.setScalar(s.size+s.grow*age);opacity.setX(i,s.alpha*(1-t)*(1-t));}else dummy.scale.setScalar(s.size*(1-t));}
    dummy.updateMatrix();mesh.setMatrixAt(i,dummy.matrix);
   }
   // Keep pool order, but draw and update only the active prefix. Data past
   // mesh.count stays allocated for reuse and is not part of the draw.
   mesh.count=active;mesh.visible=active>0;
   if(active){updatePrefix(mesh.instanceMatrix,active);if(opacity)updatePrefix(opacity,active);}
  }
 },dispose(){if(disposed)return;disposed=true;api.reset();for(const [g,m]of Object.values(definitions)){g.dispose();m.dispose();}for(const mesh of Object.values(meshes)){scene.remove(mesh);mesh.dispose();}},stats(){return {...timeline.stats(),drawCap:5,triangleCap:768,disposed};}};
 return api;
}
