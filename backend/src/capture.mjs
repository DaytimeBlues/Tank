export function freshBases(definitions) {
  return definitions.map(b=>({...b,owner:'neutral',progress:0,blue:0,red:0,net:0,contested:false}));
}
export function advanceCaptures(bases,occupants,dt) {
  if(!Number.isFinite(dt)||dt<=0||dt>1)throw new Error('Invalid capture timestep');
  const events=[];
  for(const b of bases){
    const counts={blue:0,red:0},seen=new Set();
    for(const u of occupants){
      if(!u || typeof u.id!=='string'||seen.has(u.id)||u.alive!==true||u.eligible!==true||u.grounded!==true||!['blue','red'].includes(u.team)||![u.x,u.y,u.z].every(Number.isFinite))continue;
      seen.add(u.id);if(Math.hypot(u.x-b.x,u.z-b.z)<=b.radius&&Math.abs(u.y-(b.y+1.05))<=.65)counts[u.team]++;
    }
    b.blue=counts.blue;b.red=counts.red;b.net=b.blue-b.red;b.contested=b.blue>0&&b.red>0;
    b.progress=Math.max(-1,Math.min(1,b.progress+dt*.08*b.net));
    if(Math.abs(1-b.progress)<1e-9)b.progress=1;if(Math.abs(-1-b.progress)<1e-9)b.progress=-1;
    const owner=b.progress===1?'blue':b.progress===-1?'red':b.owner;
    if(owner!==b.owner){const previous=b.owner;b.owner=owner;events.push({baseId:b.id,previous,owner});}
  }
  return events;
}
