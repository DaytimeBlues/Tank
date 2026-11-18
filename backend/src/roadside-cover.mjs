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

// Exact authored static mesh triangles preserve gaps/roof silhouettes, not coarse box cover.
export function installDistrictMeshes(RAPIER,world,placements){
 if(!Array.isArray(placements)||placements.length>32)throw Error('Invalid district placements');
 const handles=new Set();
 // Validate every authored mesh before allocating any collider.
 for(const p of placements){
  const v=p.vertices,ix=p.indices;
  if(!Array.isArray(v)||v.length<9||v.length%3||v.length>6000||!v.every(n=>Number.isFinite(n)&&Math.abs(n)<=1000)||!Array.isArray(ix)||ix.length<3||ix.length%3||ix.length>12000||!ix.every(i=>Number.isInteger(i)&&i>=0&&i<v.length/3))throw Error('Invalid district triangle geometry');
 }
 for(const p of placements){
  const c=world.createCollider(RAPIER.ColliderDesc.trimesh(new Float32Array(p.vertices),new Uint32Array(p.indices)).setFriction(.85));handles.add(c.handle);
 }
 return handles;
}
