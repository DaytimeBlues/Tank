export const TANKS=Object.freeze([{id:'prototype',name:'Field prototype',role:'Capture and manoeuvre',forwardMps:3,damage:1,reloadSeconds:4,durability:null,massKg:1000,
 strengths:['One player controls driving and aiming','Assisted suspension and pivot steering'],tradeoffs:['Primitive model — not final tank art','Armour and tank damage are not modelled','Turning reduces drive target speed']}].map(Object.freeze));
export function tankProfile(id='prototype'){const t=TANKS.find(x=>x.id===id);if(!t)throw new Error('Unknown tank configuration');return t;}
export function selectionState(catalog=TANKS,initial=catalog[0].id){
 let committed=initial,preview=initial;
 const valid=id=>{if(!catalog.some(t=>t.id===id))throw new Error('Unknown tank preview');return id;};valid(initial);
 return {open(){preview=committed;return preview;},browse(id){preview=valid(id);return preview;},confirm(){committed=preview;return committed;},back(){preview=committed;return committed;},get committed(){return committed;},get preview(){return preview;}};
}
