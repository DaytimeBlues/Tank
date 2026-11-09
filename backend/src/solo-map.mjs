import { BATTLEFIELD_MAP, terrainHeight, roadSample } from './battlefield-map.mjs';
// Sample the same two triangles per grid cell used by render and collision.
// The analytic authoring function can differ from the rendered face between vertices.
function surfaceHeight(x,z){
  const step=BATTLEFIELD_MAP.step,half=BATTLEFIELD_MAP.size/2;
  const x0=Math.floor((x+half)/step)*step-half,z0=Math.floor((z+half)/step)*step-half;
  const u=(x-x0)/step,v=(z-z0)/step,h00=terrainHeight(x0,z0),h10=terrainHeight(x0+step,z0),h01=terrainHeight(x0,z0+step),h11=terrainHeight(x0+step,z0+step);
  return u+v<=1?h00+(h10-h00)*u+(h01-h00)*v:h11+(h01-h11)*(1-u)+(h10-h11)*(1-v);
}
const extraEdges = [['b2','w1'],['b1','w0'],['b3','w2']];
const edges = [...BATTLEFIELD_MAP.routes.edges, ...extraEdges];
const roads = [...BATTLEFIELD_MAP.roads, ...extraEdges.map(([a,b]) => {
  const point = id => {const [x,z]=BATTLEFIELD_MAP.routes.nodes[id];return {x,z,y:terrainHeight(x,z)};};
  return {a:point(a),b:point(b)};
})];
export const SOLO_SPAWNS = Object.fromEntries(['blue','red'].map(team => [team,
  [[-8,-6],[8,-6],[-8,6],[8,6]].map(([dx,dz]) => {const x=(team==='blue'?-110:110)+dx,z=(team==='blue'?-40:40)+dz;return {x,z,y:surfaceHeight(x,z)+2};})
]));
const trees=[];
for(let z=-145;z<=145;z+=18)for(let x=-145;x<=145;x+=18){
  const px=x+Math.sin(z*3+x)*4,pz=z+Math.cos(x*2-z)*4;
  if(Math.abs(px)<45||roads.some(r=>roadSample(px,pz,r).distance<14)||BATTLEFIELD_MAP.bases.some(b=>Math.hypot(px-b.x,pz-b.z)<b.radius+12)||Object.values(SOLO_SPAWNS).flat().some(s=>Math.hypot(px-s.x,pz-s.z)<18))continue;
  if(trees.length<120)trees.push({id:'tree-'+trees.length,x:px,z:pz,y:surfaceHeight(px,pz),radius:.55,trunkHeight:3.8,crown:2.3+(trees.length%3)*.3});
}
export const SOLO_MAP = {...BATTLEFIELD_MAP,version:2,trees,routes:{nodes:BATTLEFIELD_MAP.routes.nodes,edges},roads};
