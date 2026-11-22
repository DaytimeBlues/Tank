// Experimental server-only observation. No traction, collision, pose or wire writes.
// Use an actual collider returned by the authoritative world, not client surface text.
export function identifyCollider(drive,collider){
 if(typeof drive?.world?.getCollider!=='function'||!drive?.supportHandles||!drive?.bridgeColliders||!drive?.waterBlockers||!drive?.map)throw new TypeError('Authoritative drive context required');
 if(collider===null)return {kind:'no-contact',id:null,support:false,wetness:'unclassified'};
 if(!collider||!Number.isFinite(collider.handle))throw new TypeError('Finite collider handle required');
 const h=collider.handle;
 if(drive.world.getCollider(h)!==collider)throw new TypeError('Collider must belong to this authoritative world');
 if(drive.waterBlockers.has(h))return {kind:'blocked-water',id:null,support:false,wetness:'not-a-drivable-surface'};
 for(const [id,c] of drive.bridgeColliders){
  if(c.handle!==h)continue;
  const kind=drive.map.bridges.some(b=>b.id===id)?'bridge-deck':(drive.map.shoulders??[]).some(b=>b.id===id)?'bridge-coping':'unknown-support';
  return {kind,id,support:drive.supportHandles.has(h),wetness:'unclassified'};
 }
 return {kind:drive.supportHandles.has(h)?'terrain':'non-support-solid',id:null,support:drive.supportHandles.has(h),wetness:'unclassified'};
}
