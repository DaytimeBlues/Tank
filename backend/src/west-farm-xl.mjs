// A separate candidate. Preserve every authored core triangle and objective.
const CAPS = 225;
const CORE = 160;
const STEP = 5;
const clamp = (n,a,b) => Math.max(a,Math.min(b,n));

export function extendWestFarm(map) {
  if (map.size !== 320 || map.step !== STEP || map.bridges.length !== 3) throw Error("West Farm source mismatch");
  const core = new Map();
  for (const chunk of map.chunks) for(let i=0;i<chunk.vertices.length;i+=3) {
    const [x,y,z] = chunk.vertices.slice(i,i+3);
    const key = x+","+z;
    if (core.has(key) && Math.abs(core.get(key)-y)>1e-7) throw Error("Core boundary is inconsistent: "+key);
    core.set(key,y);
  }
  const height = (x,z) => {
    const prior = core.get(clamp(x,-CORE,CORE)+","+clamp(z,-CORE,CORE));
    if (prior===undefined) throw Error("No matching core sample");
    const extra = Math.max(0,Math.abs(x)-CORE,Math.abs(z)-CORE);
    const fade = Math.min(1,extra/30);
    const land = Math.min(1,Math.max(0,(Math.abs(x)-15)/28));
    const soft = Math.sin(x/31)*0.9 + Math.cos(z/37)*0.8;
    return prior + soft * fade*fade * land;
  };
  const extension = [];
  const intervals=[-225,-160,-80,0,80,160,225];
  for(let zi=0;zi<6;zi++) for(let xi=0;xi<6;xi++) {
    if(xi>0&&xi<5&&zi>0&&zi<5)continue;
    const x0=intervals[xi],z0=intervals[zi], nx=(intervals[xi+1]-x0)/STEP,nz=(intervals[zi+1]-z0)/STEP;
    const vertices=[],indices=[],colors=[];
    for(let j=0;j<=nz;j++)for(let i=0;i<=nx;i++){
      const x=x0+i*STEP,z=z0+j*STEP,y=height(x,z);
      vertices.push(x,y,z); colors.push(...(y>11?[.48,.53,.35]:[.38,.49,.29]));
    }
    for(let j=0;j<nz;j++)for(let i=0;i<nx;i++){
      const a=j*(nx+1)+i,b=a+nx+1;
      indices.push(a,b,a+1,a+1,b,b+1);
    }
    extension.push({id:"xl-"+xi+"-"+zi,vertices,indices,colors});
  }
  const blockers=map.blockers.map(b=>{
    const low=b.z-b.d/2,high=b.z+b.d/2;
    const a=low<=-CORE?-CAPS:low,c=high>=CORE?CAPS:high;
    return a===low&&c===high?b:{...b,z:(a+c)/2,d:c-a};
  });
  const output={...map,size:2*CAPS,version:3, chunks:[...map.chunks,...extension],
    blockers,water:{...map.water,d:2*CAPS},walls:[
      {x:-CAPS-1,z:0,w:2,d:2*CAPS+4},{x:CAPS+1,z:0,w:2,d:2*CAPS+4},
      {x:0,z:-CAPS-1,w:2*CAPS+4,d:2},{x:0,z:CAPS+1,w:2*CAPS+4,d:2}]};
  // Same triangle split as the render/physics grid. Runtime helper is deliberately not sent on the wire.
  Object.defineProperty(output,"heightAt",{value:(x,z)=>{
    x=clamp(x,-CAPS,CAPS); z=clamp(z,-CAPS,CAPS);
    const x0=Math.min(CAPS-STEP,Math.floor(x/STEP)*STEP),z0=Math.min(CAPS-STEP,Math.floor(z/STEP)*STEP);
    const u=(x-x0)/STEP,v=(z-z0)/STEP,h00=height(x0,z0),h10=height(x0+STEP,z0),h01=height(x0,z0+STEP),h11=height(x0+STEP,z0+STEP);
    return u+v<=1?h00+(h10-h00)*u+(h01-h00)*v:h11+(h01-h11)*(1-u)+(h10-h11)*(1-v);
  }});
  return output;
}

