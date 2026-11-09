import RAPIER from '@dimforge/rapier3d-compat';
import { BATTLEFIELD_MAP,terrainHeight } from './battlefield-map.mjs';
import { createHull,rotate,differentialStep } from './suspension.mjs';
import { muzzle } from './terrain-query.mjs';
import { tankProfile } from '../public/tank-config.mjs';
export const BATTLE_SHOT_RANGE = 90;
export class BattlefieldDrive {
 constructor(profile='prototype',shared=null,map=BATTLEFIELD_MAP){
  this.map=shared?.map??map;this.profile=tankProfile(profile);this.driveSpeed=this.profile.forwardMps;
  if(shared){for(const key of ['world','supportHandles','bridgeColliders','waterBlockers','ground','targets','targetColliders'])this[key]=shared[key];}
  else {
  this.world=new RAPIER.World({x:0,y:-9.81,z:0});this.supportHandles=new Set();this.bridgeColliders=new Map();this.waterBlockers=new Set();
  for(const c of this.map.chunks){const collider=this.world.createCollider(RAPIER.ColliderDesc.trimesh(new Float32Array(c.vertices),new Uint32Array(c.indices)).setFriction(.8));this.supportHandles.add(collider.handle);this.ground??=collider;}
  for(const b of this.map.bridges){const c=this.world.createCollider(RAPIER.ColliderDesc.cuboid(b.w/2,b.thickness/2,b.d/2).setTranslation(b.x,b.top-b.thickness/2,b.z).setFriction(.8));this.supportHandles.add(c.handle);this.bridgeColliders.set(b.id,c);}
  for(const w of this.map.walls)this.world.createCollider(RAPIER.ColliderDesc.cuboid(w.w/2,5,w.d/2).setTranslation(w.x,3,w.z));
  for(const b of this.map.blockers){const c=this.world.createCollider(RAPIER.ColliderDesc.cuboid(b.w/2,b.h/2,b.d/2).setTranslation(b.x,b.y,b.z));this.waterBlockers.add(c.handle);}
  for(const t of this.map.trees??[])this.world.createCollider(RAPIER.ColliderDesc.cylinder(t.trunkHeight/2,t.radius).setTranslation(t.x,t.y+t.trunkHeight/2,t.z));
  this.targets=[[-120,-110],[-130,-110],[-110,-110]].map(([x,z],i)=>({id:i+1,x,z,y:terrainHeight(x,z)+1,hp:3}));for(const [baseId,offset] of [['5',-8],['7',-8],['7',8]]){const b=this.map.bases.find(b=>b.id===baseId);this.targets.push({id:this.targets.length+1,x:b.x+offset,z:b.z,y:b.y+1,hp:3,captureTeam:'red',baseId});}this.targetColliders=new Map();
  for(const t of this.targets){const c=this.world.createCollider(RAPIER.ColliderDesc.cuboid(1.5,1,.5).setTranslation(t.x,t.y,t.z));this.targetColliders.set(c.handle,t);}
  }
  this.reset();
 }
 remove(){if(this.vehicle)this.world.removeVehicleController(this.vehicle);if(this.body)this.world.removeRigidBody(this.body);this.vehicle=null;this.body=null;}
 reset(spawn=this.map.spawn,yaw=0){
  this.remove();
  Object.assign(this,createHull(this.world));const s=spawn;this.body.setTranslation({x:s.x,y:s.y??terrainHeight(s.x,s.z)+1.5,z:s.z},true);this.body.setRotation({x:0,y:Math.sin(yaw/2),z:0,w:Math.cos(yaw/2)},true);this.stage='active';
 }
 step(dt,throttle,steer){const n=Math.ceil(dt/(1/120));for(let i=0;i<n;i++)differentialStep(this,dt/n,throttle,steer);}
 pose(){const p=this.body.translation(),q=this.body.rotation(),v=this.body.linvel(),f=rotate(q,{x:0,y:0,z:1}),right=rotate(q,{x:1,y:0,z:0}),bridge=this.map.bridges.find(b=>Math.abs(p.x-b.x)<=b.w/2&&Math.abs(p.z-b.z)<=b.d/2);
  return {x:p.x,y:p.y,z:p.z,quaternion:{...q},yaw:Math.atan2(f.x,f.z),pitch:Math.asin(Math.max(-1,Math.min(1,f.y)))*180/Math.PI,roll:Math.asin(Math.max(-1,Math.min(1,right.y)))*180/Math.PI,speed:v.x*f.x+v.y*f.y+v.z*f.z,groundHeight:bridge?.top??terrainHeight(p.x,p.z),terrain:bridge?'bridge':'grass'};
 }
 grounded(){let n=0;for(let i=0;i<this.vehicle.numWheels();i++)if(this.vehicle.wheelIsInContact(i))n++;return n>=2;}
 occupant(connected){const p=this.pose(),water=Math.abs(p.x)<8&&![-80,0,80].some(z=>Math.abs(p.z-z)<8);return {id:'tank-1',team:'blue',...p,alive:true,eligible:!!connected&&!water,grounded:this.grounded()};}
 garrisonOccupants(){return this.targets.filter(t=>t.captureTeam).map(t=>({id:'post-'+t.id,team:t.captureTeam,x:t.x,y:t.y,z:t.z,alive:t.hp>0,eligible:true,grounded:true}));}
 cast(turret,range=BATTLE_SHOT_RANGE){
  const m=muzzle(this.pose(),turret),ray=new RAPIER.Ray(m.origin,m.direction);
  const vertical=this.world.castRay(new RAPIER.Ray({x:m.origin.x,y:100,z:m.origin.z},{x:0,y:-1,z:0}),200,true,undefined,undefined,undefined,this.body,c=>this.supportHandles.has(c.handle));
  if(vertical&&m.origin.y<=100-vertical.timeOfImpact+.0001)return {origin:m.origin,direction:m.direction,distance:0,category:'terrain',target:null};
  const hit=this.world.castRay(ray,range,true,undefined,undefined,undefined,this.body,c=>!this.waterBlockers.has(c.handle));
  const candidate=hit&&this.targetColliders.get(hit.collider.handle),target=candidate?.hp>0?candidate:null;
  return {origin:m.origin,direction:m.direction,distance:hit?.timeOfImpact??range,category:target?'target':hit?'terrain':null,target:target??null,...(hit?.collider.parent()?{bodyHandle:hit.collider.parent().handle}:{})};
 }
 restartTargets(){for(const t of this.targets)t.hp=3;}
}
