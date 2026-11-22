import fs from 'node:fs';
import {createHash} from 'node:crypto';
import RAPIER from '@dimforge/rapier3d-compat';

const read = name => fs.readFileSync(new URL(name, import.meta.url));
const geometryBytes = read('metadata.json');
if (createHash('sha256').update(geometryBytes).digest('hex') !== 'cbec9e5b67b627b5b9c75a3b5854e352dff92b54a2c9d180b98ee56d17dea441') throw Error('Quarry fixture identity mismatch');
const geometry = JSON.parse(geometryBytes);
const heightGrid = new Float32Array(231 * 191);
heightGrid.fill(NaN);
const chunks = ['00','01','10','11'].map(tile => {
  const bytes = read('tile'+tile+'.raw');
  const n = bytes.readUInt32LE(0), count = bytes.readUInt32LE(4);
  if (n !== 11136 || count !== 65550 || bytes.length !== 8+40*n+4*count) throw Error('Invalid terrain data');
  const vertices = new Float32Array(3*n), indices = new Uint32Array(count);
  for (let i=0; i<vertices.length; i++) vertices[i]=bytes.readFloatLE(8+i*4);
  for (let i=0; i<count; i++) indices[i]=bytes.readUInt32LE(8+40*n+i*4);
  for (let i=0; i<vertices.length; i+=3) {
    const cell=(vertices[i]+230)/2 + 231*(vertices[i+2]+190)/2;
    if (Number.isFinite(heightGrid[cell]) && heightGrid[cell]!==vertices[i+1]) throw Error('Quarry tile seam mismatch');
    heightGrid[cell]=vertices[i+1];
  }
  return {id:'tile'+tile,vertices,indices};
});
if (!heightGrid.every(Number.isFinite)) throw Error('Incomplete Quarry terrain');
function heightAt(x,z) {
  const col=Math.min(230, Math.max(0,(x+230)/2)), row=Math.min(190,Math.max(0,(z+190)/2));
  const ix=Math.min(229,Math.floor(col)), iz=Math.min(189,Math.floor(row));
  const a=ix+231*iz, u=col-ix, v=row-iz;
  return u+v<=1 ? heightGrid[a]*(1-u-v)+heightGrid[a+1]*u+heightGrid[a+231]*v :
    heightGrid[a+1]*(1-v)+heightGrid[a+231]*(1-u)+heightGrid[a+232]*(u+v-1);
}
function installSolids(world,waterBlockers) {
  for (const box of [...geometry.boxes,...geometry.boundaries]) {
    const [x,y,z]=box.position, [w,h,d]=box.size;
    const yaw=Math.atan2(box.basis[2][0],box.basis[2][2]);
    if(Math.abs(box.basis[1][1]-1)>1e-5) throw Error('Tilted box requires full orientation');
    world.createCollider(RAPIER.ColliderDesc.cuboid(w/2,h/2,d/2).setTranslation(x,y,z)
      .setRotation({x:0,y:Math.sin(yaw/2),z:0,w:Math.cos(yaw/2)}).setFriction(.8));
  }
  const shape=RAPIER.ColliderDesc.convexHull(Float32Array.from(geometry.shore.world_points.flat()));
  if(!shape) throw Error('Invalid Quarry shore');
  waterBlockers.add(world.createCollider(shape).handle);
}
const shoreline=geometry.shore.world_points.slice(0,24);
function inPond(x,z) {
  return shoreline.every(([ax,,az],i)=>{
    const [bx,,bz]=shoreline[(i+1)%shoreline.length];
    return (bx-ax)*(z-az)-(bz-az)*(x-ax)>=0;
  });
}
const bases=geometry.objectives.map(({name,title,position:[x,,z],radius})=>({
  id:String(name.charCodeAt(0)-64),name:title,x,y:heightAt(x,z),z,radius
}));
export const quarrySpawns = Object.fromEntries(geometry.spawns.map(({name,position:[x,y,z]})=>[name==='North'?'blue':'red',[{x,y,z}]]));
const admission={id:'redstone-quarry',revision:'23950971a5657934d7c6b8675b728da8a99536b82294ac95c640746fc239f895',mode:'battle',version:101,size:460,step:2,bases,bridges:[],trees:[]};
export const quarryMap={...admission,admission,chunks,heightAt,inPond,installSolids,spawn:quarrySpawns.blue[0],walls:[],blockers:[]};

