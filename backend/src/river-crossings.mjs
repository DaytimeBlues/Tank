// The deck remains the sole support across the center; the barrel is solid cover only.
export function riverCrossings(map) {
  const channels = new Map([[0,-3.6],[5,-3.3],[10,-0.3]]);
  const chunks = map.chunks.map(chunk => {
    const vertices = chunk.vertices.slice();
    for (let i=0;i<vertices.length;i+=3) {
      const h=channels.get(Math.abs(vertices[i]));
      if(h!==undefined) vertices[i+1]=h;
    }
    return {...chunk,vertices};
  });
  const arches=map.bridges.map(b=>{
    const vertices=[], indices=[], segments=42, width=10;
    for(let j=0;j<=segments;j++){
      const x=j===0?-15:j===segments?15:width*((j-1)/20-1);
      // The buried end at ±15 closes the triangular daylight gap between the barrel and grade.
      const soffit=Math.abs(x)>width?-1.0:.15-2.75*(x/width)**2;
      for(const [dz,y] of [[-b.d/2,soffit],[-b.d/2,b.top-b.thickness],[b.d/2,b.top-b.thickness],[b.d/2,soffit]])
        vertices.push(b.x+x,y,b.z+dz);
      if(j) for(let k=0;k<4;k++){
        const a=(j-1)*4+k,f=(j-1)*4+(k+1)%4;
        indices.push(a,f,a+4,f,f+4,a+4);
      }
    }
    const e=segments*4;
    indices.push(0,1,2,0,2,3,e,e+2,e+1,e,e+3,e+2);
    return {id:b.id+'-barrel',vertices,indices};
  });
  const shoulders=map.bridges.flatMap(b=>[-1,1].map(side=>({
    id:b.id+'-coping-'+(side<0?'north':'south'), x:b.x,z:b.z+side*(b.d/2+.95),
    w:b.w,d:1.9,top:b.top+.025,thickness:b.thickness+.025
  })));
  return {...map,chunks,water:{...map.water,y:-1.5},arches,shoulders};
}


// Only the five re-authored columns and their immediately adjacent triangles
// need a different ground-height observation; suspension still uses Rapier.
const riverGrids=new WeakMap();
export function riverGroundHeight(map,x,z,fallback) {
 if(!map.arches||Math.abs(x)>=15||Math.abs(z)>=map.size/2)return fallback(x,z);
 let rows=riverGrids.get(map);
 if(!rows){
  rows=new Map();
  for(const chunk of map.chunks)for(let i=0;i<chunk.vertices.length;i+=3){
   const [vx,y,vz]=chunk.vertices.slice(i,i+3);
   if(Math.abs(vx)<=15)rows.set(vx+','+vz,y);
  }
  riverGrids.set(map,rows);
 }
 const step=map.step,x0=Math.floor(x/step)*step,z0=Math.floor(z/step)*step;
 const u=(x-x0)/step,v=(z-z0)/step;
 const h=(dx,dz)=>rows.get((x0+dx*step)+','+(z0+dz*step));
 return u+v<=1?h(0,0)*(1-u-v)+h(1,0)*u+h(0,1)*v:h(1,1)*(u+v-1)+h(1,0)*(1-v)+h(0,1)*(1-u);
}

