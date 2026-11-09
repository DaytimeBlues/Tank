const SIZE=320,STEP=5,HALF=SIZE/2;
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const lerp=(a,b,t)=>a+(b-a)*t;
const dry=(x,z)=>8+6*Math.sin(x/65)+4*Math.cos(z/60);
const seeds=[['1','Depot',-120,-120,2],['2','Windmill',-110,-20,4],['3','West Farm',-110,100,6],['4','River Junction',0,0,1],['5','Ridge Battery',110,-100,12],['6','East Orchard',110,20,14],['7','Reservoir',110,110,10]];
const bases=seeds.map(([id,name,x,z,y])=>({id,name,x,z,y,radius:id==='4'?6:12}));
const nodes={spawn:[-120,-134],b1:[-120,-120],exit:[-90,-120],w0:[-70,-80],w1:[-70,0],w2:[-70,80],b2:[-110,-20],b3:[-110,100],b4:[0,0],e0:[70,-80],e1:[70,0],e2:[70,80],b5:[110,-100],b6:[110,20],b7:[110,110]};
const levels={spawn:2,b1:2,exit:2,w0:1,w1:1,w2:1,b2:4,b3:6,b4:1,e0:5,e1:7,e2:5,b5:12,b6:14,b7:10};
const edges=[['spawn','b1'],['b1','exit'],['exit','w0'],['w0','w1'],['w1','w2'],['w2','b3'],['b3','b2'],['b2','exit'],['w0','e0'],['w1','b4'],['b4','e1'],['w2','e2'],['e0','b5'],['b5','b6'],['b6','b7'],['e1','b6'],['e2','b7'],['e0','e1'],['e1','e2']];
const roads=[];
for(const [a,b]of edges){const start={x:nodes[a][0],z:nodes[a][1],y:levels[a]},end={x:nodes[b][0],z:nodes[b][1],y:levels[b]},points=[start];
 if(start.z===end.z&&[-80,0,80].includes(start.z)){for(const x of [-40,40])if(x>Math.min(start.x,end.x)&&x<Math.max(start.x,end.x))points.push({x,z:start.z,y:1});points.sort((p,q)=>(p.x-q.x)*Math.sign(end.x-start.x));}
 points.push(end);for(let i=1;i<points.length;i++)roads.push({a:points[i-1],b:points[i]});
}
export function roadSample(x,z,road){const dx=road.b.x-road.a.x,dz=road.b.z-road.a.z,t=clamp(((x-road.a.x)*dx+(z-road.a.z)*dz)/(dx*dx+dz*dz),0,1);return {distance:Math.hypot(x-road.a.x-t*dx,z-road.a.z-t*dz),height:lerp(road.a.y,road.b.y,t)};}
export function terrainHeight(x,z){
 const a=Math.abs(x);let h=a<=8?-2:lerp(-2,dry(x,z),clamp((a-8)/32,0,1));
 let nearest=null;for(const road of roads){const s=roadSample(x,z,road);if(!nearest||s.distance<nearest.distance)nearest=s;}
 if(nearest)h=lerp(h,nearest.height,clamp((34-nearest.distance)/26,0,1));
 const dz=Math.min(...[-80,0,80].map(c=>Math.abs(z-c)));if(a<40&&dz<8)h=a<8?-2:Math.min(h,.6);
 for(const b of bases){const d=Math.max(Math.abs(x-b.x),Math.abs(z-b.z)),core=b.id==='4'?6:15,fade=b.id==='4'?12:34;if(d<fade)h=lerp(h,b.y,clamp((fade-d)/(fade-core),0,1));}
 return h;
}
const chunks=[];
for(let cz=0;cz<4;cz++)for(let cx=0;cx<4;cx++){
 const vertices=[],indices=[],colors=[];
 for(let z=0;z<=16;z++)for(let x=0;x<=16;x++){const wx=-HALF+(cx*16+x)*STEP,wz=-HALF+(cz*16+z)*STEP,y=terrainHeight(wx,wz);vertices.push(wx,y,wz);const road=roads.some(r=>roadSample(wx,wz,r).distance<7);colors.push(...(road?[.66,.61,.46]:y>11?[.48,.53,.35]:[.38,.49,.29]));}
 for(let z=0;z<16;z++)for(let x=0;x<16;x++){const a=z*17+x;indices.push(a,a+17,a+1,a+1,a+17,a+18);}
 chunks.push({id:`terrain-${cx}-${cz}`,vertices,indices,colors});
}
const bridges=[-80,0,80].map((z,i)=>({id:`bridge-${i+1}`,x:0,z,w:80,d:16,top:1,thickness:.4}));
const blockers=[[-160,-90],[-70,-10],[10,70],[90,160]].map(([a,b],i)=>({id:`deep-${i}`,kind:'deep-water',x:0,z:(a+b)/2,w:16,d:b-a,y:2,h:10}));
const walls=[{x:-161,z:0,w:2,d:324},{x:161,z:0,w:2,d:324},{x:0,z:-161,w:324,d:2},{x:0,z:161,w:324,d:2}];
export const BATTLEFIELD_MAP={mode:'battlefield',version:1,size:SIZE,step:STEP,chunks,bridges,blockers,walls,bases,roads,water:{x:0,z:0,w:16,d:SIZE,y:.4},spawn:{x:-120,z:-134},routes:{nodes,edges}};
export function routeTo(baseId,start='spawn'){
 const goal='b'+baseId,q=[[start]],seen=new Set([start]);
 while(q.length){const p=q.shift(),n=p.at(-1);if(n===goal)return p.map(id=>({id,x:nodes[id][0],z:nodes[id][1]}));for(const [a,b]of edges){const next=a===n?b:b===n?a:null;if(next&&!seen.has(next)){seen.add(next);q.push([...p,next]);}}}
 throw new Error('Unreachable base');
}
