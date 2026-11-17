export const PROJECTILE_RULES = Object.freeze({ speed:60, range:90, cap:32, impactCap:32, impactSeconds:1 });
// Bounded, deterministic authority state; caller supplies the world's swept query.
export class ProjectilePool {
 constructor(){ this.active=[]; this.impacts=[]; }
 clear(){this.active=[];this.impacts=[];}
 removeOwner(id){this.active=this.active.filter(p=>p.ownerId!==id);}
 launch(p){if(this.active.length>=PROJECTILE_RULES.cap)return false;this.active.push({...p,remaining:PROJECTILE_RULES.range,speed:PROJECTILE_RULES.speed});return true;}
 impact(p,position,time,result={}){this.impacts.push({id:p.id,ownerId:p.ownerId,...position,time,hit:result.hit??null,blocked:!!result.blocked});if(this.impacts.length>PROJECTILE_RULES.impactCap)this.impacts.splice(0,this.impacts.length-PROJECTILE_RULES.impactCap);}
 step(dt,time,sweep){
  this.impacts=this.impacts.filter(i=>time-i.time<PROJECTILE_RULES.impactSeconds);
  const alive=[];
  for(const p of this.active){
   const distance=Math.min(p.remaining,p.speed*dt), result=sweep(p,distance);
   const travel=result?Math.max(0,Math.min(distance,result.distance)):distance;
   p.x+=p.dx*travel;p.y+=p.dy*travel;p.z+=p.dz*travel;p.remaining-=travel;
   if(result)this.impact(p,{x:p.x,y:p.y,z:p.z},time,result);
   else if(p.remaining>1e-6)alive.push(p);
  }
  this.active=alive;
 }
 snapshot(){return {projectiles:this.active.map(({id,ownerId,x,y,z,dx,dy,dz,speed,time})=>({id,ownerId,x,y,z,dx,dy,dz,speed,time})),impacts:this.impacts.map(i=>({...i}))};}
}
