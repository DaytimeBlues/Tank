// Shared-data-only solid installation. Never add these handles to waterBlockers.
export function installRoadsideCover(RAPIER,world,cover){
 const handles=new Set();
 for(const b of cover){
  if(!['x','y','z','w','h','d'].every(k=>Number.isFinite(b[k]))||[b.w,b.h,b.d].some(v=>v<=0))throw Error('Invalid cover bounds');
  const c=world.createCollider(RAPIER.ColliderDesc.cuboid(b.w/2,b.h/2,b.d/2).setTranslation(b.x,b.y,b.z).setFriction(.85));
  handles.add(c.handle);
 }
 return handles;
}
