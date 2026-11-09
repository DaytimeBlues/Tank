// Visual-only asset contract. No gameplay profile, collision or gun rule is changed.
export const VISUALS = Object.freeze([
  {id:'kestrel', name:'Kestrel', description:'Low angular turret, long fenders and six road wheels.', kind:'Original fictional design'},
  {id:'bastion', name:'Bastion', description:'Long turret bustle, raked nose and five large road wheels.', kind:'Original fictional design'},
  {id:'foundry', name:'Foundry', description:'Rounded cast silhouette, paired bogies and a raised cupola.', kind:'Original WWII-inspired design · not a replica'},
  {id:'palisade', name:'Palisade', description:'Stepped plate hull, spaced turret shield and eight small road wheels per side.', kind:'Original Panzer IV-inspired design · not a replica'}
].map(v=>Object.freeze({...v,url:`/assets/${v.id}.glb`,source:`docs/assets/original-tank/${v.id}/${v.id}.glb`})));

export async function loadTankVisuals(THREE,load,onUnavailable=()=>{}) {
  const bank=new Map();
  for(const item of VISUALS) {
    let root;
    try{
      root=(await load(item.url)).scene;
      const visual=prepareTankVisual(THREE,root);
      visual.root.name='Visual_'+item.id;
      bank.set(item.id,visual);
    }catch(error){
      if(root)disposeResources(root);
      onUnavailable(item,error);
    }
  }
  return bank;
}
function disposeResources(root) {
  const geometries = new Set(), materials = new Set();
  root.traverse(o => { if (o.isMesh) { geometries.add(o.geometry); for (const m of Array.isArray(o.material) ? o.material : [o.material]) materials.add(m); } });
  for (const g of geometries) g.dispose(); for (const m of materials) m.dispose();
}
export function prepareTankVisual(THREE, root) {
  const yaw = root.getObjectByName('TurretYaw');
  const pitch = root.getObjectByName('BarrelPitch');
  const muzzle = root.getObjectByName('Muzzle');
  const barrel = root.getObjectByName('Barrel');
  if (!yaw || !pitch || !muzzle || !barrel || !root.getObjectByName('Hull')) throw new Error('Tank visual hierarchy missing');
  root.updateMatrixWorld(true);
  const rest = muzzle.getWorldPosition(new THREE.Vector3());
  if (rest.distanceTo(new THREE.Vector3(0, 1.65, 4.05)) > 1e-5) throw new Error('Tank visual muzzle contract mismatch');
  const barrelRestZ = barrel.position.z;
  barrel.userData.recoilRestZ = barrelRestZ;
  root.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  return { root, yaw, pitch, muzzle,
    recoil(amount) { barrel.position.z = barrelRestZ - Math.max(0, Math.min(.18, Number.isFinite(amount) ? amount : 0)); },
    pose(bearing, elevation = 0) {
      if (!Number.isFinite(bearing) || !Number.isFinite(elevation)) throw new Error('Finite visual pose required');
      yaw.rotation.y = bearing; pitch.rotation.x = elevation;
    },
    dispose() {
      // Clones borrow these resources; call once after all preview/game users stop.
      disposeResources(root);
    }
  };
}
