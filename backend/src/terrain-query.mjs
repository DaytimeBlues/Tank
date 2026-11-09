import RAPIER from '@dimforge/rapier3d-compat';
import { rotate } from './suspension.mjs';

const EPS=1e-4;
function vector(p) { if (!p || !['x','y','z'].every(k=>Number.isFinite(p[k]))) throw new Error('Finite vector required'); }
// Resting primitives only: turret y1.65 minus rendered hull-centre offset1;
// barrel centre z2.3 + half length1.75. No recoil or elevation contract.
export function muzzle(pose,yaw) {
 vector(pose); const q=pose.quaternion;
 if(!q || !['x','y','z','w'].every(k=>Number.isFinite(q[k])) || Math.abs(Math.hypot(q.x,q.y,q.z,q.w)-1)>1e-6 || !Number.isFinite(yaw)) throw new Error('Unit quaternion and finite turret required');
 const offset=rotate(q,{x:4.05*Math.sin(yaw),y:.65,z:4.05*Math.cos(yaw)});
 const direction=rotate(q,{x:Math.sin(yaw),y:0,z:Math.cos(yaw)});
 return {origin:{x:pose.x+offset.x,y:pose.y+offset.y,z:pose.z+offset.z},direction};
}
// Finite observation/muzzle segment, explicitly supplied origins. Only the
// single-valued GradeDrive footprint is supported; contact within EPS blocks.
export function segment(grade,origin,endpoint) {
 vector(origin);vector(endpoint);
 const delta={x:endpoint.x-origin.x,y:endpoint.y-origin.y,z:endpoint.z-origin.z};
 const length=Math.hypot(delta.x,delta.y,delta.z);
 if(length<1e-8 || length>90 || Math.abs(origin.x)>40 || Math.abs(origin.z)>40 || Math.abs(origin.y)>90) throw new Error('Segment outside terrain-query domain');
 const hit=(category,distance)=>({blocked:true,category,distance,length});
 if(grade.ground) {
  const toi=grade.ground.castRay(new RAPIER.Ray({x:origin.x,y:100,z:origin.z},{x:0,y:-1,z:0}),200,true);
  if(toi>=0 && origin.y<=100-toi+EPS) return hit('terrain',0);
 }
 let embedded=null;
 grade.world.forEachCollider(c=>{
  if(c.handle!==grade.ground?.handle && c.parent()?.handle!==grade.body?.handle && c.containsPoint(origin)) embedded=c;
 });
 if(embedded) return hit(embedded.parent()?'body':'wall',0);
 const direction={x:delta.x/length,y:delta.y/length,z:delta.z/length};
 const result=grade.world.castRay(new RAPIER.Ray(origin,direction),length+EPS,true,undefined,undefined,undefined,grade.body);
 if(!result || result.timeOfImpact>length+EPS) return {blocked:false,category:null,distance:null,length};
 return hit(result.collider.handle===grade.ground?.handle?'terrain':result.collider.parent()?'body':'wall',result.timeOfImpact);
}

