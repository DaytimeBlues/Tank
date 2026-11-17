// Appearance roster; only the selected donor has a model-specific authoritative socket.
import { modelGunProfile } from './model-gun.mjs';
export const VISUALS = Object.freeze([
  {id:'kestrel', name:'Kestrel', description:'Low angular turret, long fenders and six road wheels.', kind:'Original fictional design'},
  {id:'bastion', name:'Bastion', description:'Long turret bustle, raked nose and five large road wheels.', kind:'Original fictional design'},
  {id:'foundry', name:'Foundry', description:'Rounded cast silhouette, paired bogies and a raised cupola.', kind:'Original WWII-inspired design · not a replica'},
  {id:'palisade', name:'Palisade', description:'Stepped plate hull, spaced turret shield and eight small road wheels per side.', kind:'Original Panzer IV-inspired design · not a replica'}
  ,{id:'leichttraktor', name:'Leichttraktor', description:'Cleaned grey early tank, narrow tracks and short offset cannon.', kind:'Newc42 CC0 model; shared gameplay footprint', source:'docs/assets/licensed-tank/leichttraktor.glb'}
].map(v=>Object.freeze({...v,url:`/assets/${v.id}.glb`,source:v.source??`docs/assets/original-tank/${v.id}/${v.id}.glb`})));

export async function loadTankVisuals(THREE,load,onUnavailable=()=>{}) {
  const bank=new Map();
  for(const item of VISUALS) {
    let root;
    try{
      root=(await load(item.url)).scene;
      const visual=prepareTankVisual(THREE,root,item.id);
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
  const geometries = new Set(), materials = new Set(), textures = new Set();
  root.traverse(o => { if (o.isMesh) { geometries.add(o.geometry); for (const m of Array.isArray(o.material) ? o.material : [o.material]) materials.add(m); } });
  for (const m of materials) for (const value of Object.values(m)) if(value?.isTexture) textures.add(value);
  for (const g of geometries) g.dispose(); for (const m of materials) m.dispose(); for (const t of textures) t.dispose();
}
export function prepareTankVisual(THREE, root, id='kestrel') {
  const contract=modelGunProfile(id);
  const yaw = root.getObjectByName('TurretYaw');
  const pitch = root.getObjectByName('BarrelPitch');
  const muzzle = root.getObjectByName('Muzzle');
  const barrel = root.getObjectByName('Barrel');
  if (!yaw || !pitch || !muzzle || !barrel || !root.getObjectByName('Hull')) throw new Error('Tank visual hierarchy missing');
  root.updateMatrixWorld(true);
  const rest = muzzle.getWorldPosition(new THREE.Vector3());
  if (rest.distanceTo(new THREE.Vector3(...contract.muzzle)) > 1e-5) throw new Error('Tank visual muzzle contract mismatch');
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


// Legacy single-tank modes never transmit a visual ID to their authority.
// A missing donor cannot use the old-gun primitive fallback with a new-gun socket.
export function availableTankVisuals(bank, modelSpecificMuzzles) {
  return VISUALS.filter(v=>bank.has(v.id) && (v.id!=='leichttraktor'||modelSpecificMuzzles));
}
export function selectableTankVisuals(bank, modelSpecificMuzzles) {
  const available=availableTankVisuals(bank,modelSpecificMuzzles);
  return available.length?available:VISUALS.filter(v=>v.id!=='leichttraktor');
}
export function canPresentAuthoritativeVisual(bank,id) {
  return id!=='leichttraktor'||bank.has(id);
}
export function attachTankAimGuide(THREE,line,visual,id) {
  const donor=id==='leichttraktor';
  line.geometry.setFromPoints([new THREE.Vector3(0,0,donor?0:4),new THREE.Vector3(0,0,65)]);
  line.position.set(0,0,0);line.quaternion.identity();
  (donor?visual.muzzle:visual.yaw).add(line);
}

export function canPresentBattleVisuals(bank,players) {
  return players.every(p=>canPresentAuthoritativeVisual(bank,p.visualId));
}
