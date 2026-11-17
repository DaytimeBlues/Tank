// Trusted finite model profiles. Selection is validated by the server; clients never send socket positions.
const point = values => Object.freeze(values);
export const LEICHTTRAKTOR_FIT = point([-.00031380355358125, -.04230314839210833, -.7424500061294334]);
export const LEICHTTRAKTOR_RAW_MUZZLE = point([.13670215904712676, 1.9453777717831633, 1.8411025962448133]);
export const LEICHTTRAKTOR_RAW_PIVOT = point([0, 1.13540318962268, .00000015255145]);
const fitted = p => point(p.map((v,i) => v + LEICHTTRAKTOR_FIT[i]));
const original = Object.freeze({muzzle:point([0,1.65,4.05]), pivot:point([0,1.65,0]), mount:null});
const donor = Object.freeze({muzzle:fitted(LEICHTTRAKTOR_RAW_MUZZLE), pivot:fitted(LEICHTTRAKTOR_RAW_PIVOT),
  mount:fitted([LEICHTTRAKTOR_RAW_MUZZLE[0],LEICHTTRAKTOR_RAW_MUZZLE[1],LEICHTTRAKTOR_RAW_PIVOT[2]])});
export function modelGunProfile(id='kestrel') {
  if (['kestrel','bastion','foundry','palisade'].includes(id)) return original;
  if (id==='leichttraktor') return donor;
  throw new Error('Unknown tank visual');
}
